import { readFile } from "node:fs/promises";
import { parse as parseYaml } from "yaml";
import { z } from "zod";

const environmentSchema = z.object({
  status: z.enum(["active", "inactive"]).default("active"),
  labels: z.array(z.string()).default([]),
  billing_account_id: z.string(),
  firebase_platform: z.record(z.unknown()).optional(),
});

const settingsSchema = z.object({
  service: z.string(),
  environments: z.record(z.string(), environmentSchema),
  retained_envs: z.array(z.string()).default([]),
});

export type Settings = z.infer<typeof settingsSchema>;
export type EnvironmentEntry = z.infer<typeof environmentSchema>;
export type FirebasePlatformConfig = Record<string, unknown>;

export async function loadSettings(path: string): Promise<Settings> {
  const raw = await readFile(path, "utf-8");
  // merge: true enables YAML "<<" merge keys for DRY-ing repeated env config.
  const parsed: unknown = parseYaml(raw, { merge: true });
  return settingsSchema.parse(parsed);
}

export function extractEnvironment(
  settings: Settings,
  env: string,
): EnvironmentEntry {
  const envConfig = settings.environments[env];
  if (!envConfig) {
    throw new Error(
      `Environment "${env}" not found in settings.yml. Available: ${
        Object.keys(settings.environments).join(", ") || "(none)"
      }`,
    );
  }
  return envConfig;
}

export function extractFirebasePlatform(
  settings: Settings,
  env: string,
): FirebasePlatformConfig {
  const entry = extractEnvironment(settings, env);
  const fp = entry.firebase_platform;
  if (!fp || typeof fp !== "object") {
    throw new Error(
      `environments.${env}.firebase_platform section not found or not an object in settings.yml`,
    );
  }
  return fp;
}
