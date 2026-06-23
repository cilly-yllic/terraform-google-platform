import * as core from "@actions/core";
import {
  upsertProject,
  upsertWorkspace,
  addWorkspaceTags,
  listWorkspacesByTag,
  deleteWorkspace,
  syncVariables,
  upsertNotification,
  listNotifications,
  upsertNotificationConfig,
  deleteNotification,
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
  expandFirebasePlatformPlaceholders,
  resolveAutoApply,
  buildTerraformVariables,
  buildEnvVariables,
  buildRunMessage,
  parseLabelsInput,
  parseEnvironmentsInput,
  selectTargetEnvs,
  buildMarkerTag,
  deriveEnvFromWorkspaceName,
  parseNotifications,
  NOTIFICATION_NAME_PREFIX,
} from "../lib/dispatch/index.js";
import { buildTemplateFiles } from "../lib/templates/index.js";
import { resolveModuleVersion } from "../lib/registry/index.js";
import { buildTarball } from "../lib/config-version/index.js";

async function run(): Promise<void> {
  try {
    // -----------------------------------------------------------------------
    // 1. Read inputs
    // -----------------------------------------------------------------------
    const service = core.getInput("service", { required: true });
    const environmentsInputRaw = core.getInput("environments");
    const settingsPath = core.getInput("settings_path");
    const tfcOrg = core.getInput("tfc_org", { required: true });
    const targetWorkspacePattern = core.getInput("target_workspace");
    const tfcProjectPattern = core.getInput("tfc_project_name");
    // 注: bootstrap_project_id input は WIF pool 等の文脈で残すが、per-env SA は
    // ターゲットプロジェクト内に作るようになったため saEmail には使わない
    // (bootstrapProjectNumber は WIF provider path 用に引き続き使用)。
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
    const environmentsInput = parseEnvironmentsInput(environmentsInputRaw);
    const inputLabelPatterns = parseLabelsInput(labelsInput);
    if (environmentsInput.length === 0 && inputLabelPatterns.length === 0) {
      throw new Error(
        "Either `environments` or `labels` input must be non-empty.",
      );
    }
    const { targets, filtered } = selectTargetEnvs({
      settings,
      environmentsInput,
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
    // 4. Resolve module version (auto-fetch latest from Terraform Registry
    //    when not pinned)
    // -----------------------------------------------------------------------
    // moduleVersion 未指定なら Terraform Registry から最新版 (pre-release 含む)
    // を auto-resolve する。Terraform は version 制約なしだと pre-release を
    // 拾わない仕様 (`0.0.0-rcN` しか公開されていない現状だと "no versions
    // available" になる) ため、Action 側で明示的に最新版を埋める。
    const resolvedModuleVersion = await resolveModuleVersion(moduleVersion);
    const wasAutoResolved = !moduleVersion || moduleVersion.trim() === "";
    core.info(
      wasAutoResolved
        ? `Module version auto-resolved to ${resolvedModuleVersion}`
        : `Module version pinned to ${resolvedModuleVersion}`,
    );

    // -----------------------------------------------------------------------
    // 5. Upsert TFC Project (per service, shared across all env workspaces)
    // -----------------------------------------------------------------------
    // service ごとに 1 つの TFC project を upsert し、以降の env workspace は
    // すべてこの project 配下に集約する。既存 workspace が Default Project
    // 等に居る場合は upsertWorkspace 内で relationships.project を PATCH して
    // 自動で migration する。
    const projectName = expandWorkspaceName(tfcProjectPattern, { service });
    core.info(`Upserting project: ${projectName}`);
    const project = await upsertProject(tfcOrg, projectName, tfcToken);
    core.info(`Project ready: id=${project.id}`);

    // -----------------------------------------------------------------------
    // 6. Loop over target envs — upsert workspace + Run for each
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
        const firebasePlatformRaw = extractFirebasePlatform(settings, env);
        // `${service}` / `${env}` / `${BOOTSTRAP_PROJECT_NUMBER}` placeholder を
        // 全 string 値で展開する。
        // 主用途:
        //   - `${service}` / `${env}` で anchor 共有 + env-prefix 分離
        //   - `${BOOTSTRAP_PROJECT_NUMBER}` で ci_service_account.wif.pool_resource_name
        //     のようなインフラ識別子を yml に書かず Action input 経由で注入
        const firebasePlatform = expandFirebasePlatformPlaceholders(
          firebasePlatformRaw,
          {
            service: settings.service,
            env,
            bootstrapProjectNumber,
          },
        );
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
        // per-env terraform SA はターゲット (firebase 用) プロジェクト内に存在する
        // (project-bootstrap がそこに作成)。infra ではなく projectId 側を指すこと。
        // これにより firebase API 呼び出しの quota がターゲットに帰属し、
        // 「Firebase Management API has not been used in project <infra>」を回避する。
        const saEmail = `${saId}@${projectId}.iam.gserviceaccount.com`;
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
        // upsertWorkspace は relationships.project を見て、既存 workspace が
        // 別 project に居る場合は PATCH で project を張り替える (Default
        // Project → service project の migration もこれで完結する)。
        const workspace = await upsertWorkspace(
          tfcOrg,
          { name: targetName, "auto-apply": autoApply },
          tfcToken,
          project.id,
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

        // apply 結果通知 (Slack 等) — settings.yml の firebase_platform.notifications を
        // 各 env workspace の TFC notification として reconcile する。
        // オプション機能なので未設定なら no-op。Router 用 firebase-platform-webhook
        // とは別名 (firebase-platform-notify-*) で共存する。
        const notifications = parseNotifications(firebasePlatform);
        // Slack URL 等は機密なのでログ mask する。
        for (const n of notifications) core.setSecret(n.url);
        const existingNotifs = await listNotifications(workspaceId, tfcToken);
        for (let ni = 0; ni < notifications.length; ni++) {
          const n = notifications[ni];
          await upsertNotificationConfig(
            workspaceId,
            {
              name: `${NOTIFICATION_NAME_PREFIX}${ni}`,
              destinationType: n.destinationType,
              url: n.url,
              triggers: n.triggers,
              hmacToken: n.hmacToken,
            },
            existingNotifs,
            tfcToken,
          );
        }
        // 宣言から消えた firebase-platform-notify-* は削除 (reconcile)。
        for (const e of existingNotifs) {
          const m = e.attributes.name.match(/^firebase-platform-notify-(\d+)$/);
          if (m && Number(m[1]) >= notifications.length) {
            await deleteNotification(e.id, tfcToken);
          }
        }
        if (notifications.length > 0) {
          core.info(
            `[${env}] Synced ${notifications.length} apply-result notification(s)`,
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
          buildTemplateFiles(resolvedModuleVersion),
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
          module_version: resolvedModuleVersion,
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
