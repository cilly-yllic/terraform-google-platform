import { readFile } from "node:fs/promises";
import { parse as parseYaml } from "yaml";
import { z } from "zod";

// compute host（VM を置くプロジェクト）用の settings.yml。
// Action A（dispatch-project-bootstrap）と同じ形（service / environments / retained_envs）で、
// env ごとの `compute_host` を compute-host-platform モジュールの変数に渡す。
const environmentSchema = z.object({
  status: z.enum(["active", "inactive"]).default("active"),
  labels: z.array(z.string()).default([]),
  billing_account_id: z.string(),
  compute_host: z.record(z.string(), z.unknown()).optional(),
});

const settingsSchema = z.object({
  service: z.string(),
  // env を全部コメントアウトした teardown（`environments: null`）を許す（dispatch-firebase-platform と同じ）
  environments: z
    .record(z.string(), environmentSchema)
    .nullable()
    .transform((v) => v ?? {}),
  retained_envs: z.array(z.string()).default([]),
});

export type Settings = z.infer<typeof settingsSchema>;
export type EnvironmentEntry = z.infer<typeof environmentSchema>;
export type ComputeHostConfig = Record<string, unknown>;

export async function loadSettings(path: string): Promise<Settings> {
  const raw = await readFile(path, "utf-8");
  // merge: true で YAML の "<<" を使える（env 間で設定を共有する）
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

export function extractComputeHost(
  settings: Settings,
  env: string,
): ComputeHostConfig {
  const entry = extractEnvironment(settings, env);
  const config = entry.compute_host;
  if (!config || typeof config !== "object" || Array.isArray(config)) {
    throw new Error(
      `environments.${env}.compute_host section not found or not an object in settings.yml`,
    );
  }
  return config;
}
