import { Hono } from "hono";
import { loadConfig } from "./config.js";
import healthz from "./routes/healthz/index.js";
import { createWebhookRoute } from "./routes/webhook/index.js";
import { bootstrap } from "./server.js";

const config = loadConfig();

const app = new Hono();
app.route("/healthz", healthz);
app.route("/webhook", createWebhookRoute(config));

bootstrap(app, { port: config.port });
