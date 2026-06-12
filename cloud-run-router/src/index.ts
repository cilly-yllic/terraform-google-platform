/**
 * Cloud Run router のエントリポイント。
 *
 * 役割はオーケストレーションのみで、ここでは以下の 3 ステップしか行わない:
 *   1. 環境変数から Config を読み込む (起動時 fail fast)
 *   2. Hono の root app に各サブルート (健全性チェック / TFC webhook) をマウント
 *   3. server.ts の bootstrap() に渡してサーバ起動 + lifecycle を任せる
 *
 * ルート分割の方針:
 *   - 各ルートは `src/routes/<name>/index.ts` で Hono の sub-app として定義
 *   - 親 app の `app.route(path, subApp)` でマウントすると、sub-app 側の
 *     パスはマウントポイント基準の相対パスになる ("/" → "/healthz" など)
 *
 * 新規ルートを追加するときは:
 *   1. `src/routes/<name>/index.ts` を作成
 *   2. 必要なら config を受け取る factory pattern にする (webhook 参照)
 *   3. ここに `app.route("/<name>", ...)` を 1 行追加
 *
 * @see ./server.ts                       — bootstrap (notFound / onError / serve / graceful shutdown)
 * @see ./routes/healthz/index.ts         — Cloud Run probe 用 health check
 * @see ./routes/webhook/index.ts         — TFC Notification 受信エンドポイント
 * @see ./config.ts                       — 環境変数からの Config 構築
 */
import { Hono } from 'hono'
import { loadConfig } from './config.js'
import healthz from './routes/healthz/index.js'
import { createWebhookRoute } from './routes/webhook/index.js'
import { bootstrap } from './server.js'

// 起動時に環境変数を一度だけ評価。検証に失敗すれば例外で即終了する
// (Cloud Run 上では再起動ループになり、ログから設定ミスがすぐ分かる)。
const config = loadConfig()

const app = new Hono()

// /healthz は config 不要 (auth/ロジック共になし) なので default export を直接マウント。
app.route('/healthz', healthz)

// /webhook は config (HMAC secret, GitHub App credentials 等) に依存するため、
// factory pattern で明示的に注入する。詳細は routes/webhook/index.ts を参照。
app.route('/webhook', createWebhookRoute(config))

// notFound / onError / serve / graceful shutdown はすべて bootstrap 側に集約。
// index.ts はあくまで「何が何処にマウントされているか」だけを示す。
bootstrap(app, { port: config.port })
