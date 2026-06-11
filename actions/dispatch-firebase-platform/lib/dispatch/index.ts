import type { VariableSpec } from "../tfc/index.js";
import type { FirebasePlatformConfig, Settings } from "../settings/index.js";

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

const FEATURE_KEYS = [
  "firebase",
  "authentication",
  "firestore",
  "rtdb",
  "storage",
  "hosting",
  "app_hosting",
  "data_connect",
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
 * Normalize a feature flag value.
 *   null / undefined → null
 *   true / "true" → true
 *   false / "false" → null  (disable the feature)
 *   object → the object itself (passed as HCL)
 *
 * Throws for unexpected types (number, non-boolean string, etc.)
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
 * - If environmentInput is set, candidates = [environmentInput] (must exist in
 *   settings.environments, otherwise throws).
 * - Otherwise, candidates = all keys of settings.environments.
 * - Each candidate runs through evaluateEnvironmentGate (status + labels).
 * - Surviving candidates are returned as `targets`; the rest as `filtered`.
 */
export function selectTargetEnvs(args: {
  settings: Settings;
  environmentInput: string;
  inputLabelPatterns: string[];
}): TargetSelection {
  const allKeys = Object.keys(args.settings.environments);
  let candidates: string[];

  if (args.environmentInput) {
    if (!(args.environmentInput in args.settings.environments)) {
      throw new Error(
        `Environment "${args.environmentInput}" not found in settings.yml. Available: ${
          allKeys.join(", ") || "(none)"
        }`,
      );
    }
    candidates = [args.environmentInput];
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
