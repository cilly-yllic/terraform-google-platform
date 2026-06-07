import { describe, it, expect } from "vitest";
import {
  expandWorkspaceName,
  resolveAutoApply,
  buildTerraformVariables,
  buildEnvVariables,
  buildRunMessage,
} from "./index.js";

describe("expandWorkspaceName", () => {
  it("replaces {service} and {environment} placeholders", () => {
    expect(
      expandWorkspaceName("{service}-{environment}", {
        service: "svc",
        environment: "prd-001",
      }),
    ).toBe("svc-prd-001");
  });

  it("replaces all occurrences of the same placeholder", () => {
    expect(
      expandWorkspaceName("{service}-{service}", { service: "svc" }),
    ).toBe("svc-svc");
  });

  it("leaves unknown placeholders untouched", () => {
    expect(expandWorkspaceName("{unknown}", { service: "x" })).toBe(
      "{unknown}",
    );
  });
});

describe("resolveAutoApply", () => {
  it("returns true for 'auto'", () => {
    expect(resolveAutoApply("auto", "prd-001")).toBe(true);
  });

  it("returns false for 'manual'", () => {
    expect(resolveAutoApply("manual", "dev-001")).toBe(false);
  });

  it("env-based: true for env keys starting with 'dev'", () => {
    expect(resolveAutoApply("env-based", "dev")).toBe(true);
    expect(resolveAutoApply("env-based", "dev-001")).toBe(true);
    expect(resolveAutoApply("env-based", "dev-002")).toBe(true);
  });

  it("env-based: false for non-dev envs", () => {
    expect(resolveAutoApply("env-based", "stg-001")).toBe(false);
    expect(resolveAutoApply("env-based", "prd-001")).toBe(false);
  });

  it("throws for unknown policy", () => {
    expect(() => resolveAutoApply("nope", "dev-001")).toThrow(
      /Unknown apply_policy/,
    );
  });
});

describe("buildTerraformVariables", () => {
  it("always emits project_id as non-hcl terraform var", () => {
    const vars = buildTerraformVariables("my-svc-prd-001", {});
    const projectId = vars.find((v) => v.key === "project_id");
    expect(projectId).toMatchObject({
      key: "project_id",
      value: "my-svc-prd-001",
      category: "terraform",
      hcl: false,
      sensitive: false,
    });
  });

  it("emits all 22 feature keys even when firebase_platform is empty", () => {
    const vars = buildTerraformVariables("p", {});
    // 1 project_id + 22 feature keys = 23
    expect(vars).toHaveLength(23);
    const featureKeys = [
      "firebase",
      "authentication",
      "firestore",
      "rtdb",
      "storage",
      "hosting",
      "app_hosting",
      "data_connect",
      "fcm",
      "remote_config",
      "app_check",
      "crashlytics",
      "performance",
      "analytics",
      "extensions",
      "secret_manager",
      "cloud_tasks",
      "cloud_scheduler",
      "pubsub",
      "eventarc",
      "cloud_run",
      "cloud_functions",
    ];
    for (const k of featureKeys) {
      const v = vars.find((x) => x.key === k);
      expect(v?.value, `${k} should default to null`).toBe("null");
      expect(v?.hcl).toBe(true);
    }
  });

  it("normalizes feature flag values: true / 'true' / false / 'false' / null", () => {
    const vars = buildTerraformVariables("p", {
      firebase: true,
      authentication: "true",
      firestore: false,
      rtdb: "false",
      storage: null,
    });
    const byKey = Object.fromEntries(vars.map((v) => [v.key, v.value]));
    expect(byKey.firebase).toBe("true");
    expect(byKey.authentication).toBe("true");
    expect(byKey.firestore).toBe("null"); // false → null
    expect(byKey.rtdb).toBe("null"); // "false" → null
    expect(byKey.storage).toBe("null");
  });

  it("renders object feature values as HCL maps", () => {
    const vars = buildTerraformVariables("p", {
      firestore: { location: "asia-northeast1", type: "FIRESTORE_NATIVE" },
    });
    const fs = vars.find((v) => v.key === "firestore");
    expect(fs?.value).toBe(
      '{ "location" = "asia-northeast1", "type" = "FIRESTORE_NATIVE" }',
    );
  });

  it("renders nested arrays and objects in HCL", () => {
    const vars = buildTerraformVariables("p", {
      storage: { buckets: [{ name: "icons" }, { name: "uploads" }] },
    });
    const s = vars.find((v) => v.key === "storage");
    expect(s?.value).toBe(
      '{ "buckets" = [{ "name" = "icons" }, { "name" = "uploads" }] }',
    );
  });

  it("escapes Terraform interpolation in string values", () => {
    const vars = buildTerraformVariables("p", {
      hosting: { site_id: "use-${var.danger}" },
    });
    const h = vars.find((v) => v.key === "hosting");
    expect(h?.value).toContain('"use-$${var.danger}"');
  });

  it("throws when feature value is an array", () => {
    expect(() =>
      buildTerraformVariables("p", { firebase: ["nope"] }),
    ).toThrow(/expected null, boolean, or object but got array/);
  });

  it("throws when feature value is a number", () => {
    expect(() => buildTerraformVariables("p", { firebase: 42 })).toThrow(
      /got number/,
    );
  });

  it("emits passthrough keys only when present", () => {
    const without = buildTerraformVariables("p", {});
    expect(without.find((v) => v.key === "region")).toBeUndefined();
    expect(without.find((v) => v.key === "users")).toBeUndefined();

    const withPass = buildTerraformVariables("p", {
      region: "asia-northeast1",
      users: [{ email: "a@b" }],
      additional_apis: ["iap.googleapis.com"],
    });
    expect(withPass.find((v) => v.key === "region")?.value).toBe(
      '"asia-northeast1"',
    );
    expect(withPass.find((v) => v.key === "users")?.value).toBe(
      '[{ "email" = "a@b" }]',
    );
    expect(withPass.find((v) => v.key === "additional_apis")?.value).toBe(
      '["iap.googleapis.com"]',
    );
  });

  it("does NOT emit passthrough keys that are absent (vs null)", () => {
    // PASSTHROUGH_KEYS only emit when raw !== undefined.
    // Explicitly setting null DOES emit (raw becomes null, which is defined).
    const vars = buildTerraformVariables("p", { region: null });
    const r = vars.find((v) => v.key === "region");
    expect(r?.value).toBe("null");
  });
});

describe("buildEnvVariables", () => {
  it("returns 4 env-category variables in fixed order", () => {
    const vars = buildEnvVariables(
      "terraform-svc-dev-001@infra.iam.gserviceaccount.com",
      "svc-dev-001",
      "123456789012",
      "tfc-pool",
      "tfc-provider",
    );
    expect(vars.map((v) => v.key)).toEqual([
      "TFC_GCP_PROVIDER_AUTH",
      "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL",
      "TFC_GCP_WORKLOAD_PROVIDER_NAME",
      "GOOGLE_PROJECT",
    ]);
    expect(vars.every((v) => v.category === "env")).toBe(true);
    expect(vars.every((v) => v.sensitive === false)).toBe(true);
  });

  it("builds the WIF provider path from bootstrap project number / pool / provider", () => {
    const vars = buildEnvVariables("sa@x", "p", "999", "pool-x", "prov-x");
    const wif = vars.find((v) => v.key === "TFC_GCP_WORKLOAD_PROVIDER_NAME");
    expect(wif?.value).toBe(
      "projects/999/locations/global/workloadIdentityPools/pool-x/providers/prov-x",
    );
  });

  it("emits empty WIF path when bootstrap project number is empty", () => {
    const vars = buildEnvVariables("sa@x", "p", "", "pool", "prov");
    const wif = vars.find((v) => v.key === "TFC_GCP_WORKLOAD_PROVIDER_NAME");
    expect(wif?.value).toBe("");
  });
});

describe("buildRunMessage", () => {
  it("serializes the metadata as JSON", () => {
    const msg = buildRunMessage({
      service: "svc",
      environment: "dev-001",
      source_repo: "owner/repo",
      sha: "abc123",
    });
    expect(JSON.parse(msg)).toEqual({
      service: "svc",
      environment: "dev-001",
      source_repo: "owner/repo",
      sha: "abc123",
    });
  });
});
