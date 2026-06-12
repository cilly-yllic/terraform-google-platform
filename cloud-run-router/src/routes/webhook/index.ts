/**
 * TFC Notification webhook → GitHub repository_dispatch。
 *
 * このサブ app は `src/index.ts` で `app.route("/webhook", ...)` されており、
 * Terraform Cloud から飛んでくる単一の POST リクエストを処理する。
 *
 * リクエスト処理の流れ:
 *   1. bodyLimit          — 上限を超えるペイロードを早期 reject (DoS ガード)
 *   2. raw body + HMAC    — X-TFE-Notification-Signature を検証 (必須)
 *   3. JSON parse         — 不正な JSON は 400 で reject
 *   4. verification ping  — destination URL 登録時に TFC が送ってくる
 *                           `notifications: []` の ping は 200 で acknowledge
 *                           するだけで dispatch は発火しない
 *   5. handleNotification — workspace 分類 → metadata 解決 → repository_dispatch
 *                           発火 (詳細ロジックは ../../router.ts)
 *
 * factory pattern (createWebhookRoute(config)) を採用している理由:
 *   ハンドラは config (HMAC secret, GitHub App credentials, metadata source
 *   等) に依存する。グローバル singleton を import すると依存が暗黙的になり、
 *   かつテストで config を差し替えづらくなる。factory にしておけば、
 *   - マウント時 (src/index.ts) に依存関係が一目で分かる
 *   - 将来テストで fake Config を作って `app.request()` で叩くのも容易
 *
 * body を `c.req.arrayBuffer()` で読んでから手動 JSON parse している理由:
 *   HMAC は **TFC が送ってきた raw bytes そのもの** に対して計算されている。
 *   `c.req.json()` を呼ぶと一度 deserialize → 再シリアライズが入り、
 *   空白やキー順序の差で digest が一致しなくなる。先に Buffer として
 *   取り出し、署名検証をパスしたあと同じ Buffer から JSON parse する。
 *
 * @see ../../router.ts            — handleNotification (workspace 分類と dispatch)
 * @see ../../signature.ts         — HMAC-SHA512 検証の詳細
 * @see ../../../README.md         — TFC Notification 設定と dispatch payload shape
 */
import { Hono } from 'hono'
import { bodyLimit } from 'hono/body-limit'
import type { Config } from '../../config.js'
import { log } from '../../log.js'
import { verifySignature } from '../../signature.js'
import { handleNotification, type TfcNotification } from '../../router.js'

/**
 * 1 MiB。TFC Notification payload は小さな JSON envelope (通常 <10 KiB)
 * なので、これは実用上の上限ではなく DoS ガード。
 * もし本当にここに引っかかる場合は、クライアント設定ミス or 攻撃を疑う。
 */
const MAX_BODY_BYTES = 1024 * 1024

export const createWebhookRoute = (config: Config): Hono => {
  const webhook = new Hono()

  webhook.post(
    '/',
    bodyLimit({
      maxSize: MAX_BODY_BYTES,
      onError: c => c.json({ error: 'payload_too_large' }, 413),
    }),
    async c => {
      // HMAC 検証のために raw bytes をそのまま保持する。
      // c.req.json() で先に parse すると再シリアライズで digest が一致しなくなる。
      const body = Buffer.from(await c.req.arrayBuffer())

      // HMAC 検証は **絶対必須**。公開 endpoint と GitHub への dispatch firehose
      // の間に立つ唯一のゲートなので、parse より先に実施する。
      // header 欠落 / 不一致はすべて 401 invalid_signature に畳む
      // (詳細を返すと攻撃側にヒントを与えるため)。
      const signature = c.req.header('x-tfe-notification-signature')
      if (!verifySignature(body, signature, config.tfcNotificationSecret)) {
        log('WARNING', 'HMAC signature verification failed')
        return c.json({ error: 'invalid_signature' }, 401)
      }

      let notification: TfcNotification
      try {
        notification = JSON.parse(body.toString('utf8')) as TfcNotification
      } catch {
        // 署名は通ったが JSON として壊れているケース。
        // 攻撃ではなく、TFC 側 or 我々のスキーマ理解のバグなので 400 で可視化する。
        return c.json({ error: 'invalid_json' }, 400)
      }

      // TFC は Notification 設定画面で "Verify" ボタンを押されたとき、
      // 通常 payload と同じ envelope を持つが `notifications: []` の
      // verification ping を送ってくる。これに 200 を返さないと TFC UI 上で
      // destination が "Failed" 扱いになり、以後の実イベントも届かなくなる。
      // dispatch は発火しないので、ここで早期 return する。
      if (!Array.isArray(notification.notifications) || notification.notifications.length === 0) {
        log('INFO', 'Verification ping received')
        return c.json({ status: 'ok', action: 'verification_ping' })
      }

      // 実イベント。以降の責務 (workspace 分類 / metadata 解決 / dispatch 発火)
      // は handleNotification に委譲。各分岐の構造化ログも router.ts 内で出す。
      const result = await handleNotification(notification, config)
      log('INFO', 'Request processed', { action: result.action })
      return c.json({ status: 'ok', ...result })
    }
  )

  return webhook
}
