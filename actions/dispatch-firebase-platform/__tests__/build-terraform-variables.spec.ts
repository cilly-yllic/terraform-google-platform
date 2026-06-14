import { describe, it, expect } from "vitest";
import { loadAndBuild, getVar } from "./helpers.js";

// ---------------------------------------------------------------------------
// 対象: buildTerraformVariables の HCL output rendering
//
// 各 fixture は「list-feature の代表的なパターン」が正しく HCL 配列に展開
// されることを検証する。validation や placeholder 展開には触れない (それらは
// 別 spec に切り出してある)。
// ---------------------------------------------------------------------------

describe("01-minimal-web", () => {
  it("web app 1 件 + hosting 1 件で他 list は null になる", async () => {
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
    expect(getVar(vars, "app_hosting")).toBe("null");
    expect(getVar(vars, "firestore")).toBe("null");
    expect(getVar(vars, "data_connect")).toBe("null");
  });
});

describe("02-multi-app-multi-hosting", () => {
  it("複数 apps + 複数 hosting + 複数 app_hosting が array で並ぶ", async () => {
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
});

describe("03-multi-platform-apps", () => {
  it("type=web/ios/android の混在 + type 固有 field (bundle_id / package_name 等)", async () => {
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
    expect(apps).toContain('"sha1_hashes" = [');

    // hosting からは type=web の name (= "main") のみ参照可
    const hosting = getVar(vars, "hosting");
    expect(hosting).toContain('"app" = "main"');
  });
});

describe("04-multi-firestore", () => {
  it("複数 database + region 別 + protection / PITR の per-DB 設定", async () => {
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
    expect(fs).toContain(
      '"delete_protection_state" = "DELETE_PROTECTION_ENABLED"',
    );
    expect(fs).toContain('"point_in_time_recovery" = true');
  });
});

describe("05-data-connect-shared-instance", () => {
  it("共有 Cloud SQL Instance (Pattern Y) + 独立 Instance (Pattern X) の混在", async () => {
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
    // 共有モード: main / analytics は同じ instance_id "shared-fdc"
    expect(dc).toContain('"instance_id" = "shared-fdc"');
    expect(dc).toContain('"database" = "main"');
    expect(dc).toContain('"database" = "analytics"');
    // 独立モード: jobs は別 instance_id
    expect(dc).toContain('"instance_id" = "jobs-fdc"');
    expect(dc).toContain('"database" = "jobs"');
    // tier は instance 単位の properties
    expect(dc).toContain('"tier" = "db-custom-2-4096"');
    expect(dc).toContain('"tier" = "db-f1-micro"');
  });
});
