import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import {
  buildMarkerTag,
  buildTerraformVariables,
  COMPUTE_HOST_KEYS,
  expandComputeHostPlaceholders,
  findForeignMarker,
  selectTargetEnvs,
  WORKSPACE_NAME_PATTERN,
} from "../lib/dispatch/index.js";
import { extractComputeHost, loadSettings } from "../lib/settings/index.js";
import { buildTemplateFiles } from "../lib/templates/index.js";

const fixture = fileURLToPath(
  new URL("./fixtures/settings.yml", import.meta.url),
);

describe("settings.yml の compute_host", () => {
  it("YAML の << で共有した設定を env ごとに読み、${env} を展開する", async () => {
    const settings = await loadSettings(fixture);
    const config = expandComputeHostPlaceholders(
      extractComputeHost(settings, "dev-001"),
      {
        service: settings.service,
        env: "dev-001",
      },
    );
    expect(
      (config["network"] as { subnets: Array<{ name: string }> }).subnets[0]
        .name,
    ).toBe("vm-dev-001");
    expect(extractComputeHost(settings, "prd-001")["apis"]).toEqual([
      "artifactregistry.googleapis.com",
    ]);
  });

  it("compute_host が無い env は止める", async () => {
    const settings = await loadSettings(fixture);
    delete settings.environments["dev-001"].compute_host;
    expect(() => extractComputeHost(settings, "dev-001")).toThrow(
      /compute_host section not found/,
    );
  });

  it("inactive の env は対象から外す（dispatch-firebase-platform と同じ選び方）", async () => {
    const settings = await loadSettings(fixture);
    const { targets, filtered } = selectTargetEnvs({
      settings,
      environmentsInput: ["dev-001", "prd-001"],
      inputLabelPatterns: [],
    });
    expect(targets).toEqual(["dev-001"]);
    expect(filtered.map((f) => f.env)).toEqual(["prd-001"]);
  });
});

describe("buildTerraformVariables", () => {
  it("書いたキーだけを変数にし、string 以外は HCL にする", async () => {
    const settings = await loadSettings(fixture);
    const config = expandComputeHostPlaceholders(
      extractComputeHost(settings, "dev-001"),
      {
        service: settings.service,
        env: "dev-001",
      },
    );
    const vars = buildTerraformVariables("example-host-dev-001", config);
    expect(vars.map((v) => v.key)).toEqual([
      "project_id",
      "region",
      "network",
      "firewall_rules",
      "cloud_nat",
      "service_accounts",
      "custom_roles",
      "iam_bindings",
    ]);
    expect(vars.find((v) => v.key === "project_id")).toMatchObject({
      value: "example-host-dev-001",
      hcl: false,
    });
    expect(vars.find((v) => v.key === "region")).toMatchObject({
      value: "asia-northeast1",
      hcl: false,
    });
    const bindings = vars.find((v) => v.key === "iam_bindings");
    expect(bindings?.hcl).toBe(true);
    expect(bindings?.value).toContain(
      '"members" = { "manager" = "serviceAccount:manager@other-project.iam.gserviceaccount.com" }',
    );
    // 文字列の ${ はエスケープする（terraform の補間にしない）
    expect(
      buildTerraformVariables("p", { apis: ["${unknown}"] }).find(
        (v) => v.key === "apis",
      )?.value,
    ).toBe('["$${unknown}"]');
  });

  it("null のキーは送らない（既定値に任せる）", () => {
    expect(
      buildTerraformVariables("p", { network: null }).map((v) => v.key),
    ).toEqual(["project_id"]);
  });

  it("知らないキーは止める（typo で設定が捨てられないように）", () => {
    expect(() => buildTerraformVariables("p", { firewal_rules: [] })).toThrow(
      /Unknown compute_host key\(s\): firewal_rules/,
    );
  });

  it.each([
    ["region", 1],
    ["apis", "compute.googleapis.com"],
    ["apis", [1]],
    ["network", []],
    ["firewall_rules", {}],
    ["cloud_nat", "nat"],
  ])("%s の形が違えば止める", (key, value) => {
    expect(() => buildTerraformVariables("p", { [key]: value })).toThrow(
      new RegExp(`compute_host.${key} must be`),
    );
  });

  it("受け付けるキーは、モジュールの variables.tf の変数から project_id を除いたもの", () => {
    const variablesTf = readFileSync(
      fileURLToPath(
        new URL(
          "../../../modules/compute-host-platform/variables.tf",
          import.meta.url,
        ),
      ),
      "utf-8",
    );
    const moduleVars = [...variablesTf.matchAll(/^variable "([a-z_]+)"/gm)].map(
      (m) => m[1],
    );
    expect(Object.keys(COMPUTE_HOST_KEYS).sort()).toEqual(
      moduleVars.filter((name) => name !== "project_id").sort(),
    );
  });
});

describe("placeholder", () => {
  it("${BOOTSTRAP_PROJECT_NUMBER} を使っていて input が空なら止める", () => {
    expect(() =>
      expandComputeHostPlaceholders(
        {
          iam_bindings: [
            {
              members: {
                ci: "principalSet://iam.googleapis.com/projects/${BOOTSTRAP_PROJECT_NUMBER}/x",
              },
            },
          ],
        },
        { service: "s", env: "dev-001" },
      ),
    ).toThrow(/bootstrap_project_number/);
    expect(
      expandComputeHostPlaceholders(
        { apis: ["${service}-${env}-${BOOTSTRAP_PROJECT_NUMBER}"] },
        { service: "s", env: "dev-001", bootstrapProjectNumber: "123" },
      ),
    ).toEqual({ apis: ["s-dev-001-123"] });
  });
});

describe("templates と marker", () => {
  it("compute-host-platform を指し、版を書く", () => {
    const files = buildTemplateFiles("~> 2.1");
    expect(files["main.tf"]).toContain(
      'source = "cilly-yllic/platform/google//modules/compute-host-platform"',
    );
    expect(files["main.tf"]).toContain('version = "~> 2.1"');
    for (const key of Object.keys(COMPUTE_HOST_KEYS)) {
      expect(files["main.tf"]).toContain(`variable "${key}"`);
    }
  });

  it("marker tag は dispatch-firebase-platform と別の名前", () => {
    expect(buildMarkerTag("example-host")).toBe("compute-host-example-host");
  });

  it("workspace の名前は Action A の WIF の許可先と同じ形に固定", () => {
    expect(WORKSPACE_NAME_PATTERN).toBe("{service}-{environment}");
  });

  it("dispatch-firebase-platform の marker tag が付いた workspace を見分ける", () => {
    expect(
      findForeignMarker({
        "tag-names": ["compute-host-x", "firebase-platform-x"],
      }),
    ).toBe("firebase-platform-x");
    expect(findForeignMarker({ "tag-names": ["compute-host-x"] })).toBeNull();
    expect(findForeignMarker({ "tag-names": [] })).toBeNull();
    // 読めなければ判定できない（止める・消さない）
    expect(findForeignMarker({ "tag-names": "firebase-platform-x" })).toBe(
      "unknown",
    );
    expect(findForeignMarker(undefined)).toBe("unknown");
  });
});
