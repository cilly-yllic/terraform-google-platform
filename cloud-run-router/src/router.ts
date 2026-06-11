import type { Config } from "./config.js";
import type { TfcRunMeta } from "./tfc-client.js";
import { fetchRunMetadata, parseRunMessage } from "./tfc-client.js";
import { repositoryDispatch } from "./github-client.js";

/** Subset of a TFC notification payload we care about. */
export interface TfcNotification {
  payload_version: number;
  notification_configuration_id: string;
  run_url: string;
  run_id: string;
  run_message: string;
  run_created_at: string;
  run_created_by: string;
  workspace_id: string;
  workspace_name: string;
  organization_name: string;
  notifications: Array<{
    message: string;
    trigger: string;
    run_status: string;
    run_updated_at: string;
    run_updated_by: string;
  }>;
}

export type RouteResult =
  | { stage: "project_factory"; service: string }
  | { stage: "terminal"; service: string; env: string }
  | { stage: "unknown" };

/**
 * Determine the pipeline stage from the workspace name.
 */
export function classifyWorkspace(
  workspaceName: string,
  config: Config,
): RouteResult {
  const pfMatch = config.projectFactoryPattern.exec(workspaceName);
  if (pfMatch?.groups?.["service"]) {
    return { stage: "project_factory", service: pfMatch.groups["service"] };
  }

  const tMatch = config.terminalPattern.exec(workspaceName);
  if (tMatch?.groups?.["service"] && tMatch?.groups?.["env"]) {
    return {
      stage: "terminal",
      service: tMatch.groups["service"],
      env: tMatch.groups["env"],
    };
  }

  return { stage: "unknown" };
}

/**
 * Resolve (service, env, source_repo) using the configured metadata source.
 */
async function resolveMetadata(
  notification: TfcNotification,
  service: string,
  config: Config,
): Promise<TfcRunMeta> {
  if (
    config.metadataSource === "run_message" ||
    config.metadataSource === "both"
  ) {
    const parsed = parseRunMessage(notification.run_message);
    if (parsed) {
      return parsed;
    }
    if (config.metadataSource === "run_message") {
      throw new Error(
        `run_message does not contain valid metadata JSON: "${notification.run_message}"`,
      );
    }
  }

  if (
    config.metadataSource === "run_variables" ||
    config.metadataSource === "both"
  ) {
    if (!config.tfcApiToken) {
      throw new Error(
        "TFC_API_TOKEN is required when metadata_source is run_variables or both (fallback)",
      );
    }
    return fetchRunMetadata(
      notification.run_id,
      config.tfcApiBaseUrl,
      config.tfcApiToken,
    );
  }

  throw new Error(`Cannot resolve metadata for service=${service}`);
}

export interface HandleResult {
  action: "dispatched" | "terminal_noop" | "ignored";
  details: Record<string, unknown>;
}

/**
 * Main routing entry point.
 */
export async function handleNotification(
  notification: TfcNotification,
  config: Config,
): Promise<HandleResult> {
  if (!Array.isArray(notification.notifications) || notification.notifications.length === 0) {
    return {
      action: "ignored",
      details: { reason: "no_notifications" },
    };
  }

  const latestStatus =
    notification.notifications[notification.notifications.length - 1]
      ?.run_status;

  const route = classifyWorkspace(notification.workspace_name, config);

  const logBase = {
    workspace_name: notification.workspace_name,
    run_id: notification.run_id,
    run_status: latestStatus,
    organization: notification.organization_name,
    route,
  };

  if (route.stage === "project_factory") {
    if (latestStatus !== "applied") {
      console.log(
        JSON.stringify({
          severity: "INFO",
          message: "project_factory run not applied; skipping dispatch",
          ...logBase,
        }),
      );
      return {
        action: "ignored",
        details: { reason: "status_not_applied", ...logBase },
      };
    }

    const meta = await resolveMetadata(notification, route.service, config);

    console.log(
      JSON.stringify({
        severity: "INFO",
        message: "Dispatching firebase_platform_requested",
        target_repo: meta.source_repo,
        service: meta.service,
        environments: meta.environments,
        labels: meta.labels,
        ...logBase,
      }),
    );

    await repositoryDispatch(
      config.githubAppId,
      config.githubAppPrivateKey,
      meta.source_repo,
      config.dispatchEventType,
      {
        service: meta.service,
        environments: meta.environments,
        labels: meta.labels,
        run_id: notification.run_id,
        workspace_name: notification.workspace_name,
        source_repo: meta.source_repo,
      },
    );

    console.log(
      JSON.stringify({
        severity: "INFO",
        message: "repository_dispatch sent successfully",
        target_repo: meta.source_repo,
        ...logBase,
      }),
    );

    return {
      action: "dispatched",
      details: {
        target_repo: meta.source_repo,
        service: meta.service,
        environments: meta.environments,
        labels: meta.labels,
        ...logBase,
      },
    };
  }

  if (route.stage === "terminal") {
    console.log(
      JSON.stringify({
        severity: "INFO",
        message: "Terminal stage completed; no-op",
        ...logBase,
      }),
    );
    return { action: "terminal_noop", details: logBase };
  }

  console.log(
    JSON.stringify({
      severity: "WARNING",
      message: "Workspace name did not match any known pattern",
      ...logBase,
    }),
  );
  return {
    action: "ignored",
    details: { reason: "unknown_workspace_pattern", ...logBase },
  };
}
