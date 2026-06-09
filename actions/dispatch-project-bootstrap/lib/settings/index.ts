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
});

export type Settings = z.infer<typeof settingsSchema>;
export type EnvironmentConfig = z.infer<typeof environmentSchema>;

export function parseSettings(raw: string): Settings {
  // merge: true enables YAML "<<" merge keys for DRY-ing repeated env config.
  const parsed: unknown = parseYaml(raw, { merge: true });
  return settingsSchema.parse(parsed);
}

export function extractEnvironment(
  settings: Settings,
  env: string
): EnvironmentConfig {
  const envConfig = settings.environments[env];
  if (!envConfig) {
    throw new Error(
      `Environment "${env}" not found in settings.yml. Available: ${Object.keys(
        settings.environments
      ).join(", ")}`
    );
  }
  return envConfig;
}
