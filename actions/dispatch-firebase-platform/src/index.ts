import * as core from "@actions/core";
import {
  upsertWorkspace,
  addWorkspaceTags,
  listWorkspacesByTag,
  deleteWorkspace,
  syncVariables,
  upsertNotification,
  createRun,
  createConfigurationVersion,
  uploadConfigurationVersion,
  waitForConfigurationVersionUploaded,
} from "../lib/tfc/index.js";
import {
  loadSettings,
  extractEnvironment,
  extractFirebasePlatform,
} from "../lib/settings/index.js";
import {
  expandWorkspaceName,
  resolveAutoApply,
  buildTerraformVariables,
  buildEnvVariables,
  buildRunMessage,
  parseLabelsInput,
  selectTargetEnvs,
  buildMarkerTag,
  deriveEnvFromWorkspaceName,
} from "../lib/dispatch/index.js";
import { buildTemplateFiles } from "../lib/templates/index.js";
import { buildTarball } from "../lib/config-version/index.js";

async function run(): Promise<void> {
  try {
    // -----------------------------------------------------------------------
    // 1. Read inputs
    // -----------------------------------------------------------------------
    const service = core.getInput("service", { required: true });
    const environment = core.getInput("environment");
    const settingsPath = core.getInput("settings_path");
    const tfcOrg = core.getInput("tfc_org", { required: true });
    const targetWorkspacePattern = core.getInput("target_workspace");
    const bootstrapProjectId = core.getInput("bootstrap_project_id");
    const bootstrapProjectNumber = core.getInput("bootstrap_project_number", {
      required: true,
    });
    const poolId = core.getInput("workload_identity_pool_id");
    const providerId = core.getInput("workload_identity_provider_id");
    const tfcToken = core.getInput("tfc_token", { required: true });
    const applyPolicy = core.getInput("apply_policy");
    const enableWebhook =
      core.getInput("enable_webhook_notification") === "true";
    const webhookUrl = core.getInput("cloud_run_webhook_url");
    const webhookSecret = core.getInput("cloud_run_webhook_secret");
    const moduleVersion = core.getInput("module_version");
    const labelsInput = core.getInput("labels");

    core.setSecret(tfcToken);
    if (webhookSecret) core.setSecret(webhookSecret);

    // Default outputs so downstream `if:` checks are always safe.
    core.setOutput("skipped", "false");
    core.setOutput("skip_reason", "");
    core.setOutput("applied_envs", "[]");
    core.setOutput("filtered_envs", "[]");
    core.setOutput("failed_envs", "[]");
    core.setOutput("destroyed_envs", "[]");
    core.setOutput("retained_envs", "[]");
    core.setOutput("run_ids", "{}");
    core.setOutput("run_urls", "{}");
    core.setOutput("workspace_ids", "{}");
    core.setOutput("workspace_names", "{}");

    // -----------------------------------------------------------------------
    // 2. Parse settings.yml
    // -----------------------------------------------------------------------
    core.info(`Loading settings from ${settingsPath}`);
    const settings = await loadSettings(settingsPath);

    // -----------------------------------------------------------------------
    // 3. Validate input combination + select target envs
    // -----------------------------------------------------------------------
    const inputLabelPatterns = parseLabelsInput(labelsInput);
    if (!environment && inputLabelPatterns.length === 0) {
      throw new Error(
        "Either `environment` or `labels` input must be specified.",
      );
    }
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
      core.info("No envs matched the filters.");
    }

    // -----------------------------------------------------------------------
    // 4. Loop over target envs — upsert workspace + Run for each
    // -----------------------------------------------------------------------
    const markerTag = buildMarkerTag(service);
    const applied: string[] = [];
    const failed: Array<{ env: string; error: string }> = [];
    const runIds: Record<string, string> = {};
    const runUrls: Record<string, string> = {};
    const workspaceIds: Record<string, string> = {};
    const workspaceNames: Record<string, string> = {};

    for (const env of targets) {
      try {
        const envEntry = extractEnvironment(settings, env);
        const firebasePlatform = extractFirebasePlatform(settings, env);
        core.info(
          `[${env}] firebase_platform keys: ${Object.keys(firebasePlatform).join(", ")}`,
        );

        // Derive project_id / SA email
        const projectId = `${service}-${env}`;
        const saId = `terraform-${service}-${env}`;
        if (saId.length > 30) {
          throw new Error(
            `service account id "${saId}" is ${saId.length} chars for env "${env}" (GCP limit is 30). Shorten the service name or env key.`,
          );
        }
        const saEmail = `${saId}@${bootstrapProjectId}.iam.gserviceaccount.com`;
        core.info(`[${env}] project_id=${projectId}, sa=${saEmail}`);

        // Mask the env's billing_account_id (defensive even though B doesn't use it)
        if (envEntry.billing_account_id) {
          core.setSecret(envEntry.billing_account_id);
        }

        // Workspace upsert
        const autoApply = resolveAutoApply(applyPolicy, env);
        const targetName = expandWorkspaceName(targetWorkspacePattern, {
          service,
          environment: env,
        });
        core.info(
          `[${env}] Upserting workspace "${targetName}" (auto-apply=${autoApply})`,
        );
        const workspace = await upsertWorkspace(
          tfcOrg,
          { name: targetName, "auto-apply": autoApply },
          tfcToken,
        );
        const workspaceId = workspace.id;

        // Attach marker tag (additive — does not replace user-set tags)
        await addWorkspaceTags(workspaceId, [markerTag], tfcToken);

        // Notification config
        if (enableWebhook) {
          if (!webhookUrl) {
            throw new Error(
              "cloud_run_webhook_url is required when enable_webhook_notification=true",
            );
          }
          if (!webhookSecret) {
            throw new Error(
              "cloud_run_webhook_secret is required when enable_webhook_notification=true",
            );
          }
          await upsertNotification(
            workspaceId,
            webhookUrl,
            webhookSecret,
            tfcToken,
          );
        }

        // Variables
        const tfVars = buildTerraformVariables(projectId, firebasePlatform);
        const envVars = buildEnvVariables(
          saEmail,
          projectId,
          bootstrapProjectNumber,
          poolId,
          providerId,
        );
        await syncVariables(workspaceId, [...tfVars, ...envVars], tfcToken);
        core.info(
          `[${env}] Synced ${tfVars.length} terraform + ${envVars.length} env variables`,
        );

        // Configuration version
        const tarball = buildTarball(
          buildTemplateFiles(moduleVersion || undefined),
        );
        const cv = await createConfigurationVersion(
          workspaceId,
          false,
          tfcToken,
        );
        const uploadUrl = cv.attributes["upload-url"];
        if (!uploadUrl) {
          throw new Error(
            `Configuration version ${cv.id} did not return an upload-url`,
          );
        }
        await uploadConfigurationVersion(uploadUrl, tarball);
        await waitForConfigurationVersionUploaded(cv.id, tfcToken);
        core.info(`[${env}] Configuration version ready: ${cv.id}`);

        // Run
        const sourceRepo = process.env["GITHUB_REPOSITORY"] ?? "";
        const sha = process.env["GITHUB_SHA"] ?? "";
        const message = buildRunMessage({
          service,
          environments: [env],
          labels: inputLabelPatterns,
          source_repo: sourceRepo,
          sha,
        });
        const runData = await createRun({
          workspaceId,
          message,
          autoApply,
          configurationVersionId: cv.id,
          token: tfcToken,
        });

        const runUrl = `https://app.terraform.io/app/${tfcOrg}/workspaces/${targetName}/runs/${runData.id}`;
        applied.push(env);
        runIds[env] = runData.id;
        runUrls[env] = runUrl;
        workspaceIds[env] = workspaceId;
        workspaceNames[env] = targetName;
        core.info(`[${env}] Run created: ${runUrl}`);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        failed.push({ env, error: msg });
        core.error(`[${env}] failed: ${msg}`);
      }
    }

    // -----------------------------------------------------------------------
    // 5. Reconciliation: find orphan workspaces and force-delete
    //
    //    Orphan = workspace with our marker tag whose env is NOT in
    //    settings.environments AND NOT in settings.retained_envs.
    //    We do NOT destroy GCP resources (that's Action A's job); we only
    //    drop the TFC workspace so it stops accruing state for an env that
    //    no longer exists.
    // -----------------------------------------------------------------------
    const settingsEnvKeys = new Set(Object.keys(settings.environments));
    const retainedEnvKeys = new Set(settings.retained_envs);
    const destroyed: string[] = [];
    const retainedTouched: string[] = [];

    let knownWorkspaces: Awaited<ReturnType<typeof listWorkspacesByTag>> = [];
    try {
      knownWorkspaces = await listWorkspacesByTag(tfcOrg, markerTag, tfcToken);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      core.warning(
        `Could not list workspaces by tag "${markerTag}" for reconciliation: ${msg}`,
      );
    }

    for (const w of knownWorkspaces) {
      const env = deriveEnvFromWorkspaceName(
        w.attributes.name,
        targetWorkspacePattern,
        service,
      );
      if (!env) continue;
      if (settingsEnvKeys.has(env)) continue;
      if (retainedEnvKeys.has(env)) {
        retainedTouched.push(env);
        core.info(
          `[reconcile] env "${env}" retained (workspace "${w.attributes.name}" kept)`,
        );
        continue;
      }
      // Orphan → force-delete the workspace
      try {
        await deleteWorkspace(w.id, tfcToken);
        destroyed.push(env);
        core.warning(
          `[reconcile] env "${env}" orphan → deleted workspace "${w.attributes.name}"`,
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        core.warning(
          `[reconcile] failed to delete workspace "${w.attributes.name}" for env "${env}": ${msg}`,
        );
      }
    }

    // -----------------------------------------------------------------------
    // 6. Outputs
    // -----------------------------------------------------------------------
    core.setOutput("applied_envs", JSON.stringify(applied));
    core.setOutput("failed_envs", JSON.stringify(failed));
    core.setOutput("destroyed_envs", JSON.stringify(destroyed));
    core.setOutput("retained_envs", JSON.stringify(retainedTouched));
    core.setOutput("run_ids", JSON.stringify(runIds));
    core.setOutput("run_urls", JSON.stringify(runUrls));
    core.setOutput("workspace_ids", JSON.stringify(workspaceIds));
    core.setOutput("workspace_names", JSON.stringify(workspaceNames));

    if (failed.length > 0) {
      core.setFailed(
        `${failed.length}/${targets.length} env(s) failed: ${failed.map((f) => f.env).join(", ")}`,
      );
      return;
    }

    if (applied.length === 0 && destroyed.length === 0) {
      core.setOutput("skipped", "true");
      core.setOutput("skip_reason", "no_changes");
      core.info("No envs to apply and no orphan workspaces to delete");
    }
  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message);
    } else {
      core.setFailed(String(error));
    }
  }
}

run();
