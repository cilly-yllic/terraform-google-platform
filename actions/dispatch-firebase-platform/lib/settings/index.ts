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
  // teardown (全 env 撤去) シナリオを許容する。
  // 前提: settings.yml の env を全てコメントアウトすると、YAML パーサは
  //   `environments: null` を返す (キーは存在するが値が空)。これは「この
  //   service の env を全撤去する」意図的な状態であり、reconciliation
  //   (src/index.ts の orphan workspace 削除) に正規ルートで乗せたい。
  //   ここで弾くと teardown が schema 段階でクラッシュして到達できない。
  // 安全側の配慮: `.nullable()` は「キーは必須・値は null 可」を意味するため、
  //   `environments:` 自体を丸ごと書き忘れた (= undefined) ケースは従来どおり
  //   Required エラーになる。空 teardown と記述ミスを区別する安全 floor。
  // 正規化: 後段は Object.keys(environments) で回す前提なので {} に潰す。
  //   retained_envs に挙げた env は reconciliation 側で削除対象から外れる。
  environments: z
    .record(z.string(), environmentSchema)
    .nullable()
    .transform((v) => v ?? {}),
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
