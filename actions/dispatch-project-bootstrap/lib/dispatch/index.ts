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

// ---------------------------------------------------------------------------
// Environment gating (status + label regex AND match)
// ---------------------------------------------------------------------------

export type SkipReason = "status_inactive" | "labels_mismatch";

export interface SkipDecision {
  skip: boolean;
  reason?: SkipReason;
  detail?: string;
}

export function parseLabelsInput(raw: string): string[] {
  const trimmed = raw.trim();
  if (trimmed === "") return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch (e) {
    throw new Error(
      `Invalid labels input: expected a JSON array of strings (e.g. '["^tier:dev$","^region:apne1$"]'), got ${JSON.stringify(raw)} — ${
        e instanceof Error ? e.message : String(e)
      }`
    );
  }
  if (!Array.isArray(parsed)) {
    throw new Error(
      `Invalid labels input: expected a JSON array of strings, got ${typeof parsed}`
    );
  }
  return parsed.map((v, i) => {
    if (typeof v !== "string") {
      throw new Error(
        `Invalid labels input: element [${i}] must be a string, got ${typeof v} (${JSON.stringify(v)})`
      );
    }
    return v;
  });
}

export function evaluateEnvironmentGate(args: {
  status: "active" | "inactive";
  envLabels: string[];
  inputLabelPatterns: string[];
}): SkipDecision {
  if (args.status === "inactive") {
    return {
      skip: true,
      reason: "status_inactive",
      detail: 'environment status is "inactive"',
    };
  }
  if (args.inputLabelPatterns.length === 0) {
    return { skip: false };
  }
  const unmatched: string[] = [];
  for (const pattern of args.inputLabelPatterns) {
    let re: RegExp;
    try {
      re = new RegExp(pattern);
    } catch (e) {
      throw new Error(
        `Invalid regex in labels input: ${JSON.stringify(pattern)} — ${
          e instanceof Error ? e.message : String(e)
        }`
      );
    }
    if (!args.envLabels.some((l) => re.test(l))) {
      unmatched.push(pattern);
    }
  }
  if (unmatched.length > 0) {
    return {
      skip: true,
      reason: "labels_mismatch",
      detail: `env labels [${args.envLabels.join(", ")}] did not match required pattern(s): [${unmatched.join(", ")}]`,
    };
  }
  return { skip: false };
}
