/**
 * TFC Notification の HMAC-SHA512 署名検証。
 *
 * 仕様:
 *   TFC は Notification 設定時に登録された共有 secret で
 *   `HMAC-SHA512(request_body, secret)` を計算し、その hex digest を
 *   `X-TFE-Notification-Signature` リクエストヘッダに載せて送ってくる。
 *
 * セキュリティ上の前提:
 *   - **必ず raw body bytes** に対して計算する必要がある (JSON parse 後の
 *     再シリアライズではバイト列が一致しなくなる)
 *   - 比較は **timing-safe** に行う必要がある。
 *     単純な `===` だと最初の不一致文字でリターンするため、文字列長や先頭
 *     一致度から secret を推測する timing attack の余地が生まれる。
 *   - 不一致 / header 欠落 / secret 不一致 のいずれも boolean false 一本に
 *     畳んで返す (詳細情報をクライアントに伝えない)
 *
 * @see ./routes/webhook/index.ts  — この関数を webhook handler の最初で呼ぶ
 * @see https://developer.hashicorp.com/terraform/cloud-docs/api-docs/notification-configurations#payload-shape
 */
import { createHmac, timingSafeEqual } from "node:crypto";

export const verifySignature = (
  body: Buffer,
  signatureHeader: string | undefined,
  secret: string,
): boolean => {
  // ヘッダ自体が無い場合は早期 false。timingSafeEqual に空文字を渡すと
  // 長さ不一致で同じ false になるが、明示的に分岐した方が読みやすい。
  if (!signatureHeader) {
    return false;
  }

  // HMAC-SHA512 を hex digest として計算 (TFC が送ってくる形式と揃える)。
  const expected = createHmac("sha512", secret).update(body).digest("hex");

  // 比較を Buffer 同士で行うことで timingSafeEqual を使える。
  // utf8 でエンコードしているのは hex 文字列はすべて ASCII なため。
  const sigBuf = Buffer.from(signatureHeader, "utf8");
  const expBuf = Buffer.from(expected, "utf8");

  // timingSafeEqual は **長さが一致しない場合に例外を投げる** ので、
  // 先に長さチェックを挟んでから呼ぶ必要がある。
  // 長さ違いは早期 false で良い (= 攻撃者は長さの違いから内部状態を
  // 推測できないし、そもそも HMAC-SHA512 hex 長は固定で 128 文字)。
  if (sigBuf.length !== expBuf.length) {
    return false;
  }

  return timingSafeEqual(sigBuf, expBuf);
};
