import type { EnvironmentConfig, Settings } from "../settings";

export function expandWorkspaceName(
  pattern: string,
  vars: Record<string, string>
): string {
  let result = pattern;
  for (const [key, value] of Object.entries(vars)) {
    result = result.replace(new RegExp(`\\{${key}\\}`, "g"), () => value);
  }
  return result;
}

export function buildRunMessage(metadata: {
  service: string;
  environments: string[];
  labels: string[];
  source_repo: string;
  sha: string;
  // 使用する terraform-google-platform module バージョン。TFC コンソールの
  // run message でどの版が適用されたか一目で分かるようにするため含める。
  module_version: string;
}): string {
  return JSON.stringify(metadata);
}

export function mergeEnvironmentsMap(
  existing: Record<string, unknown>,
  environment: string,
  entry: Record<string, unknown>
): Record<string, unknown> {
  return { ...existing, [environment]: entry };
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
      }`
    );
  }
  if (!Array.isArray(parsed)) {
    throw new Error(
      `Invalid labels input: expected a JSON array of strings, got ${typeof parsed}`
    );
  }
  return parsed.map((v, i) => {
    if (typeof v !== "string") {
      throw new Error(
        `Invalid labels input: element [${i}] must be a string, got ${typeof v} (${JSON.stringify(v)})`
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
        }`
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
 * Decides which env keys are update targets for this Action invocation.
 *
 * - If environmentInput is set, candidates = [environmentInput] (must exist in
 *   settings.environments, otherwise throws).
 * - Otherwise, candidates = all keys of settings.environments.
 * - Each candidate runs through evaluateEnvironmentGate (status + labels).
 * - Surviving candidates are returned as `targets`; the rest as `filtered`
 *   with the reason for traceability.
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
        `Environment "${args.environmentInput}" not found in settings.yml. Available: ${allKeys.join(", ")}`
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
// Map diff (state-only removal vs destroy)
// ---------------------------------------------------------------------------

export interface EnvDiff {
  stateRemoveKeys: string[];
  destroyKeys: string[];
}

/**
 * Given the previous map keys (what's currently in TFC), the keys present in
 * settings.environments, and settings.retained_envs, decide which keys should
 * be removed from Terraform state without destroy (state-only) vs which should
 * be left to Terraform's for_each diff to destroy.
 *
 * - state-only: in prev map ∩ retained list, not in environments
 * - destroy:    in prev map, not in environments, not in retained list
 */
export function computeEnvDiff(args: {
  prevKeys: string[];
  settingsKeys: string[];
  retainedKeys: string[];
}): EnvDiff {
  const settings = new Set(args.settingsKeys);
  const retained = new Set(args.retainedKeys);

  const stateRemoveKeys: string[] = [];
  const destroyKeys: string[] = [];

  for (const key of args.prevKeys) {
    if (settings.has(key)) continue;
    if (retained.has(key)) {
      stateRemoveKeys.push(key);
    } else {
      destroyKeys.push(key);
    }
  }

  return { stateRemoveKeys, destroyKeys };
}

// ---------------------------------------------------------------------------
// environments map entry builder
// ---------------------------------------------------------------------------

export interface EnvEntry {
  project_id: string;
  billing_account_id: string;
  terraform_service_account_id: string;
  tfc_workspace_name: string;
}

/**
 * Build the per-env entry that goes into the `environments` map. Also
 * validates the derived GCP service account ID against the 30-char limit.
 */
export function buildEnvEntry(args: {
  service: string;
  env: string;
  envConfig: EnvironmentConfig;
}): EnvEntry {
  const project_id = `${args.service}-${args.env}`;
  const terraform_service_account_id = `terraform-${args.service}-${args.env}`;
  if (terraform_service_account_id.length > 30) {
    throw new Error(
      `terraform_service_account_id "${terraform_service_account_id}" is ${terraform_service_account_id.length} chars for env "${args.env}" (GCP limit is 30). Shorten the service name or env key.`
    );
  }
  return {
    project_id,
    billing_account_id: args.envConfig.billing_account_id,
    terraform_service_account_id,
    tfc_workspace_name: `${args.service}-${args.env}`,
  };
}
