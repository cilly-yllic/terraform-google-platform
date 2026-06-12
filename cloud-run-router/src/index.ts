import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { bodyLimit } from "hono/body-limit";
import { loadConfig } from "./config.js";
import { verifySignature } from "./signature.js";
import { handleNotification, type TfcNotification } from "./router.js";

const config = loadConfig();

const MAX_BODY_BYTES = 1024 * 1024; // 1 MiB — TFC payloads are small JSON
const SHUTDOWN_TIMEOUT_MS = 8_000; // Must be < Cloud Run's SIGKILL grace period (default 10 s)

type LogSeverity = "INFO" | "WARNING" | "ERROR";
const log = (severity: LogSeverity, message: string, extra: Record<string, unknown> = {}): void => {
  console.log(JSON.stringify({ severity, message, ...extra }));
};

const app = new Hono();

app.get("/healthz", (c) => c.json({ status: "ok" }));

app.post(
  "/webhook",
  bodyLimit({
    maxSize: MAX_BODY_BYTES,
    onError: (c) => c.json({ error: "payload_too_large" }, 413),
  }),
  async (c) => {
    const body = Buffer.from(await c.req.arrayBuffer());

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

    // TFC sends a verification ping with payload_version=1 and no notifications
    if (!Array.isArray(notification.notifications) || notification.notifications.length === 0) {
      log("INFO", "Verification ping received");
      return c.json({ status: "ok", action: "verification_ping" });
    }

    const result = await handleNotification(notification, config);
    log("INFO", "Request processed", { action: result.action });
    return c.json({ status: "ok", ...result });
  },
);

app.notFound((c) => c.json({ error: "not_found" }, 404));

app.onError((err, c) => {
  const msg = err instanceof Error ? err.message : String(err);
  log("ERROR", "Error processing request", { error: msg });
  return c.json({ error: "internal_error" }, 500);
});

const server = serve({ fetch: app.fetch, port: config.port }, (info) => {
  log("INFO", `Cloud Run router listening on port ${info.port}`);
});

server.on("error", (err: Error) => {
  log("ERROR", "Server error", { error: err.message });
  process.exit(1);
});

let shuttingDown = false;
const shutdown = (): void => {
  if (shuttingDown) return;
  shuttingDown = true;

  log("INFO", "Received shutdown signal, draining connections…");
  const forceExit = setTimeout(() => {
    log("WARNING", "Shutdown timeout exceeded, forcing exit");
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS);
  forceExit.unref();
  server.close(() => {
    clearTimeout(forceExit);
    log("INFO", "Server closed, exiting");
    process.exit(0);
  });
};

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
