/**
 * Hono app のサーバ lifecycle を一括で引き受けるモジュール。
 *
 * 担う責務:
 *   - app レベルの cross-cutting defaults (notFound / onError) の設定
 *   - @hono/node-server による HTTP listener の起動
 *   - 起動失敗時のクラッシュ処理
 *   - SIGTERM / SIGINT を受けた際の graceful shutdown
 *
 * これらを index.ts から分離している理由:
 *   index.ts は「アプリの形」を示す場所であり、lifecycle 周りのボイラープレートが
 *   そこに混ざるとルート構成が読み取りづらくなる。bootstrap として外出しすることで、
 *   将来サーバ挙動 (timeout 値、ログ shape、新しい signal handling 等) を変えたく
 *   なったときも触る場所がこのファイル 1 箇所で済む。
 *
 * @see ./log.ts          — 構造化ログヘルパー (Cloud Logging 互換 JSON)
 * @see ./index.ts        — このモジュールを呼ぶ唯一のエントリ
 */
import type { Hono } from "hono";
import { serve } from "@hono/node-server";
import { log } from "./log.js";

/**
 * SIGTERM を受け取ってから process.exit(1) で強制終了するまでの猶予時間。
 *
 * Cloud Run は SIGTERM 送信後、デフォルトで 10 秒後に SIGKILL を送る。
 * その前に自前で server.close() の完了を待ち切れるよう、8s に設定して
 * 余裕を 2s 持たせている。Cloud Run の termination grace period を
 * 変更している場合はこの値も合わせて見直すこと。
 *
 * @see https://cloud.google.com/run/docs/configuring/services/container-runtime-contract
 */
const SHUTDOWN_TIMEOUT_MS = 8_000;

export interface BootstrapOptions {
  port: number;
}

export const bootstrap = (app: Hono, opts: BootstrapOptions): void => {
  // 任意のルート未マッチを最終的に 404 として返す。
  // 各 sub-app では path を厳密に定義しているため、ここに到達するのは
  // 設定ミス or 攻撃的なスキャンのいずれか。レスポンス shape は他の
  // エラー (invalid_signature 等) と揃えて { error: <code> } にしている。
  app.notFound((c) => c.json({ error: "not_found" }, 404));

  // 各ハンドラ内で catch しきれなかった例外の最終フォールバック。
  // ここに到達する時点で「想定外」なので、詳細はクライアントに返さず
  // ERROR ログとして残し、500 + 汎用エラーコードを返す。
  app.onError((err, c) => {
    const msg = err instanceof Error ? err.message : String(err);
    log("ERROR", "Error processing request", { error: msg });
    return c.json({ error: "internal_error" }, 500);
  });

  // @hono/node-server は内部で node:http の Server を作って返す。
  // Cloud Run は PORT 環境変数で待受ポートを指定してくる (デフォルト 8080)。
  const server = serve({ fetch: app.fetch, port: opts.port }, (info) => {
    log("INFO", `Cloud Run router listening on port ${info.port}`);
  });

  // listen 自体に失敗する (port 衝突、権限不足 等) 場合のクラッシュハンドラ。
  // 復旧不能なので process.exit(1) → Cloud Run が再起動する。
  server.on("error", (err: Error) => {
    log("ERROR", "Server error", { error: err.message });
    process.exit(1);
  });

  // SIGTERM/SIGINT 連投で二重に shutdown が走ってログが混ざるのを防ぐためのガード。
  let shuttingDown = false;

  const shutdown = (): void => {
    if (shuttingDown) return;
    shuttingDown = true;

    log("INFO", "Received shutdown signal, draining connections…");

    // server.close() は in-flight な接続が無くなるまで callback を呼ばない。
    // 万一 keep-alive 接続が掴まっていて閉じない場合に備えて、上限を切って
    // 強制終了する。Cloud Run の SIGKILL より先に自前で exit(1) させたい。
    const forceExit = setTimeout(() => {
      log("WARNING", "Shutdown timeout exceeded, forcing exit");
      process.exit(1);
    }, SHUTDOWN_TIMEOUT_MS);

    // unref() しておかないとこの setTimeout 自体が event loop を生かしてしまい、
    // server.close() が即時 callback してもプロセスがすぐ終わらなくなる。
    forceExit.unref();

    server.close(() => {
      clearTimeout(forceExit);
      log("INFO", "Server closed, exiting");
      process.exit(0);
    });
  };

  // SIGTERM: Cloud Run の通常停止フロー (deploy 入れ替え、scale-to-zero 等)
  // SIGINT : ローカル開発時の Ctrl-C
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
};
