/**
 * Health check endpoint. Mounted at `/healthz`.
 * No auth / no side effects so Cloud Run probes can hit it freely.
 */
import { Hono } from "hono";

const healthz = new Hono();

healthz.get("/", (c) => c.json({ status: "ok" }));

export default healthz;
