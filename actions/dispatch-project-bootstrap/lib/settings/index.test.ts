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

describe("extractEnvironment", () => {
  const settings = {
    service: "svc",
    environments: {
      "dev-001": { billing_account_id: "X" },
      "prd-001": { billing_account_id: "Y" },
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
