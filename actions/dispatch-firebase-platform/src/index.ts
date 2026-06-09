import * as core from "@actions/core";
import {
  upsertWorkspace,
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
  evaluateEnvironmentGate,
} from "../lib/dispatch/index.js";
import { buildTemplateFiles } from "../lib/templates/index.js";
import { buildTarball } from "../lib/config-version/index.js";

async function run(): Promise<void> {
  try {
    // -----------------------------------------------------------------------
    // 1. Read inputs
    // -----------------------------------------------------------------------
    const service = core.getInput("service", { required: true });
    const environment = core.getInput("environment", { required: true });
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

    // Default the skip-related outputs so downstream `if:` checks are always
    // safe to evaluate, even on early failure.
    core.setOutput("skipped", "false");
    core.setOutput("skip_reason", "");

    // -----------------------------------------------------------------------
    // 2. Parse settings.yml → firebase_platform section
    // -----------------------------------------------------------------------
    core.info(`Loading settings from ${settingsPath}`);
    const settings = await loadSettings(settingsPath);
    const envEntry = extractEnvironment(settings, environment);

    // -----------------------------------------------------------------------
    // 2a. Gating: status + label regex AND match
    // -----------------------------------------------------------------------
    const inputLabelPatterns = parseLabelsInput(labelsInput);
    const gate = evaluateEnvironmentGate({
      status: envEntry.status,
      envLabels: envEntry.labels,
      inputLabelPatterns,
    });
    if (gate.skip) {
      core.warning(
        `Skipping env "${environment}": ${gate.detail ?? gate.reason ?? "filtered"}`,
      );
      core.setOutput("skipped", "true");
      core.setOutput("skip_reason", gate.reason ?? "");
      return;
    }

    const firebasePlatform = extractFirebasePlatform(settings, environment);
    core.info(
      `Extracted firebase_platform for env "${environment}": ${Object.keys(firebasePlatform).join(", ")}`,
    );

    // -----------------------------------------------------------------------
    // 3. Derive project_id / SA email from service + env key
    //    (env key is the project_id suffix — e.g. "prd-001", "dev-002")
    // -----------------------------------------------------------------------
    const projectId = `${service}-${environment}`;
    const saId = `terraform-${service}-${environment}`;
    if (saId.length > 30) {
      throw new Error(
        `service account id "${saId}" is ${saId.length} chars (GCP limit is 30). ` +
          "Shorten the service name or env key.",
      );
    }
    const saEmail = `${saId}@${bootstrapProjectId}.iam.gserviceaccount.com`;
    core.info(`project_id=${projectId}, sa=${saEmail}`);

    // -----------------------------------------------------------------------
    // 4. Upsert target workspace
    // -----------------------------------------------------------------------
    const autoApply = resolveAutoApply(applyPolicy, environment);
    const targetName = expandWorkspaceName(targetWorkspacePattern, {
      service,
      environment,
    });
    core.info(
      `Upserting workspace "${targetName}" (auto-apply=${autoApply})`,
    );
    const workspace = await upsertWorkspace(
      tfcOrg,
      { name: targetName, "auto-apply": autoApply },
      tfcToken,
    );
    const workspaceId = workspace.id;

    // -----------------------------------------------------------------------
    // 5. (Phase 2) Webhook notification
    // -----------------------------------------------------------------------
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
      core.info("Upserting webhook notification configuration");
      await upsertNotification(
        workspaceId,
        webhookUrl,
        webhookSecret,
        tfcToken,
      );
    }

    // -----------------------------------------------------------------------
    // 6. Sync Terraform Variables (feature flags)
    // -----------------------------------------------------------------------
    const tfVars = buildTerraformVariables(projectId, firebasePlatform);

    // -----------------------------------------------------------------------
    // 7. Sync Environment Variables (Dynamic Credentials)
    // -----------------------------------------------------------------------
    const envVars = buildEnvVariables(
      saEmail,
      projectId,
      bootstrapProjectNumber,
      poolId,
      providerId,
    );

    const allVars = [...tfVars, ...envVars];
    core.info(
      `Syncing ${tfVars.length} Terraform + ${envVars.length} environment variable(s)`,
    );
    await syncVariables(workspaceId, allVars, tfcToken);
    core.info("Variable sync complete");

    // -----------------------------------------------------------------------
    // 8. Upload Configuration Version (main.tf template)
    // -----------------------------------------------------------------------
    core.info(
      moduleVersion
        ? `Building configuration tarball (module version pinned to ${moduleVersion})`
        : "Building configuration tarball (module version unpinned)",
    );
    const tarball = buildTarball(
      buildTemplateFiles(moduleVersion || undefined),
    );

    core.info("Creating configuration version");
    const cv = await createConfigurationVersion(workspaceId, false, tfcToken);
    const uploadUrl = cv.attributes["upload-url"];
    if (!uploadUrl) {
      throw new Error(
        `Configuration version ${cv.id} did not return an upload-url`,
      );
    }

    core.info(`Uploading tarball (${tarball.length} bytes)`);
    await uploadConfigurationVersion(uploadUrl, tarball);

    core.info("Waiting for configuration version ingestion");
    await waitForConfigurationVersionUploaded(cv.id, tfcToken);
    core.info(`Configuration version ready: ${cv.id}`);

    // -----------------------------------------------------------------------
    // 9. Create Run
    // -----------------------------------------------------------------------
    const sourceRepo = process.env["GITHUB_REPOSITORY"] ?? "";
    const sha = process.env["GITHUB_SHA"] ?? "";
    const message = buildRunMessage({
      service,
      environment,
      source_repo: sourceRepo,
      sha,
    });
    core.info(
      `Creating run in workspace "${targetName}" (auto-apply=${autoApply})`,
    );
    const runData = await createRun({
      workspaceId,
      message,
      autoApply,
      configurationVersionId: cv.id,
      token: tfcToken,
    });

    const runId = runData.id;
    const runUrl = `https://app.terraform.io/app/${tfcOrg}/workspaces/${targetName}/runs/${runId}`;

    // -----------------------------------------------------------------------
    // 9. Set outputs
    // -----------------------------------------------------------------------
    core.setOutput("run_id", runId);
    core.setOutput("run_url", runUrl);
    core.setOutput("workspace_id", workspaceId);
    core.setOutput("workspace_name", targetName);

    core.info(`Run created: ${runUrl}`);
  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message);
    } else {
      core.setFailed(String(error));
    }
  }
}

run();
