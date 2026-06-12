/**
 * Health check エンドポイント。
 *
 * 役割:
 *   - Cloud Run の startup probe / liveness probe (2xx を健全とみなす)
 *   - 外部監視 (Cloud Monitoring の Uptime Check, Cloud Armor のヘルスチェック等)
 *
 * 設計上の意図:
 *   - **認証なし / HMAC 検証なし** は意図的。Cloud Run の内部プローブは
 *     TFC の HMAC を署名できないため、auth を入れるとプローブ自体が
 *     失敗してインスタンスが起動不能とみなされてしまう。
 *   - **副作用ゼロ / I/O ゼロ** を維持する。プローブは数秒間隔で叩かれるため、
 *     ここで外部依存 (TFC API, GitHub API 等) に触れるとそれらの障害が
 *     直接 readiness 失敗に伝搬してしまう。
 *   - レスポンスは `{ "status": "ok" }` 固定。他のエラーレスポンスと
 *     shape を揃えてログ grep の一貫性を確保している。
 *
 * マウント先は `src/index.ts` で `app.route("/healthz", ...)` されているため、
 * このサブ app 内ではパスを `"/"` 相対で書く。
 *
 * @see https://cloud.google.com/run/docs/configuring/healthchecks
 */
import { Hono } from "hono";

const healthz = new Hono();

healthz.get("/", (c) => c.json({ status: "ok" }));

export default healthz;
