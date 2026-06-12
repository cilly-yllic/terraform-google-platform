export interface Config {
  port: number;

  /** HMAC shared secret for TFC notification verification */
  tfcNotificationSecret: string;

  /** TFC API token (required when metadata_source includes "run_variables") */
  tfcApiToken: string | undefined;

  /** TFC API base URL */
  tfcApiBaseUrl: string;

  /** GitHub App ID */
  githubAppId: string;

  /** GitHub App private key (PEM) */
  githubAppPrivateKey: string;

  /**
   * Regex for the project-factory stage workspace name.
   * Must contain a named capture group `service`.
   * Default: ^project-factory-(?<service>.+)$
   */
  projectFactoryPattern: RegExp;

  /**
   * Regex for the terminal (firebase-platform) stage workspace name.
   * Named capture groups `service` and `env` are optional.
   * Default: ^(?<service>.+)-(?<env>[^-]+)$
   * (env = last hyphen-separated segment, service = remainder)
   */
  terminalPattern: RegExp;

  /** event_type string sent in repository_dispatch */
  dispatchEventType: string;

  /**
   * How to resolve (service, env, source_repo) metadata.
   * "run_message" = parse run_message JSON (Option B)
   * "run_variables" = fetch via TFC API (Option A)
   * "both"          = try run_message first, fall back to run_variables
   */
  metadataSource: "run_message" | "run_variables" | "both";
}

const VALID_METADATA_SOURCES = ["run_message", "run_variables", "both"] as const;

function requiredEnv(name: string): string {
  const v = process.env[name];
  if (v === undefined || v === "") {
    throw new Error(
      v === undefined
        ? `Required environment variable ${name} is not set`
        : `Required environment variable ${name} is empty`,
    );
  }
  return v;
}

function validateMetadataSource(value: string): Config["metadataSource"] {
  if (!VALID_METADATA_SOURCES.includes(value as Config["metadataSource"])) {
    throw new Error(
      `Invalid METADATA_SOURCE "${value}". Must be one of: ${VALID_METADATA_SOURCES.join(", ")}`,
    );
  }
  return value as Config["metadataSource"];
}

function validateRegex(envName: string, pattern: string): RegExp {
  try {
    return new RegExp(pattern);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Invalid regex in ${envName}: "${pattern}" — ${msg}`);
  }
}

function validatePort(value: string): number {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error(`Invalid PORT "${value}". Must be an integer between 0 and 65535`);
  }
  return port;
}

export function loadConfig(): Config {
  const pfPattern = process.env["WORKSPACE_NAME_PATTERN"] ?? "^project-factory-(?<service>.+)$";
  const termPattern = process.env["TERMINAL_WORKSPACE_PATTERN"] ?? "^(?<service>.+)-(?<env>[^-]+)$";

  const metadataSource = validateMetadataSource(process.env["METADATA_SOURCE"] ?? "both");
  const tfcApiToken = process.env["TFC_API_TOKEN"];

  if ((metadataSource === "run_variables" || metadataSource === "both") && !tfcApiToken) {
    throw new Error(`TFC_API_TOKEN is required when METADATA_SOURCE is "${metadataSource}"`);
  }

  return {
    port: validatePort(process.env["PORT"] ?? "8080"),
    tfcNotificationSecret: requiredEnv("TFC_NOTIFICATION_SECRET"),
    tfcApiToken,
    tfcApiBaseUrl: process.env["TFC_API_BASE_URL"] ?? "https://app.terraform.io",
    githubAppId: requiredEnv("GITHUB_APP_ID"),
    githubAppPrivateKey: requiredEnv("GITHUB_APP_PRIVATE_KEY"),
    projectFactoryPattern: validateRegex("WORKSPACE_NAME_PATTERN", pfPattern),
    terminalPattern: validateRegex("TERMINAL_WORKSPACE_PATTERN", termPattern),
    dispatchEventType: process.env["DISPATCH_EVENT_TYPE"] ?? "firebase_platform_requested",
    metadataSource,
  };
}
