const FETCH_TIMEOUT_MS = 30_000;
const MAX_ERROR_BODY_LENGTH = 200;

export interface TfcRunMeta {
  service: string;
  env: string;
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
  const env =
    varMap.get("TF_VAR_environment") ?? varMap.get("METADATA_ENV") ?? "";
  const sourceRepo =
    varMap.get("TF_VAR_source_repo") ??
    varMap.get("METADATA_SOURCE_REPO") ??
    "";

  if (!service || !env || !sourceRepo) {
    throw new Error(
      `Missing metadata in workspace variables: service=${service}, env=${env}, source_repo=${sourceRepo}`,
    );
  }

  return { service, env, source_repo: sourceRepo };
}

/**
 * Parse metadata embedded in `run_message` as JSON (Option B).
 *
 * Expected format: `{"service":"X","env":"Y","source_repo":"owner/name"}`
 */
export function parseRunMessage(runMessage: string): TfcRunMeta | null {
  try {
    const parsed = JSON.parse(runMessage) as Record<string, unknown>;
    const service = parsed["service"];
    const env = parsed["env"];
    const sourceRepo = parsed["source_repo"];
    if (
      typeof service === "string" &&
      typeof env === "string" &&
      typeof sourceRepo === "string" &&
      service &&
      env &&
      sourceRepo
    ) {
      return { service, env, source_repo: sourceRepo };
    }
    return null;
  } catch {
    return null;
  }
}
