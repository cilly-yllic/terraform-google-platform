import { describe, it, expect } from "vitest";
import { parseSettings, extractEnvironment } from "./index";

describe("parseSettings", () => {
  it("parses a minimal valid settings.yml", () => {
    const raw = `service: svc
environments:
  dev-001:
    billing_account_id: AAAA-AAAA-AAAA
`;
    const settings = parseSettings(raw);
    expect(settings.service).toBe("svc");
    expect(settings.environments["dev-001"].billing_account_id).toBe(
      "AAAA-AAAA-AAAA",
    );
  });

  it("accepts optional firebase_platform record", () => {
    const raw = `service: svc
environments:
  prd-001:
    billing_account_id: X
    firebase_platform:
      firebase: true
`;
    const settings = parseSettings(raw);
    expect(settings.environments["prd-001"].firebase_platform).toEqual({
      firebase: true,
    });
  });

  it("expands YAML merge keys (<<:)", () => {
    const raw = `service: svc
_anchors:
  base: &base
    firebase: true
    region: asia-northeast1
environments:
  dev-001:
    billing_account_id: B
    firebase_platform:
      <<: *base
      region: us-central1
`;
    const settings = parseSettings(raw);
    const fp = settings.environments["dev-001"].firebase_platform!;
    expect(fp.firebase).toBe(true);
    expect(fp.region).toBe("us-central1");
  });

  it("strips unknown keys silently (zod default)", () => {
    const raw = `service: svc
unknown_top: ignored
environments:
  dev-001:
    billing_account_id: X
    surprise_field: extra
`;
    const settings = parseSettings(raw);
    expect((settings as Record<string, unknown>).unknown_top).toBeUndefined();
    expect(
      (settings.environments["dev-001"] as Record<string, unknown>)
        .surprise_field,
    ).toBeUndefined();
  });

  it("throws when service is missing", () => {
    expect(() =>
      parseSettings("environments:\n  dev-001:\n    billing_account_id: X\n"),
    ).toThrow();
  });

  it("throws when billing_account_id is missing", () => {
    expect(() =>
      parseSettings("service: svc\nenvironments:\n  dev-001: {}\n"),
    ).toThrow();
  });

  it("throws when environments is not an object", () => {
    expect(() => parseSettings("service: svc\nenvironments: foo\n")).toThrow();
  });
});

describe("status / labels defaults", () => {
  it("defaults status to 'active' and labels to [] when omitted", () => {
    const settings = parseSettings(
      "service: svc\nenvironments:\n  dev-001:\n    billing_account_id: X\n",
    );
    expect(settings.environments["dev-001"].status).toBe("active");
    expect(settings.environments["dev-001"].labels).toEqual([]);
  });

  it("accepts status: inactive", () => {
    const settings = parseSettings(`service: svc
environments:
  prd-001:
    status: inactive
    billing_account_id: X
`);
    expect(settings.environments["prd-001"].status).toBe("inactive");
  });

  it("accepts labels as a string array", () => {
    const settings = parseSettings(`service: svc
environments:
  dev-001:
    labels: ["tier:dev", "region:apne1"]
    billing_account_id: X
`);
    expect(settings.environments["dev-001"].labels).toEqual([
      "tier:dev",
      "region:apne1",
    ]);
  });

  it("rejects status values outside the enum", () => {
    expect(() =>
      parseSettings(`service: svc
environments:
  dev-001:
    status: paused
    billing_account_id: X
`),
    ).toThrow();
  });

  it("rejects non-string label entries", () => {
    expect(() =>
      parseSettings(`service: svc
environments:
  dev-001:
    labels: [1, 2]
    billing_account_id: X
`),
    ).toThrow();
  });
});

describe("retained_envs", () => {
  it("defaults to [] when omitted", () => {
    const settings = parseSettings(
      "service: svc\nenvironments:\n  dev-001:\n    billing_account_id: X\n",
    );
    expect(settings.retained_envs).toEqual([]);
  });

  it("accepts a string array", () => {
    const settings = parseSettings(`service: svc
retained_envs:
  - prd-001
  - stg-001
environments:
  prd-001:
    billing_account_id: X
`);
    expect(settings.retained_envs).toEqual(["prd-001", "stg-001"]);
  });

  it("rejects non-string entries", () => {
    expect(() =>
      parseSettings(`service: svc
retained_envs: [1, 2]
environments:
  dev-001:
    billing_account_id: X
`),
    ).toThrow();
  });
});

describe("extractEnvironment", () => {
  const settings = {
    service: "svc",
    retained_envs: [] as string[],
    environments: {
      "dev-001": { status: "active" as const, labels: [], billing_account_id: "X" },
      "prd-001": { status: "active" as const, labels: [], billing_account_id: "Y" },
    },
  };

  it("returns the matching env entry", () => {
    expect(extractEnvironment(settings, "prd-001").billing_account_id).toBe(
      "Y",
    );
  });

  it("throws with available env keys listed when missing", () => {
    expect(() => extractEnvironment(settings, "stg-001")).toThrow(
      /Available: dev-001, prd-001/,
    );
  });
});
