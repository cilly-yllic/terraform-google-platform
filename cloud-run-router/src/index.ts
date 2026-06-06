import { createServer } from "node:http";
import { loadConfig } from "./config.js";
import { verifySignature } from "./signature.js";
import { handleNotification, type TfcNotification } from "./router.js";

const config = loadConfig();

const MAX_BODY_BYTES = 1024 * 1024; // 1 MiB — TFC payloads are small JSON

class BodyTooLargeError extends Error {
  constructor() {
    super("Request body too large");
    this.name = "BodyTooLargeError";
  }
}

function collectBody(
  req: import("node:http").IncomingMessage,
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let totalLength = 0;
    let settled = false;
    req.on("data", (c: Buffer) => {
      if (settled) return;
      totalLength += c.length;
      if (totalLength > MAX_BODY_BYTES) {
        settled = true;
        req.destroy();
        reject(new BodyTooLargeError());
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => {
      if (!settled) {
        settled = true;
        resolve(Buffer.concat(chunks));
      }
    });
    req.on("error", (err) => {
      if (!settled) {
        settled = true;
        reject(err);
      }
    });
  });
}

function pathname(raw: string | undefined): string {
  try {
    return new URL(raw ?? "/", "http://localhost").pathname;
  } catch {
    return raw ?? "/";
  }
}

const server = createServer(async (req, res) => {
  const path = pathname(req.url);

  // Health check
  if (req.method === "GET" && path === "/healthz") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }

  if (req.method !== "POST" || path !== "/webhook") {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "not_found" }));
    return;
  }

  try {
    let body: Buffer;
    try {
      body = await collectBody(req);
    } catch (collectErr) {
      if (collectErr instanceof BodyTooLargeError) {
        res.writeHead(413, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "payload_too_large" }));
        return;
      }
      throw collectErr;
    }

    // HMAC verification (mandatory)
    const rawSig = req.headers["x-tfe-notification-signature"];
    const signature = Array.isArray(rawSig) ? rawSig[0] : rawSig;
    if (!verifySignature(body, signature, config.tfcNotificationSecret)) {
      console.log(
        JSON.stringify({
          severity: "WARNING",
          message: "HMAC signature verification failed",
        }),
      );
      res.writeHead(401, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "invalid_signature" }));
      return;
    }

    let notification: TfcNotification;
    try {
      notification = JSON.parse(body.toString("utf8")) as TfcNotification;
    } catch {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "invalid_json" }));
      return;
    }

    // TFC sends a verification ping with payload_version=1 and no notifications
    if (
      !Array.isArray(notification.notifications) ||
      notification.notifications.length === 0
    ) {
      console.log(
        JSON.stringify({
          severity: "INFO",
          message: "Verification ping received",
        }),
      );
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok", action: "verification_ping" }));
      return;
    }

    const result = await handleNotification(notification, config);
    console.log(
      JSON.stringify({
        severity: "INFO",
        message: "Request processed",
        action: result.action,
      }),
    );
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", ...result }));
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.log(
      JSON.stringify({
        severity: "ERROR",
        message: "Error processing request",
        error: msg,
      }),
    );
    if (!res.headersSent) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "internal_error" }));
    }
  }
});

server.on("error", (err) => {
  console.log(
    JSON.stringify({
      severity: "ERROR",
      message: "Server error",
      error: err.message,
    }),
  );
  process.exit(1);
});

server.listen(config.port, () => {
  console.log(
    JSON.stringify({
      severity: "INFO",
      message: `Cloud Run router listening on port ${config.port}`,
    }),
  );
});

const SHUTDOWN_TIMEOUT_MS = 8_000; // Must be < Cloud Run's SIGKILL grace period (default 10 s)

let shuttingDown = false;

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;

  console.log(
    JSON.stringify({
      severity: "INFO",
      message: "Received shutdown signal, draining connections…",
    }),
  );
  const forceExit = setTimeout(() => {
    console.log(
      JSON.stringify({
        severity: "WARNING",
        message: "Shutdown timeout exceeded, forcing exit",
      }),
    );
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS);
  forceExit.unref();
  server.close(() => {
    clearTimeout(forceExit);
    console.log(
      JSON.stringify({
        severity: "INFO",
        message: "Server closed, exiting",
      }),
    );
    process.exit(0);
  });
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
