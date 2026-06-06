import type { VariableSpec } from "../tfc/index.js";
import type { FirebasePlatformConfig } from "../settings/index.js";

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
      return env === "dev";
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
  environment: string;
  source_repo: string;
  sha: string;
}

export function buildRunMessage(meta: RunMessageMeta): string {
  return JSON.stringify(meta);
}
