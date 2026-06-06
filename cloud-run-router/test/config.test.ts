import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { loadConfig } from "../src/config.js";

describe("loadConfig", () => {
  const originalEnv = { ...process.env };

  function setRequiredEnvs() {
    process.env["TFC_NOTIFICATION_SECRET"] = "test-secret";
    process.env["GITHUB_APP_ID"] = "12345";
    process.env["GITHUB_APP_PRIVATE_KEY"] = "fake-pem";
  }

  beforeEach(() => {
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it("loads valid config with defaults", () => {
    setRequiredEnvs();
    process.env["TFC_API_TOKEN"] = "tfc-token";
    const config = loadConfig();
    expect(config.port).toBe(8080);
    expect(config.tfcNotificationSecret).toBe("test-secret");
    expect(config.metadataSource).toBe("both");
    expect(config.dispatchEventType).toBe("firebase_platform_requested");
    expect(config.tfcApiBaseUrl).toBe("https://app.terraform.io");
  });

  it("throws on missing TFC_NOTIFICATION_SECRET", () => {
    process.env["GITHUB_APP_ID"] = "12345";
    process.env["GITHUB_APP_PRIVATE_KEY"] = "pem";
    process.env["METADATA_SOURCE"] = "run_message";
    expect(() => loadConfig()).toThrow("TFC_NOTIFICATION_SECRET");
  });

  it("throws on missing GITHUB_APP_ID", () => {
    process.env["TFC_NOTIFICATION_SECRET"] = "s";
    process.env["GITHUB_APP_PRIVATE_KEY"] = "pem";
    process.env["METADATA_SOURCE"] = "run_message";
    expect(() => loadConfig()).toThrow("GITHUB_APP_ID");
  });

  it("throws on invalid METADATA_SOURCE", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "invalid_value";
    expect(() => loadConfig()).toThrow('Invalid METADATA_SOURCE "invalid_value"');
  });

  it("throws when METADATA_SOURCE=run_variables without TFC_API_TOKEN", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "run_variables";
    expect(() => loadConfig()).toThrow(
      'TFC_API_TOKEN is required when METADATA_SOURCE is "run_variables"',
    );
  });

  it("accepts METADATA_SOURCE=run_variables when TFC_API_TOKEN is set", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "run_variables";
    process.env["TFC_API_TOKEN"] = "tfc-token";
    const config = loadConfig();
    expect(config.metadataSource).toBe("run_variables");
    expect(config.tfcApiToken).toBe("tfc-token");
  });

  it("throws on invalid PORT", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "run_message";
    process.env["PORT"] = "not-a-number";
    expect(() => loadConfig()).toThrow('Invalid PORT "not-a-number"');
  });

  it("throws on PORT out of range", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "run_message";
    process.env["PORT"] = "70000";
    expect(() => loadConfig()).toThrow('Invalid PORT "70000"');
  });

  it("throws on invalid regex in WORKSPACE_NAME_PATTERN", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "run_message";
    process.env["WORKSPACE_NAME_PATTERN"] = "[invalid";
    expect(() => loadConfig()).toThrow("Invalid regex in WORKSPACE_NAME_PATTERN");
  });

  it("throws on invalid regex in TERMINAL_WORKSPACE_PATTERN", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "run_message";
    process.env["TERMINAL_WORKSPACE_PATTERN"] = "(unclosed";
    expect(() => loadConfig()).toThrow(
      "Invalid regex in TERMINAL_WORKSPACE_PATTERN",
    );
  });

  it("throws when TFC_API_TOKEN missing with METADATA_SOURCE=run_variables", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "run_variables";
    expect(() => loadConfig()).toThrow(
      'TFC_API_TOKEN is required when METADATA_SOURCE is "run_variables"',
    );
  });

  it("throws when TFC_API_TOKEN missing with METADATA_SOURCE=both", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "both";
    expect(() => loadConfig()).toThrow(
      'TFC_API_TOKEN is required when METADATA_SOURCE is "both"',
    );
  });

  it("does not require TFC_API_TOKEN when METADATA_SOURCE=run_message", () => {
    setRequiredEnvs();
    process.env["METADATA_SOURCE"] = "run_message";
    const config = loadConfig();
    expect(config.metadataSource).toBe("run_message");
    expect(config.tfcApiToken).toBeUndefined();
  });

  it("accepts custom valid values", () => {
    setRequiredEnvs();
    process.env["PORT"] = "3000";
    process.env["METADATA_SOURCE"] = "run_message";
    process.env["DISPATCH_EVENT_TYPE"] = "custom_event";
    process.env["TFC_API_BASE_URL"] = "https://tfe.example.com";
    process.env["TFC_API_TOKEN"] = "tfc-token";
    process.env["WORKSPACE_NAME_PATTERN"] = "^pf-(?<service>.+)$";

    const config = loadConfig();
    expect(config.port).toBe(3000);
    expect(config.metadataSource).toBe("run_message");
    expect(config.dispatchEventType).toBe("custom_event");
    expect(config.tfcApiBaseUrl).toBe("https://tfe.example.com");
    expect(config.tfcApiToken).toBe("tfc-token");
    expect(config.projectFactoryPattern.source).toBe("^pf-(?<service>.+)$");
  });
});
