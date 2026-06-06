const TFC_BASE = "https://app.terraform.io/api/v2";

function isConflict(e: TfcApiError): boolean {
  return e.status === 409 || e.status === 412 || e.status === 422;
}

interface TfcClientOptions {
  token: string;
  org: string;
}

interface WorkspaceAttributes {
  name: string;
  "auto-apply"?: boolean;
  "terraform_version"?: string;
  "working-directory"?: string;
  "execution-mode"?: string;
}

interface VariableAttributes {
  key: string;
  value: string;
  category: "terraform" | "env";
  hcl?: boolean;
  sensitive?: boolean;
  description?: string;
}

export interface TfcVariable {
  id: string;
  attributes: {
    key: string;
    value: string | null;
    category: string;
    hcl: boolean;
    sensitive: boolean;
  };
}

export interface TfcWorkspace {
  id: string;
  attributes: {
    name: string;
    "auto-apply": boolean;
  };
}

export interface TfcRun {
  id: string;
  attributes: {
    status: string;
    message: string;
  };
  links?: {
    self?: string;
  };
}

export interface TfcConfigurationVersion {
  id: string;
  attributes: {
    status: string;
    "upload-url"?: string;
    "auto-queue-runs"?: boolean;
  };
}

export class TfcApiError extends Error {
  constructor(
    public readonly method: string,
    public readonly path: string,
    public readonly status: number,
    public readonly body: string
  ) {
    super(`TFC API ${method} ${path} failed (${status}): ${body}`);
    this.name = "TfcApiError";
  }
}

export class TfcClient {
  private token: string;
  private org: string;

  constructor(opts: TfcClientOptions) {
    this.token = opts.token;
    this.org = opts.org;
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown,
    headers?: Record<string, string>
  ): Promise<{ data: T; status: number; headers: Headers }> {
    const url = `${TFC_BASE}${path}`;
    const reqHeaders: Record<string, string> = {
      Authorization: `Bearer ${this.token}`,
      "Content-Type": "application/vnd.api+json",
      ...headers,
    };

    const res = await fetch(url, {
      method,
      headers: reqHeaders,
      body: body ? JSON.stringify(body) : undefined,
    });

    if (!res.ok) {
      const text = await res.text();
      throw new TfcApiError(method, path, res.status, text);
    }

    const json = (await res.json()) as { data: T };
    return { data: json.data, status: res.status, headers: res.headers };
  }

  // --- Workspace ---

  async findWorkspaceByName(name: string): Promise<TfcWorkspace | null> {
    try {
      const { data } = await this.request<TfcWorkspace>(
        "GET",
        `/organizations/${this.org}/workspaces/${name}`
      );
      return data;
    } catch (e: unknown) {
      if (e instanceof TfcApiError && e.status === 404) return null;
      throw e;
    }
  }

  async createWorkspace(attrs: WorkspaceAttributes): Promise<TfcWorkspace> {
    const { data } = await this.request<TfcWorkspace>(
      "POST",
      `/organizations/${this.org}/workspaces`,
      {
        data: {
          type: "workspaces",
          attributes: attrs,
        },
      }
    );
    return data;
  }

  async updateWorkspace(
    workspaceId: string,
    attrs: Partial<WorkspaceAttributes>
  ): Promise<TfcWorkspace> {
    const { data } = await this.request<TfcWorkspace>(
      "PATCH",
      `/workspaces/${workspaceId}`,
      {
        data: {
          type: "workspaces",
          attributes: attrs,
        },
      }
    );
    return data;
  }

  async upsertWorkspace(
    name: string,
    attrs: Partial<WorkspaceAttributes> = {}
  ): Promise<TfcWorkspace> {
    const existing = await this.findWorkspaceByName(name);
    if (existing) {
      return this.updateWorkspace(existing.id, { ...attrs, name });
    }
    return this.createWorkspace({ ...attrs, name } as WorkspaceAttributes);
  }

  // --- Variables ---

  async listVariables(workspaceId: string): Promise<TfcVariable[]> {
    const { data } = await this.request<TfcVariable[]>(
      "GET",
      `/workspaces/${workspaceId}/vars`
    );
    return data;
  }

  async createVariable(
    workspaceId: string,
    attrs: VariableAttributes
  ): Promise<TfcVariable> {
    const { data } = await this.request<TfcVariable>(
      "POST",
      `/workspaces/${workspaceId}/vars`,
      {
        data: {
          type: "vars",
          attributes: attrs,
        },
      }
    );
    return data;
  }

  async updateVariable(
    varId: string,
    attrs: Partial<VariableAttributes>,
    etag?: string
  ): Promise<TfcVariable> {
    const reqHeaders: Record<string, string> = {};
    if (etag) {
      reqHeaders["If-Match"] = etag;
    }
    const { data } = await this.request<TfcVariable>(
      "PATCH",
      `/vars/${varId}`,
      {
        data: {
          type: "vars",
          attributes: attrs,
        },
      },
      reqHeaders
    );
    return data;
  }

  async getVariable(
    varId: string
  ): Promise<{ variable: TfcVariable; etag: string | null }> {
    const { data, headers } = await this.request<TfcVariable>(
      "GET",
      `/vars/${varId}`
    );
    return { variable: data, etag: headers.get("etag") };
  }

  async upsertVariable(
    workspaceId: string,
    attrs: VariableAttributes
  ): Promise<TfcVariable> {
    const vars = await this.listVariables(workspaceId);
    const existing = vars.find(
      (v) =>
        v.attributes.key === attrs.key &&
        v.attributes.category === attrs.category
    );
    if (existing) {
      return this.updateVariable(existing.id, attrs);
    }
    return this.createVariable(workspaceId, attrs);
  }

  /**
   * Batch-sync multiple variables with a single listVariables call.
   */
  async syncVariables(
    workspaceId: string,
    desired: VariableAttributes[]
  ): Promise<TfcVariable[]> {
    const existing = await this.listVariables(workspaceId);
    const results: TfcVariable[] = [];
    for (const attrs of desired) {
      const found = existing.find(
        (v) =>
          v.attributes.key === attrs.key &&
          v.attributes.category === attrs.category
      );
      if (found) {
        results.push(await this.updateVariable(found.id, attrs));
      } else {
        results.push(await this.createVariable(workspaceId, attrs));
      }
    }
    return results;
  }

  /**
   * Read-modify-write the `environments` variable with etag-based
   * optimistic concurrency. Retries on 409/412/422 conflict.
   */
  async readModifyWriteEnvironments(
    workspaceId: string,
    environment: string,
    entry: Record<string, unknown>,
    maxRetries = 3
  ): Promise<TfcVariable> {
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      const vars = await this.listVariables(workspaceId);
      const envVarRef = vars.find(
        (v) =>
          v.attributes.key === "environments" &&
          v.attributes.category === "terraform"
      );

      let existingMap: Record<string, unknown> = {};
      let etag: string | null = null;

      if (envVarRef) {
        const fetched = await this.getVariable(envVarRef.id);
        etag = fetched.etag;
        if (fetched.variable.attributes.value) {
          try {
            existingMap = JSON.parse(
              fetched.variable.attributes.value
            ) as Record<string, unknown>;
          } catch {
            existingMap = {};
          }
        }
      }

      const newMap = { ...existingMap, [environment]: entry };
      const newValue = JSON.stringify(newMap);

      if (envVarRef) {
        try {
          return await this.updateVariable(
            envVarRef.id,
            { value: newValue, hcl: false },
            etag ?? undefined
          );
        } catch (e: unknown) {
          if (e instanceof TfcApiError && isConflict(e) && attempt < maxRetries) {
            continue;
          }
          throw e;
        }
      } else {
        try {
          return await this.createVariable(workspaceId, {
            key: "environments",
            value: newValue,
            category: "terraform",
            hcl: false,
            sensitive: false,
            description: "Map of environments managed by project-factory",
          });
        } catch (e: unknown) {
          if (e instanceof TfcApiError && isConflict(e) && attempt < maxRetries) {
            continue;
          }
          throw e;
        }
      }
    }
    throw new Error(
      "Failed to update environments variable after max retries (etag conflict)"
    );
  }

  // --- Notification ---

  async upsertNotification(
    workspaceId: string,
    config: {
      name: string;
      url: string;
      token: string;
      triggers: string[];
    }
  ): Promise<void> {
    const { data: existing } = await this.request<
      Array<{
        id: string;
        attributes: { name: string };
      }>
    >("GET", `/workspaces/${workspaceId}/notification-configurations`);

    const found = existing.find((n) => n.attributes.name === config.name);

    const payload = {
      data: {
        type: "notification-configurations",
        attributes: {
          "destination-type": "generic",
          enabled: true,
          name: config.name,
          url: config.url,
          token: config.token,
          triggers: config.triggers,
        },
      },
    };

    if (found) {
      await this.request(
        "PATCH",
        `/notification-configurations/${found.id}`,
        payload
      );
    } else {
      await this.request(
        "POST",
        `/workspaces/${workspaceId}/notification-configurations`,
        payload
      );
    }
  }

  // --- Configuration Version ---

  async createConfigurationVersion(
    workspaceId: string,
    opts: { autoQueueRuns?: boolean } = {}
  ): Promise<TfcConfigurationVersion> {
    const { data } = await this.request<TfcConfigurationVersion>(
      "POST",
      `/workspaces/${workspaceId}/configuration-versions`,
      {
        data: {
          type: "configuration-versions",
          attributes: {
            "auto-queue-runs": opts.autoQueueRuns ?? false,
          },
        },
      }
    );
    return data;
  }

  async uploadConfigurationVersion(
    uploadUrl: string,
    tarball: Buffer
  ): Promise<void> {
    const res = await fetch(uploadUrl, {
      method: "PUT",
      headers: { "Content-Type": "application/octet-stream" },
      body: new Uint8Array(tarball),
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(
        `Failed to upload configuration version tarball (${res.status}): ${text}`
      );
    }
  }

  async getConfigurationVersion(
    configVersionId: string
  ): Promise<TfcConfigurationVersion> {
    const { data } = await this.request<TfcConfigurationVersion>(
      "GET",
      `/configuration-versions/${configVersionId}`
    );
    return data;
  }

  async waitForConfigurationVersionUploaded(
    configVersionId: string,
    opts: { timeoutMs?: number; intervalMs?: number } = {}
  ): Promise<TfcConfigurationVersion> {
    const timeoutMs = opts.timeoutMs ?? 60_000;
    const intervalMs = opts.intervalMs ?? 2_000;
    const deadline = Date.now() + timeoutMs;
    let last: TfcConfigurationVersion | undefined;
    while (Date.now() < deadline) {
      last = await this.getConfigurationVersion(configVersionId);
      const status = last.attributes.status;
      if (status === "uploaded") return last;
      if (status === "errored") {
        throw new Error(
          `Configuration version ${configVersionId} ingestion failed (status=errored)`
        );
      }
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }
    const lastStatus = last?.attributes.status ?? "unknown";
    throw new Error(
      `Timed out waiting for configuration version ${configVersionId} to reach status=uploaded (last status=${lastStatus})`
    );
  }

  // --- Run ---

  async createRun(
    workspaceId: string,
    opts: {
      message?: string;
      autoApply?: boolean;
      configurationVersionId?: string;
    } = {}
  ): Promise<TfcRun> {
    const relationships: Record<string, unknown> = {
      workspace: {
        data: {
          type: "workspaces",
          id: workspaceId,
        },
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
    const { data } = await this.request<TfcRun>("POST", `/runs`, {
      data: {
        type: "runs",
        attributes: {
          "auto-apply": opts.autoApply ?? true,
          message: opts.message ?? "",
        },
        relationships,
      },
    });
    return data;
  }
}
