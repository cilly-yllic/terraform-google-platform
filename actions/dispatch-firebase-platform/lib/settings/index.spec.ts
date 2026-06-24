import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import {
  loadSettings,
  extractEnvironment,
  extractFirebasePlatform,
} from "./index.js";

let dir: string;

beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), "settings-test-"));
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

function write(yml: string): string {
  const p = path.join(dir, "settings.yml");
  writeFileSync(p, yml);
  return p;
}

describe("loadSettings", () => {
  it("parses a minimal valid settings.yml", async () => {
    const p = write(
      `service: svc\nenvironments:\n  dev-001:\n    billing_account_id: AAAA-AAAA-AAAA\n`,
    );
    const settings = await loadSettings(p);
    expect(settings.service).toBe("svc");
    expect(Object.keys(settings.environments)).toEqual(["dev-001"]);
    expect(settings.environments["dev-001"].billing_account_id).toBe(
      "AAAA-AAAA-AAAA",
    );
  });

  it("accepts firebase_platform as record<string, unknown>", async () => {
    const p = write(`
service: svc
environments:
  prd-001:
    billing_account_id: X
    firebase_platform:
      firebase: true
      firestore:
        location: asia-northeast1
`);
    const settings = await loadSettings(p);
    const fp = settings.environments["prd-001"].firebase_platform!;
    expect(fp.firebase).toBe(true);
    expect((fp.firestore as Record<string, unknown>).location).toBe(
      "asia-northeast1",
    );
  });

  it("expands YAML merge keys (<<:)", async () => {
    const p = write(`
service: svc
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
`);
    const settings = await loadSettings(p);
    const fp = settings.environments["dev-001"].firebase_platform!;
    expect(fp.firebase).toBe(true);
    expect(fp.region).toBe("us-central1"); // override wins
  });

  it("strips unknown top-level keys without error", async () => {
    const p = write(`
service: svc
unknown_top: ignored
environments:
  dev-001:
    billing_account_id: X
`);
    const settings = await loadSettings(p);
    expect((settings as Record<string, unknown>).unknown_top).toBeUndefined();
  });

  it("throws when service is missing", async () => {
    const p = write(`environments:\n  dev-001:\n    billing_account_id: X\n`);
    await expect(loadSettings(p)).rejects.toThrow();
  });

  it("throws when billing_account_id is missing", async () => {
    const p = write(
      `service: svc\nenvironments:\n  dev-001:\n    firebase_platform: {}\n`,
    );
    await expect(loadSettings(p)).rejects.toThrow();
  });

  it("throws when the file does not exist", async () => {
    await expect(loadSettings(path.join(dir, "missing.yml"))).rejects.toThrow();
  });

  // teardown (全 env 撤去) シナリオ: env を全コメントアウトすると
  // `environments: null` になるが、これは意図的な空状態として {} に正規化し、
  // reconciliation (orphan workspace 削除) に乗せたい。
  it("normalizes a null environments map to {} (full teardown)", async () => {
    const p = write(`service: svc\nretained_envs:\n  - prd-001\nenvironments:\n`);
    const settings = await loadSettings(p);
    expect(settings.environments).toEqual({});
    expect(settings.retained_envs).toEqual(["prd-001"]);
  });

  // 安全 floor: `environments:` キー自体の欠落は記述ミスの可能性が高いので
  // 空 teardown と区別して従来どおりエラーにする (null は可、undefined は不可)。
  it("throws when the environments key is entirely missing", async () => {
    const p = write(`service: svc\nretained_envs:\n  - prd-001\n`);
    await expect(loadSettings(p)).rejects.toThrow();
  });
});

describe("status / labels defaults", () => {
  it("defaults status to 'active' and labels to [] when omitted", async () => {
    const p = write(
      `service: svc\nenvironments:\n  dev-001:\n    billing_account_id: X\n`,
    );
    const settings = await loadSettings(p);
    expect(settings.environments["dev-001"].status).toBe("active");
    expect(settings.environments["dev-001"].labels).toEqual([]);
  });

  it("accepts status: inactive", async () => {
    const p = write(`
service: svc
environments:
  prd-001:
    status: inactive
    billing_account_id: X
`);
    const settings = await loadSettings(p);
    expect(settings.environments["prd-001"].status).toBe("inactive");
  });

  it("accepts labels as a string array", async () => {
    const p = write(`
service: svc
environments:
  dev-001:
    labels: ["tier:dev", "region:apne1"]
    billing_account_id: X
`);
    const settings = await loadSettings(p);
    expect(settings.environments["dev-001"].labels).toEqual([
      "tier:dev",
      "region:apne1",
    ]);
  });

  it("rejects status values outside the enum", async () => {
    const p = write(`
service: svc
environments:
  dev-001:
    status: paused
    billing_account_id: X
`);
    await expect(loadSettings(p)).rejects.toThrow();
  });

  it("rejects non-string label entries", async () => {
    const p = write(`
service: svc
environments:
  dev-001:
    labels: [1, 2]
    billing_account_id: X
`);
    await expect(loadSettings(p)).rejects.toThrow();
  });
});

describe("retained_envs", () => {
  it("defaults to [] when omitted", async () => {
    const p = write(
      `service: svc\nenvironments:\n  dev-001:\n    billing_account_id: X\n`,
    );
    const settings = await loadSettings(p);
    expect(settings.retained_envs).toEqual([]);
  });

  it("accepts a string array", async () => {
    const p = write(`service: svc
retained_envs:
  - prd-001
  - stg-001
environments:
  prd-001:
    billing_account_id: X
`);
    const settings = await loadSettings(p);
    expect(settings.retained_envs).toEqual(["prd-001", "stg-001"]);
  });

  it("rejects non-string entries", async () => {
    const p = write(`service: svc
retained_envs: [1, 2]
environments:
  dev-001:
    billing_account_id: X
`);
    await expect(loadSettings(p)).rejects.toThrow();
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
    expect(extractEnvironment(settings, "dev-001").billing_account_id).toBe(
      "X",
    );
  });

  it("throws with available env keys listed when missing", () => {
    expect(() => extractEnvironment(settings, "stg-001")).toThrow(
      /Available: dev-001, prd-001/,
    );
  });

  it("reports (none) when environments map is empty", () => {
    expect(() =>
      extractEnvironment(
        { service: "svc", retained_envs: [], environments: {} },
        "dev-001",
      ),
    ).toThrow(/Available: \(none\)/);
  });
});

describe("extractFirebasePlatform", () => {
  it("returns the firebase_platform object", () => {
    const settings = {
      service: "svc",
      retained_envs: [] as string[],
      environments: {
        "dev-001": {
          status: "active" as const,
          labels: [],
          billing_account_id: "X",
          firebase_platform: { firebase: true },
        },
      },
    };
    expect(extractFirebasePlatform(settings, "dev-001")).toEqual({
      firebase: true,
    });
  });

  it("throws when firebase_platform is missing", () => {
    const settings = {
      service: "svc",
      retained_envs: [] as string[],
      environments: {
        "dev-001": {
          status: "active" as const,
          labels: [],
          billing_account_id: "X",
        },
      },
    };
    expect(() => extractFirebasePlatform(settings, "dev-001")).toThrow(
      /firebase_platform section not found/,
    );
  });
});
