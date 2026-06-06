import { readFile } from "node:fs/promises";
import { parse as parseYaml } from "yaml";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface FirebasePlatformConfig {
  [key: string]: unknown;
}

export interface EnvironmentEntry {
  project_id?: string;
  billing_account_key?: string;
  firebase_platform?: FirebasePlatformConfig;
  [key: string]: unknown;
}

export interface Settings {
  service?: string;
  environments?: Record<string, EnvironmentEntry>;
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

export async function loadSettings(path: string): Promise<Settings> {
  const raw = await readFile(path, "utf-8");
  const data = parseYaml(raw) as Settings;
  if (!data || typeof data !== "object") {
    throw new Error(`settings.yml at "${path}" is not a valid YAML object`);
  }
  return data;
}

export function extractEnvironment(
  settings: Settings,
  env: string,
): EnvironmentEntry {
  const envs = settings.environments;
  if (!envs || !envs[env]) {
    throw new Error(
      `Environment "${env}" not found in settings.yml. Available: ${
        envs ? Object.keys(envs).join(", ") : "(none)"
      }`,
    );
  }
  return envs[env];
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
