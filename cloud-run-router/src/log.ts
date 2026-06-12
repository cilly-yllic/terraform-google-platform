/**
 * 構造化 JSON ログヘルパー。
 *
 * Cloud Run の stdout は Cloud Logging に自動転送される。そのとき
 * 1 行 1 JSON で `severity` フィールドを含めると、Cloud Logging が
 * それをログレベルにマッピングしてくれる (Severity フィルタが効く)。
 * よって全ログをこのヘルパー経由で出すことで:
 *   - ログレベルの整合 (INFO / WARNING / ERROR)
 *   - 任意の構造化フィールド (`workspace_name`, `run_id` 等) の付与
 *   - フォーマットの一元化
 * を担保している。
 *
 * console.error ではなく console.log だけを使うのは意図的で、
 * Cloud Logging のレベル判定は stderr/stdout の区別ではなく
 * 上記の severity フィールドで行われるため、混ざると逆に解析が乱れる。
 *
 * @see https://cloud.google.com/logging/docs/agent/logging/configuration#special-fields
 */

type LogSeverity = "INFO" | "WARNING" | "ERROR";

export const log = (
  severity: LogSeverity,
  message: string,
  extra: Record<string, unknown> = {},
): void => {
  console.log(JSON.stringify({ severity, message, ...extra }));
};
