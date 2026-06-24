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

  it("parses optional service-level folder_id", () => {
    const raw = `service: svc
folder_id: "123456789012"
environments:
  dev-001:
    billing_account_id: X
`;
    const settings = parseSettings(raw);
    expect(settings.folder_id).toBe("123456789012");
  });

  it("leaves folder_id undefined when omitted", () => {
    const raw = `service: svc
environments:
  dev-001:
    billing_account_id: X
`;
    const settings = parseSettings(raw);
    expect(settings.folder_id).toBeUndefined();
  });

  it("coerces an unquoted numeric folder_id to a string", () => {
    const raw = `service: svc
folder_id: 1054101088318
environments:
  dev-001:
    billing_account_id: X
`;
    const settings = parseSettings(raw);
    expect(settings.folder_id).toBe("1054101088318");
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

  // teardown (全 env 撤去): env を全コメントアウトすると `environments: null` に
  // なるが、これは意図的な空状態として {} に正規化し、destroy diff に乗せたい。
  it("normalizes a null environments map to {} (full teardown)", () => {
    const settings = parseSettings(
      "service: svc\nretained_envs:\n  - prd-001\nenvironments:\n",
    );
    expect(settings.environments).toEqual({});
    expect(settings.retained_envs).toEqual(["prd-001"]);
  });

  // 安全 floor: `environments:` キー自体の欠落は記述ミスの可能性が高いので
  // 空 teardown と区別して従来どおりエラーにする (null は可、undefined は不可)。
  it("throws when the environments key is entirely missing", () => {
    expect(() =>
      parseSettings("service: svc\nretained_envs:\n  - prd-001\n"),
    ).toThrow();
  });

  // teardown で project ごと削除したい env だけ deletion_policy: DELETE を opt-in。
  it("parses an explicit deletion_policy", () => {
    const settings = parseSettings(
      "service: svc\nenvironments:\n  dev-004:\n    billing_account_id: X\n    deletion_policy: DELETE\n",
    );
    expect(settings.environments["dev-004"].deletion_policy).toBe("DELETE");
  });

  // 既定は undefined (= 後段で安全側の PREVENT に倒す)。
  it("leaves deletion_policy undefined when omitted", () => {
    const settings = parseSettings(
      "service: svc\nenvironments:\n  dev-004:\n    billing_account_id: X\n",
    );
    expect(settings.environments["dev-004"].deletion_policy).toBeUndefined();
  });

  it("rejects a deletion_policy outside the enum", () => {
    expect(() =>
      parseSettings(
        "service: svc\nenvironments:\n  dev-004:\n    billing_account_id: X\n    deletion_policy: NUKE\n",
      ),
    ).toThrow();
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
