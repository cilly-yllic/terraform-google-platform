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
  // service 用 GCP folder の数値 ID。指定時、そのサービスの全 project は
  // この folder 配下に作られる (action input parent_folder_id より優先)。
  // folder は事前作成し、bootstrap の root folder 配下に置くこと
  // (Factory SA の folder-scoped grant が継承で届くようにするため)。
  // YAML でクォート無し (例 `folder_id: 123456789012`) だと number として
  // パースされるため、coerce で文字列化して受ける (クォート忘れを許容)。
  folder_id: z.coerce.string().optional(),
  // teardown (全 env 撤去) シナリオを許容する。
  // 前提: settings.yml の env を全てコメントアウトすると、YAML パーサは
  //   `environments: null` を返す (キーは存在するが値が空)。project-bootstrap に
  //   とって空 environments は「この service の全 project を撤去する」意図であり、
  //   diff ロジック (computeReconciliation) は existing − settings − retained を
  //   destroyKeys として既に算出できる。ここで schema が null を弾くと、その
  //   destroy フローに到達できず "Expected object, received null" でクラッシュする。
  // 安全側の配慮: `.nullable()` は「キーは必須・値は null 可」を意味するため、
  //   `environments:` 自体を書き忘れた (= undefined) ケースは従来どおり Required
  //   エラーになる。意図的な空 teardown と記述ミスを区別する安全 floor。
  // 正規化: 後段は Object.keys(environments) で回す前提なので {} に潰す。
  environments: z
    .record(z.string(), environmentSchema)
    .nullable()
    .transform((v) => v ?? {}),
  retained_envs: z.array(z.string()).default([]),
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
