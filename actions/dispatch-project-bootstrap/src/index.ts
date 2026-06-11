import * as core from "@actions/core";
import * as github from "@actions/github";
import * as fs from "fs";
import * as path from "path";

import { TfcClient } from "../lib/tfc";
import { parseSettings } from "../lib/settings";
import {
  expandWorkspaceName,
  buildRunMessage,
  parseLabelsInput,
  selectTargetEnvs,
  buildEnvEntry,
} from "../lib/dispatch";
import { buildTemplateFiles } from "../lib/templates";
import { buildTarball } from "../lib/config-version";

async function run(): Promise<void> {
  try {
    // ---- Read inputs ----
    const service = core.getInput("service", { required: true });
    const environment = core.getInput("environment");
    const settingsPath = core.getInput("settings_path");
    const tfcOrg = core.getInput("tfc_org", { required: true });
    const tfcWorkspacePattern = core.getInput("tfc_workspace_name");
    const parentOrgId = core.getInput("parent_organization_id");
    const parentFolderId = core.getInput("parent_folder_id");
    const bootstrapProjectId = core.getInput("bootstrap_project_id");
    const bootstrapProjectNumber = core.getInput("bootstrap_project_number", {
      required: true,
    });
    const wifPoolId = core.getInput("workload_identity_pool_id");
    const wifProviderId = core.getInput("workload_identity_provider_id");
    const tfcToken = core.getInput("tfc_token", { required: true });
    const enableWebhook =
      core.getInput("enable_webhook_notification") === "true";
    const cloudRunWebhookUrl = core.getInput("cloud_run_webhook_url");
    const cloudRunWebhookSecret = core.getInput("cloud_run_webhook_secret");
    const moduleVersion = core.getInput("module_version");
    const labelsInput = core.getInput("labels");

    // Mask sensitive values
    core.setSecret(tfcToken);
    if (cloudRunWebhookSecret) core.setSecret(cloudRunWebhookSecret);

    // Default outputs so downstream `if:` checks are always safe to evaluate.
    core.setOutput("skipped", "false");
    core.setOutput("skip_reason", "");
    core.setOutput("applied_envs", "[]");
    core.setOutput("state_removed_envs", "[]");
    core.setOutput("destroyed_envs", "[]");
    core.setOutput("filtered_envs", "[]");

    // ---- 1. Read settings.yml ----
    core.info(`Reading settings from ${settingsPath}`);
    const workspace = process.env.GITHUB_WORKSPACE ?? process.cwd();
    const settingsFullPath = path.resolve(workspace, settingsPath);
    const settingsRaw = fs.readFileSync(settingsFullPath, "utf-8");
    const settings = parseSettings(settingsRaw);
    core.info(`Parsed settings for service: ${settings.service}`);

    // ---- 2. Validate input combination ----
    const inputLabelPatterns = parseLabelsInput(labelsInput);
    if (!environment && inputLabelPatterns.length === 0) {
      throw new Error(
        "Either `environment` or `labels` input must be specified."
      );
    }

    // ---- 3. Select target envs (status + labels) ----
    const { targets, filtered } = selectTargetEnvs({
      settings,
      environmentInput: environment,
      inputLabelPatterns,
    });
    core.setOutput("filtered_envs", JSON.stringify(filtered));
    for (const f of filtered) {
      core.info(`Filtered out env "${f.env}": ${f.detail}`);
    }
    if (targets.length > 0) {
      core.info(`Target envs: ${targets.join(", ")}`);
    } else {
      core.info("No envs matched the filters — only retained/destroy diffs may apply.");
    }

    // ---- 4. Build per-env entries (validates SA ID length per env) ----
    const targetEntries: Record<string, Record<string, unknown>> = {};
    for (const env of targets) {
      const envConfig = settings.environments[env];
      core.setSecret(envConfig.billing_account_id);
      const entry = buildEnvEntry({ service, env, envConfig });
      targetEntries[env] = entry as unknown as Record<string, unknown>;
    }

    // ---- 5. Upsert TFC Workspace ----
    const tfc = new TfcClient({ token: tfcToken, org: tfcOrg });
    const workspaceName = expandWorkspaceName(tfcWorkspacePattern, { service });
    core.info(`Upserting workspace: ${workspaceName}`);

    const ws = await tfc.upsertWorkspace(workspaceName, {
      "auto-apply": true,
      "execution-mode": "remote",
    });
    core.info(`Workspace ready: id=${ws.id}`);

    // ---- 6. Notification config ----
    if (enableWebhook) {
      if (!cloudRunWebhookUrl) {
        throw new Error(
          "cloud_run_webhook_url is required when enable_webhook_notification=true"
        );
      }
      core.info("Upserting TFC notification configuration");
      await tfc.upsertNotification(ws.id, {
        name: `project-factory-${service}-webhook`,
        url: cloudRunWebhookUrl,
        token: cloudRunWebhookSecret || "",
        triggers: ["run:completed", "run:errored"],
      });
    }

    // ---- 7. Upsert environments variable (batch) ----
    core.info("Updating environments variable (batch read-modify-write with etag)");
    const settingsKeys = Object.keys(settings.environments);
    const retainedKeys = settings.retained_envs;
    const diff = await tfc.upsertEnvironmentsBatch(ws.id, {
      targetEntries,
      settingsKeys,
      retainedKeys,
    });
    core.setOutput("applied_envs", JSON.stringify(targets));
    core.setOutput("state_removed_envs", JSON.stringify(diff.stateRemoveKeys));
    core.setOutput("destroyed_envs", JSON.stringify(diff.destroyKeys));

    if (diff.stateRemoveKeys.length > 0) {
      core.info(
        `State-only removal queued for: ${diff.stateRemoveKeys.join(", ")} (GCP resources retained)`
      );
    }
    if (diff.destroyKeys.length > 0) {
      core.warning(
        `Destroy queued for: ${diff.destroyKeys.join(", ")} (env absent from both environments: and retained_envs:)`
      );
    }

    // ---- 8. Skip Run if nothing changed ----
    if (
      targets.length === 0 &&
      diff.stateRemoveKeys.length === 0 &&
      diff.destroyKeys.length === 0
    ) {
      core.info("No env changes — skipping Run creation");
      core.setOutput("skipped", "true");
      core.setOutput("skip_reason", "no_changes");
      return;
    }

    // ---- 9. Sync Environment Variables (TFC Dynamic Credentials) ----
    core.info("Syncing environment variables for TFC Dynamic Credentials");
    const envVars: Array<{ key: string; value: string; sensitive: boolean }> = [
      {
        key: "TFC_GCP_PROVIDER_AUTH",
        value: "true",
        sensitive: false,
      },
      {
        key: "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL",
        value: `terraform-project-factory@${bootstrapProjectId}.iam.gserviceaccount.com`,
        sensitive: false,
      },
      {
        key: "TFC_GCP_WORKLOAD_PROVIDER_NAME",
        value: `projects/${bootstrapProjectNumber}/locations/global/workloadIdentityPools/${wifPoolId}/providers/${wifProviderId}`,
        sensitive: false,
      },
      {
        key: "GOOGLE_PROJECT",
        value: bootstrapProjectId,
        sensitive: false,
      },
    ];

    await tfc.syncVariables(
      ws.id,
      envVars.map((ev) => ({
        key: ev.key,
        value: ev.value,
        category: "env" as const,
        sensitive: ev.sensitive,
      }))
    );
    core.info("Environment variables synced");

    // ---- 10. Sync Terraform Variables ----
    // NOTE: `parent` is stored as a JSON string (hcl: false). The consuming
    // Terraform workspace is expected to use jsondecode().
    core.info("Syncing terraform variables");
    const tfVarAttrs: Array<{
      key: string;
      value: string;
      hcl: boolean;
    }> = [
      { key: "service", value: service, hcl: false },
    ];

    if (parentFolderId) {
      tfVarAttrs.push({
        key: "parent",
        value: JSON.stringify({ folder_id: parentFolderId }),
        hcl: false,
      });
    } else if (parentOrgId) {
      tfVarAttrs.push({
        key: "parent",
        value: JSON.stringify({ organization_id: parentOrgId }),
        hcl: false,
      });
    }

    tfVarAttrs.push({
      key: "bootstrap_project_id",
      value: bootstrapProjectId,
      hcl: false,
    });
    tfVarAttrs.push({
      key: "workload_identity_pool_id",
      value: wifPoolId,
      hcl: false,
    });
    tfVarAttrs.push({
      key: "workload_identity_provider_id",
      value: wifProviderId,
      hcl: false,
    });

    await tfc.syncVariables(
      ws.id,
      tfVarAttrs.map((tv) => ({
        key: tv.key,
        value: tv.value,
        category: "terraform" as const,
        hcl: tv.hcl,
        sensitive: false,
      }))
    );
    core.info("Terraform variables synced");

    // ---- 11. Upload Configuration Version (main.tf template) ----
    core.info(
      moduleVersion
        ? `Building configuration tarball (module version pinned to ${moduleVersion}, removed-blocks=${diff.stateRemoveKeys.length})`
        : `Building configuration tarball (module version unpinned, removed-blocks=${diff.stateRemoveKeys.length})`
    );
    const tarball = buildTarball(
      buildTemplateFiles({
        moduleVersion: moduleVersion || undefined,
        stateRemoveKeys: diff.stateRemoveKeys,
      })
    );

    core.info("Creating configuration version");
    const cv = await tfc.createConfigurationVersion(ws.id, {
      autoQueueRuns: false,
    });
    const uploadUrl = cv.attributes["upload-url"];
    if (!uploadUrl) {
      throw new Error(
        `Configuration version ${cv.id} did not return an upload-url`
      );
    }

    core.info(`Uploading tarball (${tarball.length} bytes)`);
    await tfc.uploadConfigurationVersion(uploadUrl, tarball);

    core.info("Waiting for configuration version ingestion");
    await tfc.waitForConfigurationVersionUploaded(cv.id);
    core.info(`Configuration version ready: ${cv.id}`);

    // ---- 12. Create Run ----
    const context = github.context;
    const runMessage = buildRunMessage({
      service,
      environments: targets,
      source_repo: `${context.repo.owner}/${context.repo.repo}`,
      sha: context.sha,
    });

    core.info("Creating Terraform Cloud Run (auto-apply: true)");
    const tfcRun = await tfc.createRun(ws.id, {
      message: runMessage,
      autoApply: true,
      configurationVersionId: cv.id,
    });

    const runUrl = `https://app.terraform.io/app/${tfcOrg}/workspaces/${workspaceName}/runs/${tfcRun.id}`;
    core.info(`Run created: ${runUrl}`);

    // ---- Set outputs ----
    core.setOutput("run_id", tfcRun.id);
    core.setOutput("run_url", runUrl);
    core.setOutput("workspace_id", ws.id);
    core.setOutput("workspace_name", workspaceName);
  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message);
    } else {
      core.setFailed("An unexpected error occurred");
    }
  }
}

run();
