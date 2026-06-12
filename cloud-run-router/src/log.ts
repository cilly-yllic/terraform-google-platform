/**
 * Structured JSON log helper.
 * Cloud Run forwards stdout to Cloud Logging; the `severity` field maps to
 * log levels (INFO / WARNING / ERROR) on the Cloud Logging side.
 */
type LogSeverity = "INFO" | "WARNING" | "ERROR";

export const log = (
  severity: LogSeverity,
  message: string,
  extra: Record<string, unknown> = {},
): void => {
  console.log(JSON.stringify({ severity, message, ...extra }));
};
