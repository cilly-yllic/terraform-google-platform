/**
 * TFC Notification を受けて GitHub への dispatch 発火を判定するコアロジック。
 *
 * webhook 受信の HTTP 層 (署名検証 / JSON parse / verification ping) は
 * `routes/webhook/index.ts` 側で済んでいるので、ここでは「正規の payload が
 * 来た」前提で **workspace 名の分類** と **metadata 解決** と
 * **repository_dispatch 発火** の判断のみを担う。
 *
 * 分類は 3 種類:
 *   - project_factory : Phase 2 の起点。applied なら GitHub Actions の Action B
 *                       (firebase-platform 構築) を repository_dispatch で起動する
 *   - terminal        : Phase 2 の末端 (firebase-platform stage)。チェーンする
 *                       先がないので no-op で締める (監査ログだけ残す)
 *   - unknown         : 命名規約に合わないワークスペース。通常は設定ミスなので
 *                       WARNING で記録 (落とすのではなく無視する)
 *
 * Status フィルタの方針:
 *   project_factory は `applied` のみ採用する。planned / queued / errored 等
 *   の中間 / 失敗ステータスでも TFC は notification を送ってくるが、
 *   それで dispatch を発火すると下流 (Action B) で「実体が無いプロジェクト」
 *   に対して動こうとして連鎖的に失敗するため、ここで止める。
 *
 * 構造化ログの粒度:
 *   どのブランチを通っても workspace_name / run_id / run_status / organization /
 *   route を必ず出す (logBase)。これで Cloud Logging から「特定 run の経路」を
 *   後追いしやすくしている。
 *
 * @see ./routes/webhook/index.ts  — この関数を呼ぶ唯一のエントリ
 * @see ./tfc-client.ts            — metadata 解決 (run_message / TFC API)
 * @see ./github-client.ts         — repository_dispatch の HTTP 呼び出し
 */
import type { Config } from "./config.js";
import type { TfcRunMeta } from "./tfc-client.js";
import { fetchRunMetadata, parseRunMessage } from "./tfc-client.js";
import { repositoryDispatch } from "./github-client.js";

/**
 * TFC Notification payload のうち、本ルータが参照するフィールドだけを表す型。
 * TFC は実際にはもっと多くのフィールドを送ってくるが、interface を絞っておくと
 * TFC 側の payload 変更影響を最小限に抑えられる。
 *
 * @see https://developer.hashicorp.com/terraform/cloud-docs/api-docs/notification-configurations#payload-shape
 */
export interface TfcNotification {
  payload_version: number;
  notification_configuration_id: string;
  run_url: string;
  run_id: string;
  /**
   * Run 起動時に渡されたメッセージ。
   * Action A / B はここに metadata JSON (service / environments / labels /
   * source_repo / sha) を埋め込んで emit する → Option B のソース。
   */
  run_message: string;
  run_created_at: string;
  run_created_by: string;
  workspace_id: string;
  workspace_name: string;
  organization_name: string;
  /**
   * 同一 Run に対する複数の trigger 通知 (queued → planning → applied 等) が
   * まとまって配列で来る。Notification 設定では通常 `run:completed` だけを
   * subscribe しているが、TFC 側仕様で常に配列形式で送られる。
   * 末尾の要素が最新ステータス (latestStatus) を保持しているとみなして処理する。
   *
   * 空配列の場合は verification ping (上流 webhook ハンドラで吸収済み)。
   */
  notifications: Array<{
    message: string;
    trigger: string;
    run_status: string;
    run_updated_at: string;
    run_updated_by: string;
  }>;
}

/**
 * workspace 名から推定したパイプライン上の役割。
 * unknown は「既知パターンのどちらにも合わなかった」状態で、
 * ignored (warn ログのみ) として扱う。
 */
export type RouteResult =
  | { stage: "project_factory"; service: string }
  | { stage: "terminal"; service: string; env: string }
  | { stage: "unknown" };

/**
 * workspace 名を Config の 2 つの regex に順次マッチさせて分類する。
 *
 * - 先に projectFactoryPattern (起点) を試す
 *   → service named group を取り出して project_factory にバインド
 * - 次に terminalPattern (末端) を試す
 *   → service / env を取り出して terminal にバインド
 * - どちらにも合わなければ unknown
 *
 * デフォルトの terminalPattern は `^(?<service>.+)-(?<env>[^-]+)$` で、
 * 「最後のハイフン区切りセグメントを env、残りを service」として扱う
 * (例: my-cool-service-dev → service=my-cool-service, env=dev)。
 */
export const classifyWorkspace = (workspaceName: string, config: Config): RouteResult => {
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
};

/**
 * Run metadata (service / environments / labels / source_repo) を取得する。
 * Config.metadataSource の設定によって解決経路が変わる:
 *
 * - "run_message"   : Action A/B が run_message JSON 内に埋め込んだ metadata を
 *                     parse して使う。Phase 2 の標準パス (TFC API 不要)。
 *                     parse 失敗時は fallback せず throw する。
 * - "run_variables" : TFC API で workspace 変数を引いて metadata を組み立てる
 *                     (旧 Action / migration 期間用)。
 * - "both"          : run_message を先に試し、失敗時のみ TFC API にフォールバック。
 *                     本番運用のデフォルト。
 *
 * "both" モードで TFC_API_TOKEN が無い設定は loadConfig() の時点で reject
 * しているはずだが、防御的に再チェックしている (将来 config を別ルートで
 * 構築するケースに備えた fail-fast)。
 *
 * @see ./tfc-client.ts  — parseRunMessage / fetchRunMetadata の具体実装
 */
const resolveMetadata = async (
  notification: TfcNotification,
  service: string,
  config: Config,
): Promise<TfcRunMeta> => {
  if (config.metadataSource === "run_message" || config.metadataSource === "both") {
    const parsed = parseRunMessage(notification.run_message);
    if (parsed) {
      return parsed;
    }
    // "run_message" 単独モードでは fallback 先が無いので即 throw。
    // "both" モードはこの後の TFC API ブロックに進む。
    if (config.metadataSource === "run_message") {
      throw new Error(
        `run_message does not contain valid metadata JSON: "${notification.run_message}"`,
      );
    }
  }

  if (config.metadataSource === "run_variables" || config.metadataSource === "both") {
    if (!config.tfcApiToken) {
      throw new Error(
        "TFC_API_TOKEN is required when metadata_source is run_variables or both (fallback)",
      );
    }
    return fetchRunMetadata(notification.run_id, config.tfcApiBaseUrl, config.tfcApiToken);
  }

  // ここに到達するのは Config.metadataSource が型に無い未知の値だった場合のみ。
  // validateMetadataSource で起動時に弾いているはずだが、type narrowing 用に残す。
  throw new Error(`Cannot resolve metadata for service=${service}`);
};

export interface HandleResult {
  /**
   * - "dispatched"    : GitHub repository_dispatch を実際に発火した
   * - "terminal_noop" : terminal stage の正常完了 (チェーンせず終わり)
   * - "ignored"       : 既知パターンだが処理対象外 (status != applied 等) /
   *                     パターン不一致 / notifications 空 のいずれか
   */
  action: "dispatched" | "terminal_noop" | "ignored";
  details: Record<string, unknown>;
}

/**
 * Notification 1 件を処理するメインルーティング。webhook ハンドラから呼ばれる。
 *
 * 戻り値の `action` でテスト容易性 / HTTP レスポンスの観測性を担保している
 * (HTTP 層は throw に応じて 500 を返すだけなので、業務ロジックの分岐結果は
 * このオブジェクトで明示する)。
 */
export const handleNotification = async (
  notification: TfcNotification,
  config: Config,
): Promise<HandleResult> => {
  // webhook ハンドラ側でも空 notifications は verification ping として吸収しているが、
  // 直接 handleNotification を呼ばれるテストや将来の別呼び出し元のため、
  // ここでも防御的に弾く。
  if (!Array.isArray(notification.notifications) || notification.notifications.length === 0) {
    return {
      action: "ignored",
      details: { reason: "no_notifications" },
    };
  }

  // TFC は同一 Run の状態遷移を時系列で配列に積んでくる (queued → planning →
  // applied 等)。我々が判定したいのは "最新ステータス" なので末尾を見る。
  const latestStatus =
    notification.notifications[notification.notifications.length - 1]?.run_status;

  const route = classifyWorkspace(notification.workspace_name, config);

  // 全ログで共通して付ける構造化フィールド。
  // Cloud Logging で run_id や workspace_name から経路を逆引きするための情報源。
  const logBase = {
    workspace_name: notification.workspace_name,
    run_id: notification.run_id,
    run_status: latestStatus,
    organization: notification.organization_name,
    route,
  };

  if (route.stage === "project_factory") {
    // applied 以外 (planned / errored / canceled 等) は下流に投げない。
    // ここで dispatch を発火すると Action B が「まだ存在しないリソース」に
    // 対して動いて連鎖失敗するので、必ず apply 成功時のみに絞る。
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

    // metadata 解決は Config 設定に従う (run_message / run_variables / both)。
    // ここで throw した場合は onError ハンドラで 500 になり、TFC 側は失敗扱いで
    // リトライする可能性がある (= TFC 側の再送に任せる)。
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

    // GitHub repository_dispatch 発火。
    // payload shape は Action B の input と合うように決めている (README 参照)。
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
    // パイプラインの末端。次にチェーンする先がないので no-op。
    // 監査ログのために INFO で 1 行残すだけにとどめる。
    console.log(
      JSON.stringify({
        severity: "INFO",
        message: "Terminal stage completed; no-op",
        ...logBase,
      }),
    );
    return { action: "terminal_noop", details: logBase };
  }

  // どの pattern にもマッチしなかった workspace。
  // 通常は workspace 命名規約から外れた手動作成 workspace か、
  // pattern (env 変数) の設定ミス。攻撃ではないので WARNING にとどめる。
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
};
