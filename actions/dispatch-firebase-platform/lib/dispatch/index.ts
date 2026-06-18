import type { VariableSpec } from "../tfc/index.js";
import type { FirebasePlatformConfig, Settings } from "../settings/index.js";

// ---------------------------------------------------------------------------
// settings.yml placeholder 展開 (`${service}` / `${env}` + 外部注入系)
//
// 用途: 同 service 配下で env を跨いで anchor を共有しつつ、env 固有の値
// (例: Cloud SQL instance_id) だけ env-prefix で分離したい時に使う。
// + ci_service_account.wif.pool_resource_name のように bootstrap project 由来の
// インフラ識別子も placeholder 化したいケースに対応 (`${BOOTSTRAP_PROJECT_NUMBER}`)。
//
// 展開対象:
//   - `${service}` → settings.service の値 (例: "graphql-svc") — yml-internal
//   - `${env}`     → 現在の env key (例: "dev-001")              — yml-internal
//   - `${BOOTSTRAP_PROJECT_NUMBER}` → Action input
//                                    bootstrap_project_number     — external 注入
//
// 命名規約:
//   - lowercase (`${service}` / `${env}`) … yml 内由来 (= service repo の SoT)
//   - UPPERCASE prefix (`${BOOTSTRAP_*}`) … 外部 (orchestrator / secret) から
//     Action input 経由で注入されるインフラ識別子
//   利用者が yml を読んだ瞬間に「これは yml-internal か / 外部注入か」を区別できる。
//
// 適用範囲: firebase_platform 配下の **string 値のみ** を再帰的に走査して
// 置換する (object のキーは対象外、number/bool/null はそのまま)。
//
// 未知の placeholder (例: `${foo}`) はそのまま残るので、後段の HCL render で
// terraform 用に `$${...}` にエスケープされる。
//
// fail-fast: yml が `${BOOTSTRAP_PROJECT_NUMBER}` を参照しているのに ctx で
// 値が空 (= Action input 未指定 or 空文字) の場合は展開時点で throw する。
// 展開後の `projects//locations/...` のような壊れた literal を Action 後続
// (TFC variable sync など) に流さない。
//
// 設計選択 (個別 input vs 汎用 map): 現状外部注入の placeholder は
// `BOOTSTRAP_PROJECT_NUMBER` の 1 件のみ。`BOOTSTRAP_POOL_ID` /
// `BOOTSTRAP_PROVIDER_ID` は project-bootstrap 規約で固定値想定なので
// 可変化の現実的な理由が薄い。3 件超に増えたら `external_placeholders:
// Record<string,string>` に refactor する (YAGNI)。
// ---------------------------------------------------------------------------

export interface PlaceholderContext {
  service: string;
  env: string;
  // 外部注入系 (UPPERCASE prefix の `${BOOTSTRAP_*}`)。
  // 未指定 (undefined / "") かつ yml が参照していれば expand 時に throw する。
  bootstrapProjectNumber?: string;
}

const BOOTSTRAP_PROJECT_NUMBER_TOKEN = "${BOOTSTRAP_PROJECT_NUMBER}";

const expandStringPlaceholders = (
  val: string,
  ctx: PlaceholderContext,
): string => {
  // fail-fast: 参照あり & 未注入 → 後段に壊れた literal を流さない。
  if (val.includes(BOOTSTRAP_PROJECT_NUMBER_TOKEN) && !ctx.bootstrapProjectNumber) {
    throw new Error(
      `settings.yml references \${BOOTSTRAP_PROJECT_NUMBER} but the dispatch-firebase-platform Action did not receive a non-empty 'bootstrap_project_number' input. Pass it via 'with.bootstrap_project_number' (typically from the repo Variable BOOTSTRAP_PROJECT_NUMBER).`,
    );
  }
  return val
    .replace(/\$\{service\}/g, ctx.service)
    .replace(/\$\{env\}/g, ctx.env)
    .replace(
      /\$\{BOOTSTRAP_PROJECT_NUMBER\}/g,
      ctx.bootstrapProjectNumber ?? "",
    );
};

const deepExpandPlaceholders = (
  val: unknown,
  ctx: PlaceholderContext,
): unknown => {
  if (typeof val === "string") return expandStringPlaceholders(val, ctx);
  if (Array.isArray(val)) return val.map((v) => deepExpandPlaceholders(v, ctx));
  if (val !== null && typeof val === "object") {
    return Object.fromEntries(
      Object.entries(val as Record<string, unknown>).map(([k, v]) => [
        k,
        deepExpandPlaceholders(v, ctx),
      ]),
    );
  }
  return val;
};

/**
 * firebase_platform 全体の string 値を再帰走査して `${service}` / `${env}` を
 * ctx の値で置換する。返り値は新オブジェクト (input は不変)。
 *
 * 例:
 *   expandFirebasePlatformPlaceholders(
 *     { data_connect: [{ cloud_sql: { instance_id: "${service}-${env}-fdc" } }] },
 *     { service: "graphql-svc", env: "dev-001" }
 *   )
 *   →
 *   { data_connect: [{ cloud_sql: { instance_id: "graphql-svc-dev-001-fdc" } }] }
 */
export const expandFirebasePlatformPlaceholders = (
  firebasePlatform: FirebasePlatformConfig,
  ctx: PlaceholderContext,
): FirebasePlatformConfig =>
  deepExpandPlaceholders(firebasePlatform, ctx) as FirebasePlatformConfig;

// ---------------------------------------------------------------------------
// Workspace name expansion
// ---------------------------------------------------------------------------

export function expandWorkspaceName(
  pattern: string,
  vars: Record<string, string>,
): string {
  let result = pattern;
  for (const [key, value] of Object.entries(vars)) {
    result = result.replaceAll(`{${key}}`, value);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Apply policy resolution
// ---------------------------------------------------------------------------

export function resolveAutoApply(
  policy: string,
  env: string,
): boolean {
  switch (policy) {
    case "auto":
      return true;
    case "manual":
      return false;
    case "env-based":
      // env key is the project_id suffix (e.g. "dev-001", "prd-001").
      // Anything that starts with "dev" auto-applies.
      return env.startsWith("dev");
    default:
      throw new Error(
        `Unknown apply_policy "${policy}". Must be "auto", "manual", or "env-based".`,
      );
  }
}

// ---------------------------------------------------------------------------
// Feature flag conversion: null | true | object → HCL literal
// ---------------------------------------------------------------------------

// 単数 feature (null | true | false | object) を取る key 群。
const FEATURE_KEYS = [
  "firebase",
  "authentication",
  "rtdb",
  "storage",
  "fcm",
  "remote_config",
  "app_check",
  "crashlytics",
  "performance",
  "analytics",
  "extensions",
  "secret_manager",
  "cloud_tasks",
  "cloud_scheduler",
  "pubsub",
  "eventarc",
  "cloud_run",
  "cloud_functions",
] as const;

// 複数 instance 持てる feature (null | array of objects) を取る key 群。
// apps / hosting / app_hosting は同 project 内で複数登録できるため、
// settings.yml で配列を書いてもらい、Terraform 側で for_each で展開する。
// apps は type=web/ios/android で discriminate する union 形式。
const LIST_FEATURE_KEYS = [
  "apps",
  "hosting",
  "app_hosting",
  "firestore",
  "data_connect",
] as const;

const PASSTHROUGH_KEYS = [
  "region",
  "additional_apis",
  "users",
  "ci_service_account",
  "service_accounts",
] as const;

function toHclValue(val: unknown): string {
  if (val === null || val === undefined) return "null";
  if (val === true) return "true";
  if (val === false) return "false";
  if (typeof val === "number") return String(val);
  if (typeof val === "string") {
    const escaped = val.replace(/\$\{/g, "$$$${").replace(/%\{/g, "%%{");
    return JSON.stringify(escaped);
  }
  if (Array.isArray(val)) {
    const items = val.map(toHclValue);
    return `[${items.join(", ")}]`;
  }
  if (typeof val === "object") {
    const entries = Object.entries(val as Record<string, unknown>).map(
      ([k, v]) => `${JSON.stringify(k)} = ${toHclValue(v)}`,
    );
    return `{ ${entries.join(", ")} }`;
  }
  return JSON.stringify(val);
}

/**
 * Normalize a feature flag value (single-instance features).
 *   null / undefined → null
 *   true / "true" → true
 *   false / "false" → null  (disable the feature)
 *   object → the object itself (passed as HCL)
 *
 * Throws for unexpected types (number, array, non-boolean string, etc.)
 */
function normalizeFeatureFlag(key: string, val: unknown): unknown {
  if (val === null || val === undefined) return null;
  if (val === true || val === "true") return true;
  if (val === false || val === "false") return null;
  if (Array.isArray(val)) {
    throw new Error(
      `Invalid value for feature key "${key}": expected null, boolean, or object but got array`,
    );
  }
  if (typeof val === "object") return val;
  throw new Error(
    `Invalid value for feature key "${key}": expected null, boolean, or object but got ${typeof val} (${JSON.stringify(val)})`,
  );
}

/**
 * Normalize a list-feature value (multi-instance features: apps / hosting /
 * app_hosting)。
 *   null / undefined → null
 *   false / "false" → null  (disable the feature)
 *   array → array (validated as object-array、apps の場合は type discrimination も check)
 *   その他 → throw
 *
 * 単数 object / true / 文字列の各 shorthand はサポートしない (array にしてから
 * 渡す前提)。
 *
 * apps の場合の追加 validation (Terraform module 側でも check されるが、Action
 * 側で早めに落として fail-fast):
 *   - 各 entry の type は "web" | "ios" | "android"
 *   - type=ios なら bundle_id required (空文字でも error)
 *   - type=android なら package_name required
 */
const APPS_VALID_TYPES = new Set(["web", "ios", "android"]);

function normalizeListFeatureFlag(key: string, val: unknown): unknown {
  if (val === null || val === undefined) return null;
  if (val === false || val === "false") return null;
  if (Array.isArray(val)) {
    for (let i = 0; i < val.length; i++) {
      const item = val[i];
      if (item === null || typeof item !== "object" || Array.isArray(item)) {
        throw new Error(
          `Invalid value for list-feature key "${key}" at index ${i}: expected an object but got ${
            Array.isArray(item) ? "array" : typeof item
          } (${JSON.stringify(item)})`,
        );
      }
      if (key === "apps") {
        validateAppEntry(i, item as Record<string, unknown>);
      }
      if (key === "firestore") {
        validateFirestoreEntry(i, item as Record<string, unknown>);
      }
      if (key === "data_connect") {
        validateDataConnectEntry(i, item as Record<string, unknown>);
      }
    }
    return val;
  }
  throw new Error(
    `Invalid value for list-feature key "${key}": expected null or array of objects but got ${typeof val} (${JSON.stringify(val)})`,
  );
}

const FIRESTORE_VALID_TYPES = new Set(["FIRESTORE_NATIVE", "DATASTORE_MODE"]);

function validateFirestoreEntry(
  index: number,
  entry: Record<string, unknown>,
): void {
  const databaseId = entry.database_id;
  if (typeof databaseId !== "string" || databaseId === "") {
    throw new Error(
      `firestore[${index}]: 'database_id' is required and must be a non-empty string (got ${JSON.stringify(databaseId)})`,
    );
  }
  if (entry.type !== undefined && !FIRESTORE_VALID_TYPES.has(entry.type as string)) {
    throw new Error(
      `firestore[${index}] (database_id="${databaseId}"): 'type' must be "FIRESTORE_NATIVE" or "DATASTORE_MODE" (got ${JSON.stringify(entry.type)})`,
    );
  }
}

function validateDataConnectEntry(
  index: number,
  entry: Record<string, unknown>,
): void {
  const serviceId = entry.service_id;
  if (typeof serviceId !== "string" || serviceId === "") {
    throw new Error(
      `data_connect[${index}]: 'service_id' is required and must be a non-empty string (got ${JSON.stringify(serviceId)})`,
    );
  }
  const cloudSql = entry.cloud_sql;
  if (cloudSql === null || typeof cloudSql !== "object" || Array.isArray(cloudSql)) {
    throw new Error(
      `data_connect[${index}] (service_id="${serviceId}"): 'cloud_sql' is required and must be an object`,
    );
  }
  const cs = cloudSql as Record<string, unknown>;
  if (typeof cs.instance_id !== "string" || cs.instance_id === "") {
    throw new Error(
      `data_connect[${index}] (service_id="${serviceId}"): 'cloud_sql.instance_id' is required and must be a non-empty string`,
    );
  }
  if (typeof cs.database !== "string" || cs.database === "") {
    throw new Error(
      `data_connect[${index}] (service_id="${serviceId}"): 'cloud_sql.database' is required and must be a non-empty string`,
    );
  }
}

function validateAppEntry(
  index: number,
  entry: Record<string, unknown>,
): void {
  const name = entry.name;
  if (typeof name !== "string" || name === "") {
    throw new Error(
      `apps[${index}]: 'name' is required and must be a non-empty string (got ${JSON.stringify(name)})`,
    );
  }
  const type = entry.type;
  if (typeof type !== "string" || !APPS_VALID_TYPES.has(type)) {
    throw new Error(
      `apps[${index}] (name="${name}"): 'type' must be one of "web" | "ios" | "android" (got ${JSON.stringify(type)})`,
    );
  }
  if (type === "ios") {
    if (typeof entry.bundle_id !== "string" || entry.bundle_id === "") {
      throw new Error(
        `apps[${index}] (name="${name}", type="ios"): 'bundle_id' is required and must be a non-empty string`,
      );
    }
  }
  if (type === "android") {
    if (typeof entry.package_name !== "string" || entry.package_name === "") {
      throw new Error(
        `apps[${index}] (name="${name}", type="android"): 'package_name' is required and must be a non-empty string`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Build Terraform variable specs from firebase_platform config
// ---------------------------------------------------------------------------

export function buildTerraformVariables(
  projectId: string,
  firebasePlatform: FirebasePlatformConfig,
): VariableSpec[] {
  const vars: VariableSpec[] = [];

  vars.push({
    key: "project_id",
    value: projectId,
    category: "terraform",
    hcl: false,
    sensitive: false,
  });

  for (const key of FEATURE_KEYS) {
    const raw = firebasePlatform[key];
    const normalized = normalizeFeatureFlag(key, raw);
    vars.push({
      key,
      value: toHclValue(normalized),
      category: "terraform",
      hcl: true,
      sensitive: false,
    });
  }

  for (const key of LIST_FEATURE_KEYS) {
    const raw = firebasePlatform[key];
    const normalized = normalizeListFeatureFlag(key, raw);
    vars.push({
      key,
      value: toHclValue(normalized),
      category: "terraform",
      hcl: true,
      sensitive: false,
    });
  }

  for (const key of PASSTHROUGH_KEYS) {
    const raw = firebasePlatform[key];
    if (raw !== undefined) {
      vars.push({
        key,
        value: toHclValue(raw),
        category: "terraform",
        hcl: true,
        sensitive: false,
      });
    }
  }

  return vars;
}

// ---------------------------------------------------------------------------
// Build environment variable specs for TFC Dynamic Credentials
// ---------------------------------------------------------------------------

export function buildEnvVariables(
  saEmail: string,
  targetProjectId: string,
  bootstrapProjectNumber: string,
  poolId: string,
  providerId: string,
): VariableSpec[] {
  const wifProvider = bootstrapProjectNumber
    ? `projects/${bootstrapProjectNumber}/locations/global/workloadIdentityPools/${poolId}/providers/${providerId}`
    : "";

  return [
    {
      key: "TFC_GCP_PROVIDER_AUTH",
      value: "true",
      category: "env",
      hcl: false,
      sensitive: false,
    },
    {
      key: "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL",
      value: saEmail,
      category: "env",
      hcl: false,
      sensitive: false,
    },
    {
      key: "TFC_GCP_WORKLOAD_PROVIDER_NAME",
      value: wifProvider,
      category: "env",
      hcl: false,
      sensitive: false,
    },
    {
      key: "GOOGLE_PROJECT",
      value: targetProjectId,
      category: "env",
      hcl: false,
      sensitive: false,
    },
  ];
}

// ---------------------------------------------------------------------------
// Run message (metadata JSON for Phase 2 webhook routing)
// ---------------------------------------------------------------------------

export interface RunMessageMeta {
  service: string;
  environments: string[];
  labels: string[];
  source_repo: string;
  sha: string;
  // 使用する terraform-google-platform module バージョン。TFC コンソールの
  // run message でどの版が適用されたか一目で分かるようにするため含める。
  module_version: string;
}

export function buildRunMessage(meta: RunMessageMeta): string {
  return JSON.stringify(meta);
}

// ---------------------------------------------------------------------------
// Environment gating (status + label regex AND match)
// ---------------------------------------------------------------------------

export type SkipReason = "status_inactive" | "labels_mismatch";

export interface SkipDecision {
  skip: boolean;
  reason?: SkipReason;
  detail?: string;
}

export function parseLabelsInput(raw: string): string[] {
  const trimmed = raw.trim();
  if (trimmed === "") return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch (e) {
    throw new Error(
      `Invalid labels input: expected a JSON array of strings (e.g. '["^tier:dev$","^region:apne1$"]'), got ${JSON.stringify(raw)} — ${
        e instanceof Error ? e.message : String(e)
      }`,
    );
  }
  if (!Array.isArray(parsed)) {
    throw new Error(
      `Invalid labels input: expected a JSON array of strings, got ${typeof parsed}`,
    );
  }
  return parsed.map((v, i) => {
    if (typeof v !== "string") {
      throw new Error(
        `Invalid labels input: element [${i}] must be a string, got ${typeof v} (${JSON.stringify(v)})`,
      );
    }
    return v;
  });
}

/**
 * Parse the `environments` input — a JSON array string of env key names.
 * Returns [] for empty / whitespace-only input. Throws on malformed JSON,
 * non-array values, or non-string elements. Duplicate entries are deduped
 * while preserving first-seen order.
 */
export function parseEnvironmentsInput(raw: string): string[] {
  const trimmed = raw.trim();
  if (trimmed === "") return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch (e) {
    throw new Error(
      `Invalid environments input: expected a JSON array of env key strings (e.g. '["dev-001","dev-002"]'), got ${JSON.stringify(raw)} — ${
        e instanceof Error ? e.message : String(e)
      }`,
    );
  }
  if (!Array.isArray(parsed)) {
    throw new Error(
      `Invalid environments input: expected a JSON array of strings, got ${typeof parsed}`,
    );
  }
  const seen = new Set<string>();
  const out: string[] = [];
  parsed.forEach((v, i) => {
    if (typeof v !== "string") {
      throw new Error(
        `Invalid environments input: element [${i}] must be a string, got ${typeof v} (${JSON.stringify(v)})`,
      );
    }
    if (v === "") {
      throw new Error(
        `Invalid environments input: element [${i}] is an empty string`,
      );
    }
    if (!seen.has(v)) {
      seen.add(v);
      out.push(v);
    }
  });
  return out;
}

export function evaluateEnvironmentGate(args: {
  status: "active" | "inactive";
  envLabels: string[];
  inputLabelPatterns: string[];
}): SkipDecision {
  if (args.status === "inactive") {
    return {
      skip: true,
      reason: "status_inactive",
      detail: 'environment status is "inactive"',
    };
  }
  if (args.inputLabelPatterns.length === 0) {
    return { skip: false };
  }
  const unmatched: string[] = [];
  for (const pattern of args.inputLabelPatterns) {
    let re: RegExp;
    try {
      re = new RegExp(pattern);
    } catch (e) {
      throw new Error(
        `Invalid regex in labels input: ${JSON.stringify(pattern)} — ${
          e instanceof Error ? e.message : String(e)
        }`,
      );
    }
    if (!args.envLabels.some((l) => re.test(l))) {
      unmatched.push(pattern);
    }
  }
  if (unmatched.length > 0) {
    return {
      skip: true,
      reason: "labels_mismatch",
      detail: `env labels [${args.envLabels.join(", ")}] did not match required pattern(s): [${unmatched.join(", ")}]`,
    };
  }
  return { skip: false };
}

// ---------------------------------------------------------------------------
// Multi-env target selection
// ---------------------------------------------------------------------------

export interface FilteredEnv {
  env: string;
  reason: SkipReason;
  detail: string;
}

export interface TargetSelection {
  targets: string[];
  filtered: FilteredEnv[];
}

/**
 * Decide which env keys are update targets for this Action invocation.
 *
 * - If environmentsInput is non-empty, candidates = environmentsInput (every
 *   key must exist in settings.environments, otherwise throws).
 * - Otherwise, candidates = all keys of settings.environments.
 * - Each candidate runs through evaluateEnvironmentGate (status + labels).
 * - Surviving candidates are returned as `targets`; the rest as `filtered`.
 */
export function selectTargetEnvs(args: {
  settings: Settings;
  environmentsInput: string[];
  inputLabelPatterns: string[];
}): TargetSelection {
  const allKeys = Object.keys(args.settings.environments);
  let candidates: string[];

  if (args.environmentsInput.length > 0) {
    const missing = args.environmentsInput.filter(
      (env) => !(env in args.settings.environments),
    );
    if (missing.length > 0) {
      throw new Error(
        `Environments not found in settings.yml: ${missing.join(", ")}. Available: ${
          allKeys.join(", ") || "(none)"
        }`,
      );
    }
    candidates = args.environmentsInput;
  } else {
    candidates = allKeys;
  }

  const targets: string[] = [];
  const filtered: FilteredEnv[] = [];

  for (const env of candidates) {
    const cfg = args.settings.environments[env];
    const decision = evaluateEnvironmentGate({
      status: cfg.status,
      envLabels: cfg.labels,
      inputLabelPatterns: args.inputLabelPatterns,
    });
    if (decision.skip) {
      filtered.push({
        env,
        reason: decision.reason ?? "labels_mismatch",
        detail: decision.detail ?? "filtered",
      });
    } else {
      targets.push(env);
    }
  }

  return { targets, filtered };
}

// ---------------------------------------------------------------------------
// Workspace name <-> env reverse mapping
// ---------------------------------------------------------------------------

/**
 * Reverse the workspace-name pattern to extract the env key from a workspace
 * name. Returns null if the name doesn't match the pattern's expected shape.
 *
 * Example: pattern "{service}-{environment}", service "svc", name "svc-dev-001"
 *   → "dev-001"
 */
export function deriveEnvFromWorkspaceName(
  workspaceName: string,
  pattern: string,
  service: string,
): string | null {
  const patternWithService = pattern.replace(/\{service\}/g, service);
  const placeholder = "{environment}";
  const idx = patternWithService.indexOf(placeholder);
  if (idx < 0) return null;
  const prefix = patternWithService.slice(0, idx);
  const suffix = patternWithService.slice(idx + placeholder.length);
  if (!workspaceName.startsWith(prefix)) return null;
  if (suffix && !workspaceName.endsWith(suffix)) return null;
  const start = prefix.length;
  const end = workspaceName.length - suffix.length;
  if (end <= start) return null;
  return workspaceName.slice(start, end);
}

// ---------------------------------------------------------------------------
// Marker tag (used to find workspaces created by this Action for a service)
// ---------------------------------------------------------------------------

export function buildMarkerTag(service: string): string {
  return `firebase-platform-${service}`;
}
