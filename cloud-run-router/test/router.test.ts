import { describe, it, expect, vi, beforeEach } from "vitest";
import type { TfcNotification } from "../src/router.js";
import type { Config } from "../src/config.js";

vi.mock("../src/github-client.js", () => ({
  repositoryDispatch: vi.fn().mockResolvedValue(undefined),
}));

import { classifyWorkspace, handleNotification } from "../src/router.js";
import { repositoryDispatch } from "../src/github-client.js";

function makeConfig(overrides: Partial<Config> = {}): Config {
  return {
    port: 8080,
    tfcNotificationSecret: "secret",
    tfcApiToken: undefined,
    tfcApiBaseUrl: "https://app.terraform.io",
    githubAppId: "12345",
    githubAppPrivateKey: "fake-pem",
    projectFactoryPattern: /^project-factory-(?<service>.+)$/,
    terminalPattern: /^(?<service>.+)-(?<env>[^-]+)$/,
    dispatchEventType: "firebase_platform_requested",
    metadataSource: "run_message",
    ...overrides,
  };
}

function makeNotification(
  overrides: Partial<TfcNotification> = {},
): TfcNotification {
  return {
    payload_version: 1,
    notification_configuration_id: "nc-123",
    run_url: "https://app.terraform.io/runs/run-abc",
    run_id: "run-abc",
    run_message:
      '{"service":"my-svc","environments":["dev-001"],"labels":["^tier:dev$"],"source_repo":"owner/repo","sha":"abc"}',
    run_created_at: "2025-01-01T00:00:00Z",
    run_created_by: "user",
    workspace_id: "ws-123",
    workspace_name: "project-factory-my-svc",
    organization_name: "my-org",
    notifications: [
      {
        message: "Run applied",
        trigger: "run:completed",
        run_status: "applied",
        run_updated_at: "2025-01-01T00:01:00Z",
        run_updated_by: "user",
      },
    ],
    ...overrides,
  };
}

describe("classifyWorkspace", () => {
  const config = makeConfig();

  it("matches project-factory-{service} pattern", () => {
    const result = classifyWorkspace("project-factory-billing", config);
    expect(result).toEqual({ stage: "project_factory", service: "billing" });
  });

  it("matches {service}-{env} terminal pattern", () => {
    const result = classifyWorkspace("billing-dev", config);
    expect(result).toEqual({
      stage: "terminal",
      service: "billing",
      env: "dev",
    });
  });

  it("returns unknown for unrecognised names", () => {
    const cfg = makeConfig({
      projectFactoryPattern: /^pf-(?<service>.+)$/,
      terminalPattern: /^term-(?<service>.+)-(?<env>.+)$/,
    });
    const result = classifyWorkspace("random-workspace", cfg);
    expect(result).toEqual({ stage: "unknown" });
  });

  it("handles multi-segment service names", () => {
    const result = classifyWorkspace(
      "project-factory-my-cool-service",
      config,
    );
    expect(result).toEqual({
      stage: "project_factory",
      service: "my-cool-service",
    });
  });

  it("terminal pattern assigns env as last segment for multi-hyphen names", () => {
    const result = classifyWorkspace("my-cool-service-dev", config);
    expect(result).toEqual({
      stage: "terminal",
      service: "my-cool-service",
      env: "dev",
    });
  });
});

describe("handleNotification", () => {
  beforeEach(() => {
    vi.mocked(repositoryDispatch).mockClear();
  });

  it("dispatches on project_factory applied with hybrid run_message metadata", async () => {
    const config = makeConfig();
    const notification = makeNotification();

    const result = await handleNotification(notification, config);

    expect(result.action).toBe("dispatched");
    expect(result.details).toMatchObject({
      target_repo: "owner/repo",
      service: "my-svc",
      environments: ["dev-001"],
      labels: ["^tier:dev$"],
    });
    expect(repositoryDispatch).toHaveBeenCalledWith(
      "12345",
      "fake-pem",
      "owner/repo",
      "firebase_platform_requested",
      expect.objectContaining({
        service: "my-svc",
        environments: ["dev-001"],
        labels: ["^tier:dev$"],
        run_id: "run-abc",
        workspace_name: "project-factory-my-svc",
        source_repo: "owner/repo",
      }),
    );
  });

  it("dispatches with empty labels when A was invoked with a single environment input", async () => {
    const config = makeConfig();
    const notification = makeNotification({
      run_message:
        '{"service":"my-svc","environments":["prd-001"],"labels":[],"source_repo":"owner/repo","sha":"abc"}',
    });

    const result = await handleNotification(notification, config);

    expect(result.action).toBe("dispatched");
    expect(repositoryDispatch).toHaveBeenCalledWith(
      "12345",
      "fake-pem",
      "owner/repo",
      "firebase_platform_requested",
      expect.objectContaining({
        service: "my-svc",
        environments: ["prd-001"],
        labels: [],
      }),
    );
  });

  it("dispatches with multiple environments when A processed a batch", async () => {
    const config = makeConfig();
    const notification = makeNotification({
      run_message:
        '{"service":"my-svc","environments":["dev-001","dev-002"],"labels":["^tier:dev$"],"source_repo":"owner/repo","sha":"abc"}',
    });

    const result = await handleNotification(notification, config);

    expect(result.action).toBe("dispatched");
    expect(repositoryDispatch).toHaveBeenCalledWith(
      "12345",
      "fake-pem",
      "owner/repo",
      "firebase_platform_requested",
      expect.objectContaining({
        environments: ["dev-001", "dev-002"],
        labels: ["^tier:dev$"],
      }),
    );
  });

  it("ignores project_factory with non-applied status", async () => {
    const config = makeConfig();
    const notification = makeNotification({
      notifications: [
        {
          message: "",
          trigger: "run:completed",
          run_status: "errored",
          run_updated_at: "",
          run_updated_by: "",
        },
      ],
    });
    const result = await handleNotification(notification, config);
    expect(result.action).toBe("ignored");
    expect(result.details).toHaveProperty("reason", "status_not_applied");
  });

  it("returns terminal_noop for terminal workspace", async () => {
    const config = makeConfig();
    const notification = makeNotification({
      workspace_name: "billing-dev",
    });
    const result = await handleNotification(notification, config);
    expect(result.action).toBe("terminal_noop");
  });

  it("returns ignored for unknown workspace pattern", async () => {
    const config = makeConfig({
      projectFactoryPattern: /^pf-(?<service>.+)$/,
      terminalPattern: /^term-(?<service>.+)-(?<env>.+)$/,
    });
    const notification = makeNotification({
      workspace_name: "unknown-workspace",
    });
    const result = await handleNotification(notification, config);
    expect(result.action).toBe("ignored");
    expect(result.details).toHaveProperty(
      "reason",
      "unknown_workspace_pattern",
    );
  });

  it("returns ignored when notifications array is empty", async () => {
    const config = makeConfig();
    const notification = makeNotification({
      notifications: [],
    });
    const result = await handleNotification(notification, config);
    expect(result.action).toBe("ignored");
    expect(result.details).toHaveProperty("reason", "no_notifications");
  });

  it("returns ignored when notifications is not an array", async () => {
    const config = makeConfig();
    const notification = makeNotification();
    // Force non-array value to test defensive validation
    (notification as Record<string, unknown>).notifications = "not-an-array";
    const result = await handleNotification(notification, config);
    expect(result.action).toBe("ignored");
    expect(result.details).toHaveProperty("reason", "no_notifications");
  });
});

describe("parseRunMessage (via handleNotification)", () => {
  it("throws when run_message is invalid and source is run_message only", async () => {
    const config = makeConfig({ metadataSource: "run_message" });
    const notification = makeNotification({ run_message: "not json" });
    await expect(
      handleNotification(notification, config),
    ).rejects.toThrow("run_message does not contain valid metadata JSON");
  });
});
