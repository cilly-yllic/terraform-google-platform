/**
 * TFC Notification webhook → GitHub repository_dispatch. Mounted at `/webhook`.
 *
 * Factory pattern (`createWebhookRoute(config)`) keeps the config dependency
 * explicit instead of relying on a module-level singleton.
 *
 * Body is read as raw bytes (`arrayBuffer()`) before parsing so the HMAC
 * digest is computed against the exact wire payload.
 */
import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import type { Config } from "../../config.js";
import { log } from "../../log.js";
import { verifySignature } from "../../signature.js";
import { handleNotification, type TfcNotification } from "../../router.js";

const MAX_BODY_BYTES = 1024 * 1024; // 1 MiB DoS guard; TFC payloads are <10 KiB

export const createWebhookRoute = (config: Config): Hono => {
  const webhook = new Hono();

  webhook.post(
    "/",
    bodyLimit({
      maxSize: MAX_BODY_BYTES,
      onError: (c) => c.json({ error: "payload_too_large" }, 413),
    }),
    async (c) => {
      const body = Buffer.from(await c.req.arrayBuffer());

      // HMAC verification (mandatory).
      const signature = c.req.header("x-tfe-notification-signature");
      if (!verifySignature(body, signature, config.tfcNotificationSecret)) {
        log("WARNING", "HMAC signature verification failed");
        return c.json({ error: "invalid_signature" }, 401);
      }

      let notification: TfcNotification;
      try {
        notification = JSON.parse(body.toString("utf8")) as TfcNotification;
      } catch {
        return c.json({ error: "invalid_json" }, 400);
      }

      // TFC sends a verification ping with no notifications when the destination
      // URL is first registered — acknowledge with 200 without dispatching.
      if (!Array.isArray(notification.notifications) || notification.notifications.length === 0) {
        log("INFO", "Verification ping received");
        return c.json({ status: "ok", action: "verification_ping" });
      }

      const result = await handleNotification(notification, config);
      log("INFO", "Request processed", { action: result.action });
      return c.json({ status: "ok", ...result });
    },
  );

  return webhook;
};
