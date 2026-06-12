/**
 * Hono app の lifecycle bootstrap。
 * notFound / onError のデフォルト、HTTP listener 起動、エラー時のクラッシュ、
 * SIGTERM/SIGINT による graceful shutdown を一括で受け持つ。
 */
import type { Hono } from "hono";
import { serve } from "@hono/node-server";
import { log } from "./log.js";

// Cloud Run のデフォルト SIGKILL grace period は 10 秒。それより手前で
// server.close() のドレインを諦めて強制終了させる。
const SHUTDOWN_TIMEOUT_MS = 8_000;

export interface BootstrapOptions {
  port: number;
}

export const bootstrap = (app: Hono, opts: BootstrapOptions): void => {
  app.notFound((c) => c.json({ error: "not_found" }, 404));

  app.onError((err, c) => {
    const msg = err instanceof Error ? err.message : String(err);
    log("ERROR", "Error processing request", { error: msg });
    return c.json({ error: "internal_error" }, 500);
  });

  const server = serve({ fetch: app.fetch, port: opts.port }, (info) => {
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
};
