export function expandWorkspaceName(
  pattern: string,
  vars: Record<string, string>
): string {
  let result = pattern;
  for (const [key, value] of Object.entries(vars)) {
    result = result.replace(new RegExp(`\\{${key}\\}`, "g"), () => value);
  }
  return result;
}

export function buildRunMessage(metadata: {
  service: string;
  environment: string;
  source_repo: string;
  sha: string;
}): string {
  return JSON.stringify(metadata);
}

export function mergeEnvironmentsMap(
  existing: Record<string, unknown>,
  environment: string,
  entry: Record<string, unknown>
): Record<string, unknown> {
  return { ...existing, [environment]: entry };
}
