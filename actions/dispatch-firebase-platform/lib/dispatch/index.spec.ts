import { describe, it, expect } from "vitest";
import {
  expandWorkspaceName,
  expandFirebasePlatformPlaceholders,
  resolveAutoApply,
  buildTerraformVariables,
  buildEnvVariables,
  buildRunMessage,
  parseLabelsInput,
  parseEnvironmentsInput,
  evaluateEnvironmentGate,
  selectTargetEnvs,
  buildMarkerTag,
  deriveEnvFromWorkspaceName,
} from "./index.js";

describe("expandFirebasePlatformPlaceholders", () => {
  const ctx = { service: "graphql-svc", env: "dev-001" };

  it("expands ${service} / ${env} in string values", () => {
    const out = expandFirebasePlatformPlaceholders(
      { foo: "${service}-${env}-fdc" },
      ctx,
    );
    expect(out.foo).toBe("graphql-svc-dev-001-fdc");
  });

  it("recurses into nested objects and arrays", () => {
    const out = expandFirebasePlatformPlaceholders(
      {
        data_connect: [
          {
            service_id: "main",
            cloud_sql: {
              instance_id: "${service}-${env}-shared-fdc",
              database: "main",
            },
          },
        ],
      },
      ctx,
    );
    expect(
      (out.data_connect as Array<{ cloud_sql: { instance_id: string } }>)[0]
        .cloud_sql.instance_id,
    ).toBe("graphql-svc-dev-001-shared-fdc");
  });

  it("leaves number / bool / null values untouched", () => {
    const out = expandFirebasePlatformPlaceholders(
      {
        firebase: true,
        version: 1,
        nothing: null,
        nested: { count: 42, flag: false },
      },
      ctx,
    );
    expect(out.firebase).toBe(true);
    expect(out.version).toBe(1);
    expect(out.nothing).toBeNull();
    expect((out.nested as Record<string, unknown>).count).toBe(42);
    expect((out.nested as Record<string, unknown>).flag).toBe(false);
  });

  it("leaves unknown placeholders untouched (passes through to HCL escape)", () => {
    const out = expandFirebasePlatformPlaceholders(
      { foo: "literal-${unknown}-text" },
      ctx,
    );
    expect(out.foo).toBe("literal-${unknown}-text");
  });

  it("does not mutate object keys (only values)", () => {
    const out = expandFirebasePlatformPlaceholders(
      { "${service}-key": "value" } as Record<string, unknown>,
      ctx,
    );
    expect(Object.keys(out as Record<string, unknown>)).toContain(
      "${service}-key",
    );
  });

  it("does not mutate the input object", () => {
    const input = { foo: "${service}" };
    const out = expandFirebasePlatformPlaceholders(input, ctx);
    expect(input.foo).toBe("${service}");
    expect(out.foo).toBe("graphql-svc");
  });

  // -------------------------------------------------------------------------
  // Per-field expansion tests
  //
  // 「この field に placeholder を書いて良い」ことを明示的に lock-in する。
  // 「placeholder が動くかどうかを覚えてなくて毎回 docs を見る」を防ぐ目的。
  // -------------------------------------------------------------------------

  it("expands in apps[].display_name (cosmetic)", () => {
    const out = expandFirebasePlatformPlaceholders(
      {
        apps: [
          { name: "main", type: "web", display_name: "${service} ${env} Main" },
        ],
      },
      ctx,
    );
    expect(
      (out.apps as Array<{ display_name: string }>)[0].display_name,
    ).toBe("graphql-svc dev-001 Main");
  });

  it("expands in hosting[].site_id (globally unique)", () => {
    const out = expandFirebasePlatformPlaceholders(
      { hosting: [{ site_id: "${service}-${env}-web", app: "main" }] },
      ctx,
    );
    expect((out.hosting as Array<{ site_id: string }>)[0].site_id).toBe(
      "graphql-svc-dev-001-web",
    );
  });

  it("expands in app_hosting[].backend_id (project-unique)", () => {
    const out = expandFirebasePlatformPlaceholders(
      {
        app_hosting: [
          {
            backend_id: "${service}-${env}-api",
            location: "asia-northeast1",
            app: "main",
          },
        ],
      },
      ctx,
    );
    expect(
      (out.app_hosting as Array<{ backend_id: string }>)[0].backend_id,
    ).toBe("graphql-svc-dev-001-api");
  });

  it("expands in storage.buckets[].name (globally unique なので ${service}/${env} 展開で衝突回避するパターン)", () => {
    const out = expandFirebasePlatformPlaceholders(
      {
        storage: {
          buckets: [{ name: "${service}-${env}-cdn-assets" }],
        },
      },
      ctx,
    );
    expect(
      (out.storage as { buckets: Array<{ name: string }> }).buckets[0].name,
    ).toBe("graphql-svc-dev-001-cdn-assets");
  });

  it("expands in storage.firestore_backup.bucket_name", () => {
    const out = expandFirebasePlatformPlaceholders(
      {
        storage: {
          firestore_backup: {
            bucket_name: "${service}-${env}-firestore-backup",
          },
        },
      },
      ctx,
    );
    expect(
      (out.storage as { firestore_backup: { bucket_name: string } })
        .firestore_backup.bucket_name,
    ).toBe("graphql-svc-dev-001-firestore-backup");
  });

  it("expands in firestore[].database_id (但し '(default)' は固定文字列なのでそのまま)", () => {
    const out = expandFirebasePlatformPlaceholders(
      {
        firestore: [
          { database_id: "(default)" },
          { database_id: "${env}-analytics" },
        ],
      },
      ctx,
    );
    const fs = out.firestore as Array<{ database_id: string }>;
    expect(fs[0].database_id).toBe("(default)");
    expect(fs[1].database_id).toBe("dev-001-analytics");
  });

  it("expands in data_connect[].service_id / cloud_sql.instance_id / cloud_sql.database", () => {
    const out = expandFirebasePlatformPlaceholders(
      {
        data_connect: [
          {
            service_id: "${env}-main",
            location: "asia-northeast1",
            cloud_sql: {
              instance_id: "${service}-${env}-shared-fdc",
              database: "${env}-main",
            },
          },
        ],
      },
      ctx,
    );
    const dc = out.data_connect as Array<{
      service_id: string;
      cloud_sql: { instance_id: string; database: string };
    }>;
    expect(dc[0].service_id).toBe("dev-001-main");
    expect(dc[0].cloud_sql.instance_id).toBe("graphql-svc-dev-001-shared-fdc");
    expect(dc[0].cloud_sql.database).toBe("dev-001-main");
  });

  it("expands within YAML <<: anchor merge result (Action 側で merge 後に走査するため)", () => {
    // YAML parser が <<: を merge し終わった後の object 構造を simulate する。
    // anchor を共有して env だけ override する典型パターンを per-field test として lock-in。
    const out = expandFirebasePlatformPlaceholders(
      {
        data_connect: [
          {
            service_id: "main",
            cloud_sql: {
              instance_id: "${service}-${env}-shared-fdc", // anchor 由来
              database: "main", // anchor 由来
              tier: "db-f1-micro", // env で override (dev は small)
            },
          },
        ],
      },
      ctx,
    );
    const cs = (
      out.data_connect as Array<{
        cloud_sql: { instance_id: string; database: string; tier: string };
      }>
    )[0].cloud_sql;
    expect(cs.instance_id).toBe("graphql-svc-dev-001-shared-fdc");
    expect(cs.database).toBe("main");
    expect(cs.tier).toBe("db-f1-micro");
  });

  // ---------------------------------------------------------------------------
  // ${BOOTSTRAP_PROJECT_NUMBER} (external 注入系) の per-function lock-in
  // ---------------------------------------------------------------------------

  it("expands ${BOOTSTRAP_PROJECT_NUMBER} when ctx.bootstrapProjectNumber is provided", () => {
    const out = expandFirebasePlatformPlaceholders(
      {
        ci_service_account: {
          wif: {
            pool_resource_name:
              "projects/${BOOTSTRAP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/terraform-cloud",
          },
        },
      },
      { ...ctx, bootstrapProjectNumber: "836996693576" },
    );
    expect(
      (
        out.ci_service_account as {
          wif: { pool_resource_name: string };
        }
      ).wif.pool_resource_name,
    ).toBe(
      "projects/836996693576/locations/global/workloadIdentityPools/terraform-cloud",
    );
  });

  it("throws when ${BOOTSTRAP_PROJECT_NUMBER} is referenced but bootstrapProjectNumber is undefined (fail-fast)", () => {
    expect(() =>
      expandFirebasePlatformPlaceholders(
        {
          ci_service_account: {
            wif: {
              pool_resource_name:
                "projects/${BOOTSTRAP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/x",
            },
          },
        },
        ctx, // bootstrapProjectNumber 未指定
      ),
    ).toThrow(/BOOTSTRAP_PROJECT_NUMBER/);
  });

  it("throws when ${BOOTSTRAP_PROJECT_NUMBER} is referenced but bootstrapProjectNumber is empty string (fail-fast)", () => {
    expect(() =>
      expandFirebasePlatformPlaceholders(
        { foo: "projects/${BOOTSTRAP_PROJECT_NUMBER}/locations/global/..." },
        { ...ctx, bootstrapProjectNumber: "" },
      ),
    ).toThrow(/BOOTSTRAP_PROJECT_NUMBER/);
  });

  it("does NOT throw when bootstrapProjectNumber is undefined but yml does not reference it (backward compat)", () => {
    // 旧 caller (= placeholder 未使用) が引き続き動くことを lock-in。
    const out = expandFirebasePlatformPlaceholders(
      { firebase: true, hosting: [{ site_id: "${service}-${env}-web" }] },
      ctx, // bootstrapProjectNumber 未指定
    );
    expect(
      (out.hosting as Array<{ site_id: string }>)[0].site_id,
    ).toBe("graphql-svc-dev-001-web");
  });
});

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

  it("emits all 23 feature keys (18 single + 5 list) even when firebase_platform is empty", () => {
    const vars = buildTerraformVariables("p", {});
    // 1 project_id + 18 single-feature keys + 5 list-feature keys = 24
    expect(vars).toHaveLength(24);
    const featureKeys = [
      "firebase",
      "authentication",
      "rtdb",
      "storage",
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
      // list features (multi-instance) — default null when omitted
      "apps",
      "hosting",
      "app_hosting",
      "firestore",
      "data_connect",
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
      rtdb: "false",
      storage: null,
    });
    const byKey = Object.fromEntries(vars.map((v) => [v.key, v.value]));
    expect(byKey.firebase).toBe("true");
    expect(byKey.authentication).toBe("true");
    expect(byKey.rtdb).toBe("null"); // "false" → null
    expect(byKey.storage).toBe("null");
  });

  it("renders object feature values as HCL maps", () => {
    const vars = buildTerraformVariables("p", {
      storage: { buckets: [{ name: "icons" }] },
    });
    const fs = vars.find((v) => v.key === "storage");
    expect(fs?.value).toBe(
      '{ "buckets" = [{ "name" = "icons" }] }',
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
      hosting: [{ site_id: "use-${var.danger}", app: "main" }],
    });
    const h = vars.find((v) => v.key === "hosting");
    expect(h?.value).toContain('"use-$${var.danger}"');
  });

  it("throws when single-feature value is an array", () => {
    expect(() =>
      buildTerraformVariables("p", { firebase: ["nope"] }),
    ).toThrow(/expected null, boolean, or object but got array/);
  });

  it("renders list-feature values (apps / hosting / app_hosting) as HCL arrays", () => {
    const vars = buildTerraformVariables("p", {
      apps: [
        { name: "main", type: "web" },
        { name: "admin", type: "web", display_name: "Admin" },
      ],
      hosting: [{ site_id: "mooodone-prod" }],
      app_hosting: [
        { backend_id: "api", location: "asia-northeast1", app: "main" },
      ],
    });
    const w = vars.find((v) => v.key === "apps");
    expect(w?.value).toBe(
      '[{ "name" = "main", "type" = "web" }, { "name" = "admin", "type" = "web", "display_name" = "Admin" }]',
    );
    const h = vars.find((v) => v.key === "hosting");
    expect(h?.value).toBe('[{ "site_id" = "mooodone-prod" }]');
    const a = vars.find((v) => v.key === "app_hosting");
    expect(a?.value).toBe(
      '[{ "backend_id" = "api", "location" = "asia-northeast1", "app" = "main" }]',
    );
  });

  it("throws when list-feature value is not an array", () => {
    expect(() =>
      buildTerraformVariables("p", {
        // ← 旧 schema の単数 object 形式は無効
        hosting: { site_id: "foo" },
      }),
    ).toThrow(/expected null or array of objects but got object/);
  });

  it("throws when list-feature array contains non-object items", () => {
    expect(() =>
      buildTerraformVariables("p", { apps: ["not-an-object"] }),
    ).toThrow(/at index 0: expected an object/);
  });

  it("throws when apps[].type is missing or invalid", () => {
    expect(() =>
      buildTerraformVariables("p", { apps: [{ name: "main" }] }),
    ).toThrow(/apps\[0\] \(name="main"\): 'type' must be one of/);
    expect(() =>
      buildTerraformVariables("p", { apps: [{ name: "main", type: "flutter" }] }),
    ).toThrow(/apps\[0\] \(name="main"\): 'type' must be one of/);
  });

  it("throws when apps[].name is missing", () => {
    expect(() =>
      buildTerraformVariables("p", { apps: [{ type: "web" }] }),
    ).toThrow(/apps\[0\]: 'name' is required/);
  });

  it("throws when type=ios but bundle_id is missing", () => {
    expect(() =>
      buildTerraformVariables("p", {
        apps: [{ name: "main-ios", type: "ios" }],
      }),
    ).toThrow(/apps\[0\] \(name="main-ios", type="ios"\): 'bundle_id' is required/);
  });

  it("throws when type=android but package_name is missing", () => {
    expect(() =>
      buildTerraformVariables("p", {
        apps: [{ name: "main-android", type: "android" }],
      }),
    ).toThrow(/apps\[0\] \(name="main-android", type="android"\): 'package_name' is required/);
  });

  it("accepts valid type=ios / type=android entries with required fields", () => {
    const vars = buildTerraformVariables("p", {
      apps: [
        { name: "main", type: "web" },
        { name: "main-ios", type: "ios", bundle_id: "com.example.app" },
        {
          name: "main-android",
          type: "android",
          package_name: "com.example.app",
        },
      ],
    });
    const a = vars.find((v) => v.key === "apps");
    expect(a?.value).toContain('"type" = "ios"');
    expect(a?.value).toContain('"bundle_id" = "com.example.app"');
    expect(a?.value).toContain('"type" = "android"');
    expect(a?.value).toContain('"package_name" = "com.example.app"');
  });

  it("throws when feature value is a number", () => {
    expect(() => buildTerraformVariables("p", { firebase: 42 })).toThrow(
      /got number/,
    );
  });

  it("validates firestore[].database_id required", () => {
    expect(() =>
      buildTerraformVariables("p", {
        firestore: [{ location: "asia-northeast1" }],
      }),
    ).toThrow(/firestore\[0\]: 'database_id' is required/);
  });

  it("validates firestore[].type allowed values", () => {
    expect(() =>
      buildTerraformVariables("p", {
        firestore: [{ database_id: "x", type: "BOGUS" }],
      }),
    ).toThrow(/firestore\[0\] \(database_id="x"\): 'type' must be/);
  });

  it("validates data_connect[].service_id + cloud_sql required", () => {
    expect(() =>
      buildTerraformVariables("p", {
        data_connect: [{ location: "asia-northeast1" }],
      }),
    ).toThrow(/data_connect\[0\]: 'service_id' is required/);
    expect(() =>
      buildTerraformVariables("p", {
        data_connect: [{ service_id: "main" }],
      }),
    ).toThrow(/data_connect\[0\] \(service_id="main"\): 'cloud_sql' is required/);
    expect(() =>
      buildTerraformVariables("p", {
        data_connect: [
          { service_id: "main", cloud_sql: { database: "main" } },
        ],
      }),
    ).toThrow(/'cloud_sql\.instance_id' is required/);
    expect(() =>
      buildTerraformVariables("p", {
        data_connect: [
          {
            service_id: "main",
            cloud_sql: { instance_id: "shared", database: "" },
          },
        ],
      }),
    ).toThrow(/'cloud_sql\.database' is required/);
  });

  it("accepts valid firestore + data_connect entries", () => {
    const vars = buildTerraformVariables("p", {
      firestore: [
        { database_id: "(default)", location: "asia-northeast1" },
        { database_id: "analytics", location: "us-central1", type: "FIRESTORE_NATIVE" },
      ],
      data_connect: [
        {
          service_id: "main",
          location: "asia-northeast1",
          cloud_sql: {
            instance_id: "shared-fdc",
            database: "main",
            tier: "db-f1-micro",
          },
        },
        {
          service_id: "analytics",
          cloud_sql: {
            instance_id: "shared-fdc",
            database: "analytics",
          },
        },
      ],
    });
    const fs = vars.find((v) => v.key === "firestore");
    expect(fs?.value).toContain('"database_id" = "(default)"');
    expect(fs?.value).toContain('"database_id" = "analytics"');
    const dc = vars.find((v) => v.key === "data_connect");
    expect(dc?.value).toContain('"service_id" = "main"');
    expect(dc?.value).toContain('"instance_id" = "shared-fdc"');
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
  it("serializes the metadata as JSON with environments + labels arrays", () => {
    const msg = buildRunMessage({
      service: "svc",
      environments: ["dev-001"],
      labels: ["^tier:dev$"],
      source_repo: "owner/repo",
      sha: "abc123",
    });
    expect(JSON.parse(msg)).toEqual({
      service: "svc",
      environments: ["dev-001"],
      labels: ["^tier:dev$"],
      source_repo: "owner/repo",
      sha: "abc123",
    });
  });

  it("supports multiple env keys with empty labels (single-env path)", () => {
    const msg = buildRunMessage({
      service: "svc",
      environments: ["dev-001"],
      labels: [],
      source_repo: "o/r",
      sha: "x",
    });
    expect(JSON.parse(msg)).toMatchObject({
      environments: ["dev-001"],
      labels: [],
    });
  });
});

describe("parseLabelsInput", () => {
  it("returns [] for empty / whitespace-only input", () => {
    expect(parseLabelsInput("")).toEqual([]);
    expect(parseLabelsInput("   \n  \n")).toEqual([]);
  });

  it("parses a JSON array of strings", () => {
    expect(
      parseLabelsInput('["^tier:dev$", "^region:apne1$"]'),
    ).toEqual(["^tier:dev$", "^region:apne1$"]);
  });

  it("returns [] for a literal empty JSON array", () => {
    expect(parseLabelsInput("[]")).toEqual([]);
  });

  it("tolerates surrounding whitespace / multi-line JSON", () => {
    expect(
      parseLabelsInput('\n  [\n    "a",\n    "b"\n  ]\n'),
    ).toEqual(["a", "b"]);
  });

  it("throws on invalid JSON", () => {
    expect(() => parseLabelsInput("not json")).toThrow(
      /Invalid labels input/,
    );
  });

  it("throws when the JSON value is not an array", () => {
    expect(() => parseLabelsInput('"single string"')).toThrow(
      /expected a JSON array/,
    );
    expect(() => parseLabelsInput("{}")).toThrow(/expected a JSON array/);
  });

  it("throws when an array element is not a string", () => {
    expect(() => parseLabelsInput('["ok", 42]')).toThrow(
      /element \[1\] must be a string/,
    );
  });
});

describe("evaluateEnvironmentGate", () => {
  it("skips when status is inactive (no label check needed)", () => {
    const d = evaluateEnvironmentGate({
      status: "inactive",
      envLabels: ["tier:prd"],
      inputLabelPatterns: ["^tier:prd$"],
    });
    expect(d.skip).toBe(true);
    expect(d.reason).toBe("status_inactive");
  });

  it("runs when status is active and no input labels are given", () => {
    expect(
      evaluateEnvironmentGate({
        status: "active",
        envLabels: [],
        inputLabelPatterns: [],
      }),
    ).toEqual({ skip: false });
  });

  it("AND-matches every input pattern against env labels", () => {
    expect(
      evaluateEnvironmentGate({
        status: "active",
        envLabels: ["tier:prd", "region:apne1"],
        inputLabelPatterns: ["^tier:prd$", "^region:"],
      }),
    ).toEqual({ skip: false });
  });

  it("skips when any single input pattern fails to match", () => {
    const d = evaluateEnvironmentGate({
      status: "active",
      envLabels: ["tier:prd", "region:apne1"],
      inputLabelPatterns: ["^tier:prd$", "^owner:"],
    });
    expect(d.skip).toBe(true);
    expect(d.reason).toBe("labels_mismatch");
    expect(d.detail).toContain("^owner:");
  });

  it("regex test() is unanchored by default (partial match works)", () => {
    expect(
      evaluateEnvironmentGate({
        status: "active",
        envLabels: ["tier:prd-001"],
        inputLabelPatterns: ["tier:prd"],
      }),
    ).toEqual({ skip: false });
  });

  it("anchored patterns force exact match", () => {
    const d = evaluateEnvironmentGate({
      status: "active",
      envLabels: ["tier:prd-001"],
      inputLabelPatterns: ["^tier:prd$"],
    });
    expect(d.skip).toBe(true);
    expect(d.reason).toBe("labels_mismatch");
  });

  it("skips when env labels are empty but input patterns are given", () => {
    const d = evaluateEnvironmentGate({
      status: "active",
      envLabels: [],
      inputLabelPatterns: ["anything"],
    });
    expect(d.skip).toBe(true);
    expect(d.reason).toBe("labels_mismatch");
  });

  it("throws for invalid regex syntax in input", () => {
    expect(() =>
      evaluateEnvironmentGate({
        status: "active",
        envLabels: ["x"],
        inputLabelPatterns: ["[unclosed"],
      }),
    ).toThrow(/Invalid regex in labels input/);
  });
});

describe("parseEnvironmentsInput", () => {
  it("returns [] for empty / whitespace-only input", () => {
    expect(parseEnvironmentsInput("")).toEqual([]);
    expect(parseEnvironmentsInput("   \n  \n")).toEqual([]);
  });

  it("parses a JSON array of env keys", () => {
    expect(parseEnvironmentsInput('["dev-001", "dev-002"]')).toEqual([
      "dev-001",
      "dev-002",
    ]);
  });

  it("returns [] for a literal empty JSON array", () => {
    expect(parseEnvironmentsInput("[]")).toEqual([]);
  });

  it("dedupes duplicate env keys while preserving first-seen order", () => {
    expect(
      parseEnvironmentsInput('["dev-001", "dev-002", "dev-001"]'),
    ).toEqual(["dev-001", "dev-002"]);
  });

  it("throws on invalid JSON", () => {
    expect(() => parseEnvironmentsInput("not json")).toThrow(
      /Invalid environments input/,
    );
  });

  it("throws when the JSON value is not an array", () => {
    expect(() => parseEnvironmentsInput('"single"')).toThrow(
      /expected a JSON array/,
    );
    expect(() => parseEnvironmentsInput("{}")).toThrow(/expected a JSON array/);
  });

  it("throws when an array element is not a string", () => {
    expect(() => parseEnvironmentsInput('["ok", 42]')).toThrow(
      /element \[1\] must be a string/,
    );
  });

  it("throws when an array element is an empty string", () => {
    expect(() => parseEnvironmentsInput('["dev-001", ""]')).toThrow(
      /element \[1\] is an empty string/,
    );
  });
});

describe("selectTargetEnvs", () => {
  const settings = {
    service: "svc",
    retained_envs: [] as string[],
    environments: {
      "prd-001": {
        status: "active" as const,
        labels: ["tier:prd", "region:apne1"],
        billing_account_id: "A",
      },
      "stg-001": {
        status: "inactive" as const,
        labels: ["tier:stg"],
        billing_account_id: "B",
      },
      "dev-001": {
        status: "active" as const,
        labels: ["tier:dev"],
        billing_account_id: "C",
      },
    },
  };

  it("picks the single named env when environmentsInput=[env] and gate passes", () => {
    const r = selectTargetEnvs({
      settings,
      environmentsInput: ["prd-001"],
      inputLabelPatterns: [],
    });
    expect(r.targets).toEqual(["prd-001"]);
    expect(r.filtered).toEqual([]);
  });

  it("picks multiple envs in order when given an array", () => {
    const r = selectTargetEnvs({
      settings,
      environmentsInput: ["prd-001", "dev-001"],
      inputLabelPatterns: [],
    });
    expect(r.targets).toEqual(["prd-001", "dev-001"]);
    expect(r.filtered).toEqual([]);
  });

  it("filters one of the named envs via labels mismatch", () => {
    const r = selectTargetEnvs({
      settings,
      environmentsInput: ["prd-001", "dev-001"],
      inputLabelPatterns: ["^tier:dev$"],
    });
    expect(r.targets).toEqual(["dev-001"]);
    expect(r.filtered).toHaveLength(1);
    expect(r.filtered[0].env).toBe("prd-001");
    expect(r.filtered[0].reason).toBe("labels_mismatch");
  });

  it("filters when one of the named envs has status: inactive", () => {
    const r = selectTargetEnvs({
      settings,
      environmentsInput: ["stg-001", "dev-001"],
      inputLabelPatterns: [],
    });
    expect(r.targets).toEqual(["dev-001"]);
    expect(r.filtered).toHaveLength(1);
    expect(r.filtered[0].env).toBe("stg-001");
    expect(r.filtered[0].reason).toBe("status_inactive");
  });

  it("throws when ANY named env is missing from settings", () => {
    expect(() =>
      selectTargetEnvs({
        settings,
        environmentsInput: ["prd-001", "missing-001"],
        inputLabelPatterns: [],
      }),
    ).toThrow(/Environments not found in settings\.yml: missing-001/);
  });

  it("error message lists every missing env and the available set", () => {
    expect(() =>
      selectTargetEnvs({
        settings,
        environmentsInput: ["missing-a", "missing-b"],
        inputLabelPatterns: [],
      }),
    ).toThrow(/missing-a, missing-b.+Available: prd-001, stg-001, dev-001/s);
  });

  it("iterates all envs and applies labels when environmentsInput is empty", () => {
    const r = selectTargetEnvs({
      settings,
      environmentsInput: [],
      inputLabelPatterns: ["^tier:dev$"],
    });
    expect(r.targets).toEqual(["dev-001"]);
    expect(r.filtered.map((f) => f.env).sort()).toEqual(["prd-001", "stg-001"]);
  });

  it("iterates all active envs when no input filters at all", () => {
    const r = selectTargetEnvs({
      settings,
      environmentsInput: [],
      inputLabelPatterns: [],
    });
    expect(r.targets.sort()).toEqual(["dev-001", "prd-001"]);
    expect(r.filtered.map((f) => f.env)).toEqual(["stg-001"]);
  });
});

describe("buildMarkerTag", () => {
  it("encodes the service into a tag string", () => {
    expect(buildMarkerTag("my-svc")).toBe("firebase-platform-my-svc");
  });
});

describe("deriveEnvFromWorkspaceName", () => {
  it("extracts env from default {service}-{environment} pattern", () => {
    expect(
      deriveEnvFromWorkspaceName("svc-dev-001", "{service}-{environment}", "svc"),
    ).toBe("dev-001");
  });

  it("extracts env when service contains hyphens", () => {
    expect(
      deriveEnvFromWorkspaceName(
        "my-svc-prd-001",
        "{service}-{environment}",
        "my-svc",
      ),
    ).toBe("prd-001");
  });

  it("returns null when name doesn't match the pattern prefix", () => {
    expect(
      deriveEnvFromWorkspaceName(
        "other-prd-001",
        "{service}-{environment}",
        "svc",
      ),
    ).toBeNull();
  });

  it("handles patterns with a suffix segment", () => {
    expect(
      deriveEnvFromWorkspaceName(
        "svc-prd-001-fb",
        "{service}-{environment}-fb",
        "svc",
      ),
    ).toBe("prd-001");
  });

  it("returns null when pattern lacks the {environment} placeholder", () => {
    expect(
      deriveEnvFromWorkspaceName("svc-anything", "{service}-static", "svc"),
    ).toBeNull();
  });
});
