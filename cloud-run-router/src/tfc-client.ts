const FETCH_TIMEOUT_MS = 30_000;
const MAX_ERROR_BODY_LENGTH = 200;

export interface TfcRunMeta {
  service: string;
  /** Env keys that Action A resolved as targets for this Run. */
  environments: string[];
  /**
   * Original `labels` input passed to Action A (JS RegExp pattern strings).
   * Forwarded to caller workflows so Action B can re-resolve using its own
   * settings.yml view when desired. Empty array when A was invoked with a
   * single `environment` input (no labels).
   */
  labels: string[];
  source_repo: string;
}

/**
 * Fetch Run metadata from TFC API (Option A).
 *
 * Looks up the Run's workspace variables for:
 *   - TF_VAR_service  (or METADATA_SERVICE)
 *   - TF_VAR_environment (or METADATA_ENV)
 *   - TF_VAR_source_repo (or METADATA_SOURCE_REPO)
 */
export async function fetchRunMetadata(
  runId: string,
  baseUrl: string,
  token: string,
): Promise<TfcRunMeta> {
  const runRes = await fetch(`${baseUrl}/api/v2/runs/${runId}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.api+json",
    },
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (!runRes.ok) {
    const body = await runRes.text();
    throw new Error(
      `TFC API /runs/${runId} returned ${runRes.status}: ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`,
    );
  }
  interface TfcRunResponse {
    data?: {
      relationships?: {
        workspace?: { data?: { id?: string } };
      };
    };
  }
  const runData = (await runRes.json()) as TfcRunResponse;
  const workspaceId = runData.data?.relationships?.workspace?.data?.id;
  if (!workspaceId) {
    throw new Error(
      `TFC API /runs/${runId} response missing workspace id`,
    );
  }

  interface TfcVarsResponse {
    data?: Array<{ attributes?: { key?: string; value?: string } }>;
    meta?: { pagination?: { next_page?: number | null } };
  }

  const allVars: Array<{ attributes?: { key?: string; value?: string } }> = [];
  let page = 1;
  while (true) {
    const varsRes = await fetch(
      `${baseUrl}/api/v2/workspaces/${workspaceId}/vars?page%5Bnumber%5D=${page}&page%5Bsize%5D=100`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/vnd.api+json",
        },
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      },
    );
    if (!varsRes.ok) {
      const body = await varsRes.text();
      throw new Error(
        `TFC API /workspaces/${workspaceId}/vars returned ${varsRes.status}: ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`,
      );
    }
    const varsData = (await varsRes.json()) as TfcVarsResponse;
    if (!Array.isArray(varsData.data)) {
      throw new Error(
        `TFC API /workspaces/${workspaceId}/vars response missing data array`,
      );
    }
    allVars.push(...varsData.data);
    const nextPage = varsData.meta?.pagination?.next_page;
    if (!nextPage) break;
    page = nextPage;
  }

  const varMap = new Map<string, string>();
  for (const v of allVars) {
    const key = v.attributes?.key;
    const value = v.attributes?.value;
    if (typeof key === "string" && typeof value === "string") {
      varMap.set(key, value);
    }
  }

  const service =
    varMap.get("TF_VAR_service") ?? varMap.get("METADATA_SERVICE") ?? "";
  const sourceRepo =
    varMap.get("TF_VAR_source_repo") ??
    varMap.get("METADATA_SOURCE_REPO") ??
    "";

  // Action A's per-service workspace keeps an `environments` JSON-string TFC
  // variable mapping env_key → entry. Use its keys as the env list. Note this
  // returns ALL envs managed by the workspace, not just the ones the latest
  // Run targeted — for an accurate per-Run list, prefer metadata_source
  // "run_message".
  let environments: string[] = [];
  const envsVar = varMap.get("environments");
  if (envsVar) {
    try {
      const parsed = JSON.parse(envsVar) as Record<string, unknown>;
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        environments = Object.keys(parsed);
      }
    } catch {
      // ignore malformed JSON; environments stays []
    }
  }

  if (!service || environments.length === 0 || !sourceRepo) {
    throw new Error(
      `Missing metadata in workspace variables: service=${service}, environments=[${environments.join(",")}], source_repo=${sourceRepo}`,
    );
  }

  return { service, environments, labels: [], source_repo: sourceRepo };
}

/**
 * Parse metadata embedded in `run_message` as JSON (Option B).
 *
 * Expected shape (current — emitted by dispatch-project-bootstrap / dispatch-firebase-platform):
 *   {
 *     "service": "X",
 *     "environments": ["dev-001", ...],
 *     "labels": ["^tier:dev$", ...],
 *     "source_repo": "owner/name",
 *     "sha": "..."
 *   }
 *
 * `labels` defaults to [] when absent (forward-compat with older Run messages
 * that didn't carry labels yet — older messages emitted by the platform never
 * had `environments` either, so they're already rejected below).
 */
export function parseRunMessage(runMessage: string): TfcRunMeta | null {
  try {
    const parsed = JSON.parse(runMessage) as Record<string, unknown>;
    const service = parsed["service"];
    const environments = parsed["environments"];
    const labelsRaw = parsed["labels"];
    const sourceRepo = parsed["source_repo"];
    if (
      typeof service !== "string" ||
      !service ||
      typeof sourceRepo !== "string" ||
      !sourceRepo ||
      !Array.isArray(environments) ||
      environments.length === 0 ||
      !environments.every((v) => typeof v === "string" && v.length > 0)
    ) {
      return null;
    }
    let labels: string[] = [];
    if (Array.isArray(labelsRaw)) {
      if (!labelsRaw.every((v) => typeof v === "string")) return null;
      labels = labelsRaw as string[];
    }
    return {
      service,
      environments: environments as string[],
      labels,
      source_repo: sourceRepo,
    };
  } catch {
    return null;
  }
}
