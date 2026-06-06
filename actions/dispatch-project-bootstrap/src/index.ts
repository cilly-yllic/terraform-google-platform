import * as core from "@actions/core";
import * as github from "@actions/github";
import * as fs from "fs";
import * as path from "path";

import { TfcClient } from "../lib/tfc";
import { parseSettings, extractEnvironment } from "../lib/settings";
import { resolveBillingAccount } from "../lib/billing";
import { fetchFileViaApp } from "../lib/github";
import { expandWorkspaceName, buildRunMessage } from "../lib/dispatch";

async function run(): Promise<void> {
  try {
    // ---- Read inputs ----
    const service = core.getInput("service", { required: true });
    const environment = core.getInput("environment", { required: true });
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
    const billingRegistryRepo = core.getInput("billing_registry_repo", {
      required: true,
    });

    if (!billingRegistryRepo.includes("/") || billingRegistryRepo.split("/").length !== 2) {
      throw new Error(
        `billing_registry_repo must be in "owner/repo" format, got: "${billingRegistryRepo}"`
      );
    }
    const billingRegistryPath = core.getInput("billing_registry_path");
    const githubAppId = core.getInput("github_app_id", { required: true });
    const githubAppPrivateKey = core.getInput("github_app_private_key", {
      required: true,
    });
    const tfcToken = core.getInput("tfc_token", { required: true });
    const enableWebhook =
      core.getInput("enable_webhook_notification") === "true";
    const cloudRunWebhookUrl = core.getInput("cloud_run_webhook_url");
    const cloudRunWebhookSecret = core.getInput("cloud_run_webhook_secret");

    // Mask sensitive values
    core.setSecret(tfcToken);
    core.setSecret(githubAppPrivateKey);
    if (cloudRunWebhookSecret) core.setSecret(cloudRunWebhookSecret);

    // ---- 1. Read settings.yml ----
    core.info(`Reading settings from ${settingsPath}`);
    const workspace = process.env.GITHUB_WORKSPACE ?? process.cwd();
    const settingsFullPath = path.resolve(workspace, settingsPath);
    const settingsRaw = fs.readFileSync(settingsFullPath, "utf-8");
    const settings = parseSettings(settingsRaw);
    core.info(`Parsed settings for service: ${settings.service}`);

    // ---- 2. Extract environment config ----
    const envConfig = extractEnvironment(settings, environment);
    core.info(
      `Environment "${environment}": project_id=${envConfig.project_id}, billing_account_key=${envConfig.billing_account_key}`
    );

    // ---- 3. Fetch billing-accounts.yml via GitHub App ----
    core.info(
      `Fetching billing registry from ${billingRegistryRepo}/${billingRegistryPath}`
    );
    const [billingOwner, billingRepo] = billingRegistryRepo.split("/");
    const billingRaw = await fetchFileViaApp(
      { appId: githubAppId, privateKey: githubAppPrivateKey },
      billingOwner,
      billingRepo,
      billingRegistryPath
    );

    // ---- 4. Resolve billing_account_key -> billing_account_id ----
    const billingAccountId = resolveBillingAccount(
      billingRaw,
      envConfig.billing_account_key
    );
    core.info(`Resolved billing_account_key -> billing_account_id`);
    core.setSecret(billingAccountId);

    // ---- 5. Upsert TFC Workspace ----
    const tfc = new TfcClient({ token: tfcToken, org: tfcOrg });
    const workspaceName = expandWorkspaceName(tfcWorkspacePattern, { service });
    core.info(`Upserting workspace: ${workspaceName}`);

    const ws = await tfc.upsertWorkspace(workspaceName, {
      "auto-apply": true,
      "execution-mode": "remote",
    });
    core.info(`Workspace ready: id=${ws.id}`);

    // ---- 6. (Phase 2) Notification config upsert ----
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

    // ---- 7-9. Read-modify-write environments variable ----
    core.info("Updating environments variable (read-modify-write with etag)");
    const envEntry: Record<string, string> = {
      project_id: envConfig.project_id,
      billing_account_id: billingAccountId,
      terraform_service_account_id: `terraform-${service}-${environment}`,
      tfc_workspace_name: `${service}-${environment}`,
    };
    await tfc.readModifyWriteEnvironments(
      ws.id,
      environment,
      envEntry
    );
    core.info("environments variable updated successfully");

    // ---- 10. Sync Environment Variables (TFC Dynamic Credentials) ----
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

    // ---- Sync Terraform Variables ----
    // NOTE: `parent` and `environments` are stored as JSON strings (hcl: false).
    // The consuming Terraform workspace is expected to use jsondecode().
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

    // ---- 11. Create Run ----
    const context = github.context;
    const runMessage = buildRunMessage({
      service,
      environment,
      source_repo: `${context.repo.owner}/${context.repo.repo}`,
      sha: context.sha,
    });

    core.info("Creating Terraform Cloud Run (auto-apply: true)");
    const tfcRun = await tfc.createRun(ws.id, {
      message: runMessage,
      autoApply: true,
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
