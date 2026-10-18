import type { VariableSpec } from "../tfc/index.js";
import type { ComputeHostConfig, Settings } from "../settings/index.js";

// ---------------------------------------------------------------------------
// settings.yml の placeholder 展開（dispatch-firebase-platform と同じ規約）
//   - `${service}` → settings.service、`${env}` → 今の env key（yml の中のもの。小文字）
//   - `${BOOTSTRAP_PROJECT_NUMBER}` → Action の bootstrap_project_number input（外から注入するもの。大文字）
// compute_host の下の string 値だけを再帰で置き換える（キー・数値・真偽・null はそのまま）。
// 知らない placeholder はそのまま残し、HCL にするときに `$${...}` にエスケープする。
// `${BOOTSTRAP_PROJECT_NUMBER}` を使っているのに input が空なら、壊れた値を流さないよう止める
// ---------------------------------------------------------------------------

export interface PlaceholderContext {
  service: string;
  env: string;
  bootstrapProjectNumber?: string;
}

const BOOTSTRAP_PROJECT_NUMBER_TOKEN = "${BOOTSTRAP_PROJECT_NUMBER}";

const expandStringPlaceholders = (
  val: string,
  ctx: PlaceholderContext,
): string => {
  if (
    val.includes(BOOTSTRAP_PROJECT_NUMBER_TOKEN) &&
    !ctx.bootstrapProjectNumber
  ) {
    throw new Error(
      `settings.yml references \${BOOTSTRAP_PROJECT_NUMBER} but the dispatch-compute-host Action did not receive a non-empty 'bootstrap_project_number' input.`,
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

export const expandComputeHostPlaceholders = (
  config: ComputeHostConfig,
  ctx: PlaceholderContext,
): ComputeHostConfig =>
  deepExpandPlaceholders(config, ctx) as ComputeHostConfig;

// ---------------------------------------------------------------------------
// Workspace name expansion / apply policy（dispatch-firebase-platform と同じ）
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

export function resolveAutoApply(policy: string, env: string): boolean {
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
// HCL value（dispatch-firebase-platform と同じ。文字列の `${` / `%{` はエスケープする）
// ---------------------------------------------------------------------------

export function toHclValue(val: unknown): string {
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

// ---------------------------------------------------------------------------
// compute_host → Terraform 変数
//
// settings.yml に書いたキーだけを変数にする（書いていないキーは main.tf の既定値 = モジュールの既定値。
// 消したキーの TFC 変数は syncVariables が消す）。知らないキー・形の違う値は、ここで止める
// （typo で設定が黙って捨てられないように）。中身の細かい検証はモジュールの変数の検証に任せる
// ---------------------------------------------------------------------------

type ValueKind = "string" | "string[]" | "object" | "array";

export const COMPUTE_HOST_KEYS: Readonly<Record<string, ValueKind>> = {
  region: "string",
  apis: "string[]",
  api_propagation_wait: "string",
  network: "object",
  firewall_rules: "array",
  cloud_nat: "object",
  service_accounts: "array",
  service_account_iam: "array",
  custom_roles: "array",
  iam_bindings: "array",
};

const checkKind = (key: string, kind: ValueKind, value: unknown): void => {
  const ok =
    kind === "string"
      ? typeof value === "string"
      : kind === "string[]"
        ? Array.isArray(value) &&
          value.every((item) => typeof item === "string")
        : kind === "array"
          ? Array.isArray(value)
          : value !== null &&
            typeof value === "object" &&
            !Array.isArray(value);
  if (!ok) {
    throw new Error(
      `compute_host.${key} must be ${kind === "string[]" ? "a list of strings" : `a ${kind}`} (got ${
        Array.isArray(value) ? "array" : value === null ? "null" : typeof value
      })`,
    );
  }
};

export function buildTerraformVariables(
  projectId: string,
  config: ComputeHostConfig,
): VariableSpec[] {
  const unknown = Object.keys(config).filter(
    (key) => !Object.prototype.hasOwnProperty.call(COMPUTE_HOST_KEYS, key),
  );
  if (unknown.length > 0) {
    throw new Error(
      `Unknown compute_host key(s): ${unknown.join(", ")}. Allowed: ${Object.keys(COMPUTE_HOST_KEYS).join(", ")}`,
    );
  }
  const vars: VariableSpec[] = [
    {
      key: "project_id",
      value: projectId,
      category: "terraform",
      hcl: false,
      sensitive: false,
    },
  ];
  for (const [key, kind] of Object.entries(COMPUTE_HOST_KEYS)) {
    const value = config[key];
    // 書いていない・null のキーは送らない（既定値に任せる）
    if (value === undefined || value === null) continue;
    checkKind(key, kind, value);
    vars.push(
      kind === "string"
        ? {
            key,
            value: value as string,
            category: "terraform",
            hcl: false,
            sensitive: false,
          }
        : {
            key,
            value: toHclValue(value),
            category: "terraform",
            hcl: true,
            sensitive: false,
          },
    );
  }
  return vars;
}

// ---------------------------------------------------------------------------
// TFC Dynamic Credentials の env 変数（dispatch-firebase-platform と同じ）
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
// Run message / target env selection（dispatch-firebase-platform と同じ）
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
// Marker tag（この Action が作った workspace を見つける。dispatch-firebase-platform とは別の名前）
// ---------------------------------------------------------------------------

export function buildMarkerTag(service: string): string {
  return `compute-host-${service}`;
}

/**
 * workspace の名前（固定。Action A の WIF の許可先 `${service}-${env}` と合わせるため、変えられない）
 */
export const WORKSPACE_NAME_PATTERN = "{service}-{environment}";

/** dispatch-firebase-platform（Action B）が付ける marker tag の接頭辞 */
export const FOREIGN_MARKER_PREFIX = "firebase-platform-";

/**
 * workspace に別の Action（dispatch-firebase-platform）の marker tag が付いていれば、その tag を返す。
 * 付いていれば、この Action はその workspace を変えない・消さない（同じ service・env を両方の Action に指定したとき、
 * 変数・構成を置き換えたり、reconcile で消し合ったりしない）。
 * tag-names が読めない（無い・配列でない）ときは判定できないので "unknown" を返す（呼び出し側は止める・消さない）
 */
export function findForeignMarker(
  attributes: Record<string, unknown> | undefined,
): string | null | "unknown" {
  const tags = attributes?.["tag-names"];
  if (!Array.isArray(tags)) return "unknown";
  const found = tags.find(
    (tag): tag is string =>
      typeof tag === "string" && tag.startsWith(FOREIGN_MARKER_PREFIX),
  );
  return found ?? null;
}

// ---------------------------------------------------------------------------
// Project propagation pre-run wait（Action A から続けて起動されたときだけ。dispatch-firebase-platform と同じ）
// ---------------------------------------------------------------------------

export const PROPAGATION_WAIT_EVENT = "repository_dispatch";

/**
 * pre-run sleep の待機ミリ秒を決める純関数 (副作用なし → テスト可能)。
 *   - hasTargets が false (作る run 0 件) → 0
 *   - eventName が repository_dispatch 以外 (手動等) → 0
 *   - waitSeconds が 0 以下 / 非数 → 0
 * それ以外は waitSeconds * 1000 を返す。
 */
export function resolveProjectPropagationWaitMs(args: {
  eventName: string;
  waitSeconds: number;
  hasTargets: boolean;
}): number {
  if (!args.hasTargets) return 0;
  if (args.eventName !== PROPAGATION_WAIT_EVENT) return 0;
  if (!Number.isFinite(args.waitSeconds) || args.waitSeconds <= 0) return 0;
  return Math.floor(args.waitSeconds * 1000);
}
