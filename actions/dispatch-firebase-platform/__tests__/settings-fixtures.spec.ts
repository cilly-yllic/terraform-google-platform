import { describe, it, expect } from "vitest";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  loadSettings,
  extractFirebasePlatform,
} from "../lib/settings/index.js";
import {
  buildTerraformVariables,
  expandFirebasePlatformPlaceholders,
} from "../lib/dispatch/index.js";

// ---------------------------------------------------------------------------
// fixture-based integration tests
//
// 目的: settings.yml を実際に読み込んで loadSettings → extractFirebasePlatform →
// buildTerraformVariables までの pipeline が想定通りの HCL を出すことを assert する。
//
// fixtures 配置:
//   tests/fixtures/settings/NN-pattern-name.yml       ← happy-path
//   tests/fixtures/settings/errors/EXX-error-name.yml ← 異常系
// ---------------------------------------------------------------------------

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES_DIR = resolve(__dirname, "fixtures/settings");

/**
 * Helper: fixture を読んで project_id 指定で variables 配列まで build する。
 */
const loadAndBuild = async (
  fixture: string,
  env: string,
  projectId: string,
) => {
  const settings = await loadSettings(`${FIXTURES_DIR}/${fixture}`);
  const raw = extractFirebasePlatform(settings, env);
  // 実 src/index.ts と同じ pipeline: placeholder 展開 → HCL build。
  const fp = expandFirebasePlatformPlaceholders(raw, {
    service: settings.service,
    env,
  });
  return {
    settings,
    fp,
    vars: buildTerraformVariables(projectId, fp),
  };
};

const getVar = (
  vars: Array<{ key: string; value: string }>,
  key: string,
): string | undefined => vars.find((v) => v.key === key)?.value;

// ---------------------------------------------------------------------------
// Happy-path fixtures
// ---------------------------------------------------------------------------

describe("settings.yml fixtures — happy path", () => {
  it("01-minimal-web: web app 1 件 + hosting 1 件", async () => {
    const { settings, fp, vars } = await loadAndBuild(
      "01-minimal-web.yml",
      "prd-001",
      "minimal-svc-prd-001",
    );

    expect(settings.service).toBe("minimal-svc");
    expect(fp.firebase).toBe(true);

    expect(getVar(vars, "project_id")).toBe("minimal-svc-prd-001");
    expect(getVar(vars, "apps")).toBe(
      '[{ "name" = "main", "type" = "web" }]',
    );
    expect(getVar(vars, "hosting")).toBe(
      '[{ "site_id" = "minimal-svc-prd-001-web" }]',
    );
    // 他の list features は空
    expect(getVar(vars, "app_hosting")).toBe("null");
    expect(getVar(vars, "firestore")).toBe("null");
    expect(getVar(vars, "data_connect")).toBe("null");
  });

  it("02-multi-app-multi-hosting: 多 web_app + 多 hosting + 多 app_hosting", async () => {
    const { vars } = await loadAndBuild(
      "02-multi-app-multi-hosting.yml",
      "prd-001",
      "multi-svc-prd-001",
    );

    const apps = getVar(vars, "apps");
    expect(apps).toContain('"name" = "main"');
    expect(apps).toContain('"name" = "admin"');
    expect(apps).toContain('"display_name" = "Main Web App"');
    expect(apps).toContain('"display_name" = "Admin Console"');

    const hosting = getVar(vars, "hosting");
    expect(hosting).toContain('"site_id" = "multi-svc-prd-001-web"');
    expect(hosting).toContain('"site_id" = "multi-svc-prd-001-admin"');
    expect(hosting).toContain('"app" = "main"');
    expect(hosting).toContain('"app" = "admin"');

    const appHosting = getVar(vars, "app_hosting");
    expect(appHosting).toContain('"backend_id" = "api"');
    expect(appHosting).toContain('"backend_id" = "admin-api"');
  });

  it("03-multi-platform-apps: web + iOS + Android の混在", async () => {
    const { vars } = await loadAndBuild(
      "03-multi-platform-apps.yml",
      "prd-001",
      "cross-platform-svc-prd-001",
    );

    const apps = getVar(vars, "apps");
    expect(apps).toContain('"type" = "web"');
    expect(apps).toContain('"type" = "ios"');
    expect(apps).toContain('"type" = "android"');
    expect(apps).toContain('"bundle_id" = "com.example.main"');
    expect(apps).toContain('"package_name" = "com.example.main"');
    expect(apps).toContain('"app_store_id" = "123456789"');
    expect(apps).toContain('"team_id" = "ABCDE12345"');
    // sha1_hashes はリスト形式で expand される
    expect(apps).toContain('"sha1_hashes" = [');

    // hosting は web type の main を参照
    const hosting = getVar(vars, "hosting");
    expect(hosting).toContain('"app" = "main"');
  });

  it("04-multi-firestore: 複数 database + region 別 + protection 設定", async () => {
    const { vars } = await loadAndBuild(
      "04-multi-firestore.yml",
      "prd-001",
      "data-svc-prd-001",
    );

    const fs = getVar(vars, "firestore");
    expect(fs).toContain('"database_id" = "(default)"');
    expect(fs).toContain('"database_id" = "analytics"');
    expect(fs).toContain('"database_id" = "logs"');
    expect(fs).toContain('"location" = "asia-northeast1"');
    expect(fs).toContain('"location" = "us-central1"');
    expect(fs).toContain('"delete_protection_state" = "DELETE_PROTECTION_ENABLED"');
    expect(fs).toContain('"point_in_time_recovery" = true');
  });

  it("05-data-connect-shared-instance: 共有 Cloud SQL Instance + 独立 Instance のミックス", async () => {
    const { vars } = await loadAndBuild(
      "05-data-connect-shared-instance.yml",
      "prd-001",
      "graphql-svc-prd-001",
    );

    const dc = getVar(vars, "data_connect");
    // 3 つの service が出力される
    expect(dc).toContain('"service_id" = "main"');
    expect(dc).toContain('"service_id" = "analytics"');
    expect(dc).toContain('"service_id" = "jobs"');
    // 共有モード: main / analytics は同じ instance_id "shared-fdc" を指す
    expect(dc).toContain('"instance_id" = "shared-fdc"');
    expect(dc).toContain('"database" = "main"');
    expect(dc).toContain('"database" = "analytics"');
    // 独立モード: jobs は別 instance_id
    expect(dc).toContain('"instance_id" = "jobs-fdc"');
    expect(dc).toContain('"database" = "jobs"');
    // tier は共有 instance の最初の entry にだけ書く形 (canonical)
    expect(dc).toContain('"tier" = "db-custom-2-4096"');
    expect(dc).toContain('"tier" = "db-f1-micro"');
  });

  it("06-yaml-anchor-shared-config: YAML anchor で env 間 config 共有 + override", async () => {
    // dev-001: そのまま anchor 使用
    const dev001 = await loadAndBuild(
      "06-yaml-anchor-shared-config.yml",
      "dev-001",
      "anchored-svc-dev-001",
    );
    expect(dev001.fp.firebase).toBe(true);
    expect(dev001.fp.authentication).toBe(true);
    expect(getVar(dev001.vars, "apps")).toContain('"name" = "main"');
    // anchor の firestore は (default) at asia-northeast1
    expect(getVar(dev001.vars, "firestore")).toContain(
      '"location" = "asia-northeast1"',
    );

    // dev-002: <<: *anchor で merge してから firestore だけ override
    const dev002 = await loadAndBuild(
      "06-yaml-anchor-shared-config.yml",
      "dev-002",
      "anchored-svc-dev-002",
    );
    expect(dev002.fp.firebase).toBe(true); // anchor から継承
    expect(dev002.fp.authentication).toBe(true); // anchor から継承
    // firestore は override → us-central1 に変わっている
    const dev002Fs = getVar(dev002.vars, "firestore");
    expect(dev002Fs).toContain('"location" = "us-central1"');
    expect(dev002Fs).not.toContain('"location" = "asia-northeast1"');
  });

  it("07-data-connect-env-prefix-anchor: ${service}/${env} placeholder で instance_id を env-prefix 分離", async () => {
    // dev-001: ${service}-${env}-shared-fdc → graphql-svc-dev-001-shared-fdc に展開
    const dev = await loadAndBuild(
      "07-data-connect-env-prefix-anchor.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );
    const devDc = getVar(dev.vars, "data_connect");
    expect(devDc).toContain('"instance_id" = "graphql-svc-dev-001-shared-fdc"');
    expect(devDc).not.toContain("${service}");
    expect(devDc).not.toContain("${env}");
    // dev は small tier override
    expect(devDc).toContain('"tier" = "db-f1-micro"');
    expect(devDc).not.toContain('"deletion_protection" = true');

    // prd-001: 同じ template が prd-001 prefix で展開
    const prd = await loadAndBuild(
      "07-data-connect-env-prefix-anchor.yml",
      "prd-001",
      "graphql-svc-prd-001",
    );
    const prdDc = getVar(prd.vars, "data_connect");
    expect(prdDc).toContain('"instance_id" = "graphql-svc-prd-001-shared-fdc"');
    expect(prdDc).not.toContain("dev-001");
    // prd は deletion_protection on
    expect(prdDc).toContain('"deletion_protection" = true');
    // tier override 無し → base の db-custom-2-4096
    expect(prdDc).toContain('"tier" = "db-custom-2-4096"');
    expect(prdDc).not.toContain('"tier" = "db-f1-micro"');
  });

  it("08-placeholder-all-fields: ${service}/${env} を主要 field 全体で展開", async () => {
    const { vars } = await loadAndBuild(
      "08-placeholder-all-fields.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );

    // apps[].display_name (cosmetic)
    const apps = getVar(vars, "apps");
    expect(apps).toContain('"display_name" = "graphql-svc dev-001 Main"');
    expect(apps).toContain('"display_name" = "graphql-svc dev-001 Admin"');

    // hosting[].site_id (globally unique なので env / service prefix が事実上必須)
    const hosting = getVar(vars, "hosting");
    expect(hosting).toContain('"site_id" = "graphql-svc-dev-001-web"');
    expect(hosting).toContain('"site_id" = "graphql-svc-dev-001-admin"');

    // app_hosting[].backend_id (project-unique)
    const appHosting = getVar(vars, "app_hosting");
    expect(appHosting).toContain('"backend_id" = "graphql-svc-dev-001-api"');

    // storage.buckets[].name (raw_name=true で env を含むパターン)
    const storage = getVar(vars, "storage");
    expect(storage).toContain('"name" = "uploads"'); // raw_name=false はそのまま
    expect(storage).toContain('"name" = "graphql-svc-dev-001-cdn-assets"');
    expect(storage).toContain(
      '"bucket_name" = "graphql-svc-dev-001-firestore-backup"',
    );

    // firestore[].database_id ("(default)" はそのまま、別 DB は env-prefix)
    const firestore = getVar(vars, "firestore");
    expect(firestore).toContain('"database_id" = "(default)"');
    expect(firestore).toContain('"database_id" = "dev-001-analytics"');

    // data_connect[].cloud_sql の各 field
    const dc = getVar(vars, "data_connect");
    expect(dc).toContain('"instance_id" = "graphql-svc-dev-001-shared-fdc"');
    expect(dc).toContain('"database" = "dev-001-main"');

    // 全 var で placeholder が残っていないことの sanity check
    const allValues = vars.map((v) => v.value).join("\n");
    expect(allValues).not.toContain("${service}");
    expect(allValues).not.toContain("${env}");
  });
});

// ---------------------------------------------------------------------------
// Error fixtures — validation が plan-time で error を吐くか
// ---------------------------------------------------------------------------

describe("settings.yml fixtures — error patterns", () => {
  it("E01-apps-missing-type: apps[].type 欠落 → throws", async () => {
    const settings = await loadSettings(
      `${FIXTURES_DIR}/errors/E01-apps-missing-type.yml`,
    );
    const fp = extractFirebasePlatform(settings, "prd-001");
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /'type' must be one of "web" \| "ios" \| "android"/,
    );
  });

  it("E02-apps-ios-missing-bundle-id: type=ios で bundle_id 欠落 → throws", async () => {
    const settings = await loadSettings(
      `${FIXTURES_DIR}/errors/E02-apps-ios-missing-bundle-id.yml`,
    );
    const fp = extractFirebasePlatform(settings, "prd-001");
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /type="ios"\): 'bundle_id' is required/,
    );
  });

  it("E03-apps-android-missing-package-name: type=android で package_name 欠落 → throws", async () => {
    const settings = await loadSettings(
      `${FIXTURES_DIR}/errors/E03-apps-android-missing-package-name.yml`,
    );
    const fp = extractFirebasePlatform(settings, "prd-001");
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /type="android"\): 'package_name' is required/,
    );
  });

  it("E04-firestore-missing-database-id: firestore[].database_id 欠落 → throws", async () => {
    const settings = await loadSettings(
      `${FIXTURES_DIR}/errors/E04-firestore-missing-database-id.yml`,
    );
    const fp = extractFirebasePlatform(settings, "prd-001");
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /firestore\[0\]: 'database_id' is required/,
    );
  });

  it("E05-data-connect-missing-cloud-sql: data_connect[].cloud_sql 欠落 → throws", async () => {
    const settings = await loadSettings(
      `${FIXTURES_DIR}/errors/E05-data-connect-missing-cloud-sql.yml`,
    );
    const fp = extractFirebasePlatform(settings, "prd-001");
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /'cloud_sql' is required/,
    );
  });

  it("E06-old-schema-hosting-object: 旧 object 形式の hosting → throws", async () => {
    const settings = await loadSettings(
      `${FIXTURES_DIR}/errors/E06-old-schema-hosting-object.yml`,
    );
    const fp = extractFirebasePlatform(settings, "prd-001");
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /expected null or array of objects but got object/,
    );
  });
});
