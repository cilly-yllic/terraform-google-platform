import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Verify the HMAC-SHA512 signature sent by Terraform Cloud.
 *
 * TFC computes `HMAC-SHA512(body, secret)` and sends the hex digest in
 * the `X-TFE-Notification-Signature` header.
 */
export function verifySignature(
  body: Buffer,
  signatureHeader: string | undefined,
  secret: string,
): boolean {
  if (!signatureHeader) {
    return false;
  }

  const expected = createHmac("sha512", secret).update(body).digest("hex");

  const sigBuf = Buffer.from(signatureHeader, "utf8");
  const expBuf = Buffer.from(expected, "utf8");

  if (sigBuf.length !== expBuf.length) {
    return false;
  }

  return timingSafeEqual(sigBuf, expBuf);
}
