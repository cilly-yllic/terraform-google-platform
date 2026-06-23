const FETCH_TIMEOUT_MS = 30_000;
const MAX_ERROR_BODY = 500;
const TFC_BASE = "https://app.terraform.io";

interface RequestOpts {
  method?: string;
  body?: unknown;
  token: string;
  baseUrl?: string;
}

class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

async function api<T>(path: string, opts: RequestOpts): Promise<T> {
  const base = opts.baseUrl ?? TFC_BASE;
  const url = `${base}/api/v2${path}`;
  const headers: Record<string, string> = {
    Authorization: `Bearer ${opts.token}`,
    "Content-Type": "application/vnd.api+json",
  };
  const res = await fetch(url, {
    method: opts.method ?? "GET",
    headers,
    body: opts.body ? JSON.stringify(opts.body) : undefined,
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new ApiError(
      `TFC API ${opts.method ?? "GET"} ${path} → ${res.status}: ${body.slice(0, MAX_ERROR_BODY)}`,
      res.status,
    );
  }
  if (res.status === 204) return {} as T;
  return (await res.json()) as T;
}

// ---------------------------------------------------------------------------
// Project
// ---------------------------------------------------------------------------

export interface ProjectData {
  id: string;
  attributes: { name: string };
}

export async function findProjectByName(
  org: string,
  name: string,
  token: string,
): Promise<ProjectData | null> {
  // TFC は project リストを `filter[names]=` で絞り込める (per-page max 100、
  // service ごとに 1 project なので page 不要)。
  interface Resp {
    data: ProjectData[];
  }
  const resp = await api<Resp>(
    `/organizations/${encodeURIComponent(org)}/projects?filter%5Bnames%5D=${encodeURIComponent(name)}`,
    { token },
  );
  if (!Array.isArray(resp.data) || resp.data.length === 0) return null;
  return resp.data.find((p) => p.attributes.name === name) ?? null;
}

export async function createProject(
  org: string,
  name: string,
  token: string,
): Promise<ProjectData> {
  interface Resp {
    data: ProjectData;
  }
  const resp = await api<Resp>(
    `/organizations/${encodeURIComponent(org)}/projects`,
    {
      method: "POST",
      token,
      body: { data: { type: "projects", attributes: { name } } },
    },
  );
  return resp.data;
}

export async function upsertProject(
  org: string,
  name: string,
  token: string,
): Promise<ProjectData> {
  const existing = await findProjectByName(org, name, token);
  if (existing) return existing;
  return createProject(org, name, token);
}

// ---------------------------------------------------------------------------
// Workspace
// ---------------------------------------------------------------------------

export interface WorkspaceAttributes {
  name: string;
  "auto-apply"?: boolean;
  "working-directory"?: string;
  "terraform-version"?: string;
  "execution-mode"?: string;
}

interface WorkspaceRelationships {
  project?: {
    data?: { id: string; type: "projects" } | null;
  };
}

interface WorkspaceData {
  id: string;
  attributes: { name: string; [k: string]: unknown };
  relationships?: WorkspaceRelationships;
}

export async function findWorkspaceByName(
  org: string,
  name: string,
  token: string,
): Promise<WorkspaceData | null> {
  interface Resp {
    data: WorkspaceData;
  }
  try {
    const resp = await api<Resp>(
      `/organizations/${encodeURIComponent(org)}/workspaces/${encodeURIComponent(name)}`,
      { token },
    );
    return resp.data;
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) {
      return null;
    }
    throw err;
  }
}

export async function createWorkspace(
  org: string,
  attrs: WorkspaceAttributes,
  token: string,
  projectId?: string,
): Promise<WorkspaceData> {
  interface Resp {
    data: WorkspaceData;
  }
  // project への配置は relationships で指定する。未指定だと Default Project
  // に作られるが、本 action からは常に明示的に project を渡す前提。
  const payload: Record<string, unknown> = {
    type: "workspaces",
    attributes: attrs,
  };
  if (projectId) {
    payload.relationships = {
      project: { data: { id: projectId, type: "projects" } },
    };
  }
  const resp = await api<Resp>(
    `/organizations/${encodeURIComponent(org)}/workspaces`,
    {
      method: "POST",
      token,
      body: { data: payload },
    },
  );
  return resp.data;
}

export async function updateWorkspace(
  workspaceId: string,
  attrs: Partial<WorkspaceAttributes>,
  token: string,
): Promise<WorkspaceData> {
  interface Resp {
    data: WorkspaceData;
  }
  const resp = await api<Resp>(`/workspaces/${workspaceId}`, {
    method: "PATCH",
    token,
    body: { data: { type: "workspaces", attributes: attrs } },
  });
  return resp.data;
}

/**
 * workspace の project relationship を別 project に張り替える。
 * TFC は relationships を含めた workspace PATCH 経由で project を変更できる
 * (専用の "move" endpoint は無い)。
 */
export async function moveWorkspaceToProject(
  workspaceId: string,
  projectId: string,
  token: string,
): Promise<WorkspaceData> {
  interface Resp {
    data: WorkspaceData;
  }
  const resp = await api<Resp>(`/workspaces/${workspaceId}`, {
    method: "PATCH",
    token,
    body: {
      data: {
        type: "workspaces",
        relationships: {
          project: { data: { id: projectId, type: "projects" } },
        },
      },
    },
  });
  return resp.data;
}

export async function upsertWorkspace(
  org: string,
  attrs: WorkspaceAttributes,
  token: string,
  projectId?: string,
): Promise<WorkspaceData> {
  const existing = await findWorkspaceByName(org, attrs.name, token);
  if (existing) {
    // project が違えば張り替え (Default Project → 新 project の migration が
    // これで自動化される)
    if (projectId && existing.relationships?.project?.data?.id !== projectId) {
      await moveWorkspaceToProject(existing.id, projectId, token);
    }
    return updateWorkspace(existing.id, attrs, token);
  }
  return createWorkspace(org, attrs, token, projectId);
}

/**
 * Additively attach tags to a workspace via the relationships endpoint
 * (does NOT replace existing tags, unlike `tag-names` in workspace attrs).
 *
 * Used by the Action to mark workspaces it manages so they can later be
 * reconciled against settings.yml.
 */
export async function addWorkspaceTags(
  workspaceId: string,
  tagNames: string[],
  token: string,
): Promise<void> {
  if (tagNames.length === 0) return;
  await api<unknown>(`/workspaces/${workspaceId}/relationships/tags`, {
    method: "POST",
    token,
    body: {
      data: tagNames.map((name) => ({
        type: "tags",
        attributes: { name },
      })),
    },
  });
}

/**
 * List all workspaces in the org that carry the given tag. Paginated.
 */
export async function listWorkspacesByTag(
  org: string,
  tag: string,
  token: string,
): Promise<WorkspaceData[]> {
  const all: WorkspaceData[] = [];
  let page = 1;
  const encodedTag = encodeURIComponent(tag);
  while (true) {
    interface Resp {
      data: WorkspaceData[];
      meta?: { pagination?: { next_page?: number | null } };
    }
    const resp = await api<Resp>(
      `/organizations/${encodeURIComponent(org)}/workspaces?search%5Btags%5D=${encodedTag}&page%5Bnumber%5D=${page}&page%5Bsize%5D=100`,
      { token },
    );
    all.push(...resp.data);
    const next = resp.meta?.pagination?.next_page;
    if (!next) break;
    page = next;
  }
  return all;
}

/**
 * Force-delete a TFC workspace. Removes the workspace and its state entirely;
 * does NOT destroy real infrastructure. The caller is responsible for any
 * resource cleanup (e.g. having Action A destroy the underlying GCP project).
 */
export async function deleteWorkspace(
  workspaceId: string,
  token: string,
): Promise<void> {
  await api<unknown>(`/workspaces/${workspaceId}`, {
    method: "DELETE",
    token,
  });
}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

interface VariableData {
  id: string;
  attributes: {
    key: string;
    value: string;
    category: "terraform" | "env";
    hcl: boolean;
    sensitive: boolean;
  };
}

export async function listVariables(
  workspaceId: string,
  token: string,
): Promise<VariableData[]> {
  const all: VariableData[] = [];
  let page = 1;
  while (true) {
    interface Resp {
      data: VariableData[];
      meta?: { pagination?: { next_page?: number | null } };
    }
    const resp = await api<Resp>(
      `/workspaces/${workspaceId}/vars?page%5Bnumber%5D=${page}&page%5Bsize%5D=100`,
      { token },
    );
    all.push(...resp.data);
    const next = resp.meta?.pagination?.next_page;
    if (!next) break;
    page = next;
  }
  return all;
}

export async function createVariable(
  workspaceId: string,
  key: string,
  value: string,
  category: "terraform" | "env",
  hcl: boolean,
  sensitive: boolean,
  token: string,
): Promise<VariableData> {
  interface Resp {
    data: VariableData;
  }
  const resp = await api<Resp>(`/workspaces/${workspaceId}/vars`, {
    method: "POST",
    token,
    body: {
      data: {
        type: "vars",
        attributes: { key, value, category, hcl, sensitive },
      },
    },
  });
  return resp.data;
}

export async function updateVariable(
  variableId: string,
  workspaceId: string,
  value: string,
  hcl: boolean,
  sensitive: boolean,
  token: string,
): Promise<VariableData> {
  interface Resp {
    data: VariableData;
  }
  const resp = await api<Resp>(
    `/workspaces/${workspaceId}/vars/${variableId}`,
    {
      method: "PATCH",
      token,
      body: {
        data: {
          type: "vars",
          attributes: { value, hcl, sensitive },
        },
      },
    },
  );
  return resp.data;
}

export async function deleteVariable(
  variableId: string,
  workspaceId: string,
  token: string,
): Promise<void> {
  await api<unknown>(`/workspaces/${workspaceId}/vars/${variableId}`, {
    method: "DELETE",
    token,
  });
}

export interface VariableSpec {
  key: string;
  value: string;
  category: "terraform" | "env";
  hcl: boolean;
  sensitive: boolean;
}

export async function syncVariables(
  workspaceId: string,
  desired: VariableSpec[],
  token: string,
): Promise<void> {
  const existing = await listVariables(workspaceId, token);
  const existingMap = new Map<string, VariableData>();
  for (const v of existing) {
    const compoundKey = `${v.attributes.category}::${v.attributes.key}`;
    existingMap.set(compoundKey, v);
  }

  for (const spec of desired) {
    const compoundKey = `${spec.category}::${spec.key}`;
    const cur = existingMap.get(compoundKey);
    if (cur) {
      const valueChanged = cur.attributes.sensitive
        ? true // TFC returns "" for sensitive values; always update
        : cur.attributes.value !== spec.value;
      if (
        valueChanged ||
        cur.attributes.hcl !== spec.hcl ||
        cur.attributes.sensitive !== spec.sensitive
      ) {
        await updateVariable(
          cur.id,
          workspaceId,
          spec.value,
          spec.hcl,
          spec.sensitive,
          token,
        );
      }
      existingMap.delete(compoundKey);
    } else {
      await createVariable(
        workspaceId,
        spec.key,
        spec.value,
        spec.category,
        spec.hcl,
        spec.sensitive,
        token,
      );
    }
  }

  for (const [, stale] of existingMap) {
    await deleteVariable(stale.id, workspaceId, token);
  }
}

// ---------------------------------------------------------------------------
// Notification Configuration
// ---------------------------------------------------------------------------

export interface NotifData {
  id: string;
  attributes: {
    name: string;
    url: string;
    "destination-type": string;
    enabled: boolean;
  };
}

// workspace の notification-configurations を全 page 取得する。
export async function listNotifications(
  workspaceId: string,
  token: string,
): Promise<NotifData[]> {
  interface ListResp {
    data: NotifData[];
    meta?: { pagination?: { next_page?: number | null } };
  }
  const all: NotifData[] = [];
  let page = 1;
  while (true) {
    const resp = await api<ListResp>(
      `/workspaces/${workspaceId}/notification-configurations?page%5Bnumber%5D=${page}&page%5Bsize%5D=100`,
      { token },
    );
    all.push(...resp.data);
    const next = resp.meta?.pagination?.next_page;
    if (!next) break;
    page = next;
  }
  return all;
}

// Cloud Run Router 用 generic notification (HMAC 署名付き)。Phase 2 連鎖用。
export async function upsertNotification(
  workspaceId: string,
  url: string,
  hmacSecret: string,
  token: string,
): Promise<void> {
  const all = await listNotifications(workspaceId, token);
  const existing = all.find(
    (n) =>
      n.attributes["destination-type"] === "generic" &&
      n.attributes.name === "firebase-platform-webhook",
  );

  const attrs = {
    name: "firebase-platform-webhook",
    "destination-type": "generic",
    url,
    token: hmacSecret,
    enabled: true,
    triggers: ["run:completed", "run:errored", "run:needs_attention"],
  };

  if (existing) {
    await api<unknown>(`/notification-configurations/${existing.id}`, {
      method: "PATCH",
      token,
      body: {
        data: { type: "notification-configurations", attributes: attrs },
      },
    });
  } else {
    await api<unknown>(`/workspaces/${workspaceId}/notification-configurations`, {
      method: "POST",
      token,
      body: {
        data: { type: "notification-configurations", attributes: attrs },
      },
    });
  }
}

// apply 結果通知 (Slack 等) を name 単位で upsert する。Router 用とは別名で共存。
// slack: destination-type=slack, HMAC token 不要 (TFC が Slack 整形)。
// generic: destination-type=generic, hmacToken があれば署名付与。
export interface NotificationConfigSpec {
  name: string;
  destinationType: string;
  url: string;
  triggers: string[];
  hmacToken?: string;
}

export async function upsertNotificationConfig(
  workspaceId: string,
  spec: NotificationConfigSpec,
  existing: NotifData[],
  token: string,
): Promise<void> {
  const attrs: Record<string, unknown> = {
    name: spec.name,
    "destination-type": spec.destinationType,
    url: spec.url,
    enabled: true,
    triggers: spec.triggers,
  };
  if (spec.destinationType === "generic" && spec.hmacToken) {
    attrs.token = spec.hmacToken;
  }
  const found = existing.find((n) => n.attributes.name === spec.name);
  if (found) {
    await api<unknown>(`/notification-configurations/${found.id}`, {
      method: "PATCH",
      token,
      body: {
        data: { type: "notification-configurations", attributes: attrs },
      },
    });
  } else {
    await api<unknown>(`/workspaces/${workspaceId}/notification-configurations`, {
      method: "POST",
      token,
      body: {
        data: { type: "notification-configurations", attributes: attrs },
      },
    });
  }
}

export async function deleteNotification(
  id: string,
  token: string,
): Promise<void> {
  await api<unknown>(`/notification-configurations/${id}`, {
    method: "DELETE",
    token,
  });
}

// ---------------------------------------------------------------------------
// Configuration Version
// ---------------------------------------------------------------------------

export interface ConfigurationVersionData {
  id: string;
  attributes: {
    status: string;
    "upload-url"?: string;
    "auto-queue-runs"?: boolean;
  };
}

export async function createConfigurationVersion(
  workspaceId: string,
  autoQueueRuns: boolean,
  token: string,
): Promise<ConfigurationVersionData> {
  interface Resp {
    data: ConfigurationVersionData;
  }
  const resp = await api<Resp>(
    `/workspaces/${workspaceId}/configuration-versions`,
    {
      method: "POST",
      token,
      body: {
        data: {
          type: "configuration-versions",
          attributes: { "auto-queue-runs": autoQueueRuns },
        },
      },
    },
  );
  return resp.data;
}

export async function uploadConfigurationVersion(
  uploadUrl: string,
  tarball: Buffer,
): Promise<void> {
  const res = await fetch(uploadUrl, {
    method: "PUT",
    headers: { "Content-Type": "application/octet-stream" },
    body: new Uint8Array(tarball),
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(
      `Failed to upload configuration version tarball (${res.status}): ${body.slice(0, MAX_ERROR_BODY)}`,
    );
  }
}

export async function getConfigurationVersion(
  configVersionId: string,
  token: string,
): Promise<ConfigurationVersionData> {
  interface Resp {
    data: ConfigurationVersionData;
  }
  const resp = await api<Resp>(
    `/configuration-versions/${configVersionId}`,
    { token },
  );
  return resp.data;
}

export async function waitForConfigurationVersionUploaded(
  configVersionId: string,
  token: string,
  opts: { timeoutMs?: number; intervalMs?: number } = {},
): Promise<ConfigurationVersionData> {
  const timeoutMs = opts.timeoutMs ?? 60_000;
  const intervalMs = opts.intervalMs ?? 2_000;
  const deadline = Date.now() + timeoutMs;
  let last: ConfigurationVersionData | undefined;
  while (Date.now() < deadline) {
    last = await getConfigurationVersion(configVersionId, token);
    const status = last.attributes.status;
    if (status === "uploaded") return last;
    if (status === "errored") {
      throw new Error(
        `Configuration version ${configVersionId} ingestion failed (status=errored)`,
      );
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  const lastStatus = last?.attributes.status ?? "unknown";
  throw new Error(
    `Timed out waiting for configuration version ${configVersionId} to reach status=uploaded (last status=${lastStatus})`,
  );
}

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

export interface RunCreateOpts {
  workspaceId: string;
  message?: string;
  autoApply?: boolean;
  configurationVersionId?: string;
  token: string;
}

interface RunData {
  id: string;
  attributes: { [k: string]: unknown };
}

export async function createRun(opts: RunCreateOpts): Promise<RunData> {
  interface Resp {
    data: RunData;
  }
  const relationships: Record<string, unknown> = {
    workspace: {
      data: { type: "workspaces", id: opts.workspaceId },
    },
  };
  if (opts.configurationVersionId) {
    relationships["configuration-version"] = {
      data: {
        type: "configuration-versions",
        id: opts.configurationVersionId,
      },
    };
  }
  const resp = await api<Resp>("/runs", {
    method: "POST",
    token: opts.token,
    body: {
      data: {
        type: "runs",
        attributes: {
          message: opts.message ?? "",
          "auto-apply": opts.autoApply ?? false,
        },
        relationships,
      },
    },
  });
  return resp.data;
}
