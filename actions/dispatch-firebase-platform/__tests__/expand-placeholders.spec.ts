import { describe, it, expect } from "vitest";
import { loadAndBuild, getVar } from "./helpers.js";

// ---------------------------------------------------------------------------
// 対象: expandFirebasePlatformPlaceholders を pipeline の中で通した時の
// fixture-based 検証 (Action 全体に対する integration test)。
//
// `${service}` / `${env}` placeholder が anchor merge 後の object でも、
// firebase_platform 配下の様々な field でも、正しく展開されることを確認する。
// 関数単体の test は `lib/dispatch/index.spec.ts` 側を参照。
// ---------------------------------------------------------------------------

describe("07-data-connect-env-prefix-anchor", () => {
  it("dev-001: ${service}-${env}-shared-fdc → graphql-svc-dev-001-shared-fdc に展開", async () => {
    const dev = await loadAndBuild(
      "07-data-connect-env-prefix-anchor.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );
    const dc = getVar(dev.vars, "data_connect");
    expect(dc).toContain('"instance_id" = "graphql-svc-dev-001-shared-fdc"');
    expect(dc).not.toContain("${service}");
    expect(dc).not.toContain("${env}");
    // dev は small tier override
    expect(dc).toContain('"tier" = "db-f1-micro"');
    expect(dc).not.toContain('"deletion_protection" = true');
  });

  it("prd-001: 同 template が prd-001 prefix で展開、env で異なる override が効く", async () => {
    const prd = await loadAndBuild(
      "07-data-connect-env-prefix-anchor.yml",
      "prd-001",
      "graphql-svc-prd-001",
    );
    const dc = getVar(prd.vars, "data_connect");
    expect(dc).toContain('"instance_id" = "graphql-svc-prd-001-shared-fdc"');
    expect(dc).not.toContain("dev-001");
    // prd は deletion_protection on
    expect(dc).toContain('"deletion_protection" = true');
    // tier override 無し → base の db-custom-2-4096
    expect(dc).toContain('"tier" = "db-custom-2-4096"');
    expect(dc).not.toContain('"tier" = "db-f1-micro"');
  });
});

describe("08-placeholder-all-fields", () => {
  it("apps[].display_name (cosmetic) で展開される", async () => {
    const { vars } = await loadAndBuild(
      "08-placeholder-all-fields.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );
    const apps = getVar(vars, "apps");
    expect(apps).toContain('"display_name" = "graphql-svc dev-001 Main"');
    expect(apps).toContain('"display_name" = "graphql-svc dev-001 Admin"');
  });

  it("hosting[].site_id (globally unique) で展開される", async () => {
    const { vars } = await loadAndBuild(
      "08-placeholder-all-fields.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );
    const hosting = getVar(vars, "hosting");
    expect(hosting).toContain('"site_id" = "graphql-svc-dev-001-web"');
    expect(hosting).toContain('"site_id" = "graphql-svc-dev-001-admin"');
  });

  it("app_hosting[].backend_id (project-unique) で展開される", async () => {
    const { vars } = await loadAndBuild(
      "08-placeholder-all-fields.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );
    const appHosting = getVar(vars, "app_hosting");
    expect(appHosting).toContain('"backend_id" = "graphql-svc-dev-001-api"');
  });

  it("storage.buckets[].name + firestore_backup.bucket_name で展開される", async () => {
    const { vars } = await loadAndBuild(
      "08-placeholder-all-fields.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );
    const storage = getVar(vars, "storage");
    // auto_prefix=true の方は base name のまま (実 bucket 名は TF 側で {project}- を被せる)
    expect(storage).toContain('"name" = "uploads"');
    expect(storage).toContain('"auto_prefix" = true');
    // ${service}/${env} 展開で globally unique を作るパターン
    expect(storage).toContain('"name" = "graphql-svc-dev-001-cdn-assets"');
    expect(storage).toContain(
      '"bucket_name" = "graphql-svc-dev-001-firestore-backup"',
    );
  });

  it("firestore[].database_id で展開される ('(default)' は固定文字列のまま)", async () => {
    const { vars } = await loadAndBuild(
      "08-placeholder-all-fields.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );
    const firestore = getVar(vars, "firestore");
    expect(firestore).toContain('"database_id" = "(default)"');
    expect(firestore).toContain('"database_id" = "dev-001-analytics"');
  });

  it("data_connect[].cloud_sql の各 field で展開される", async () => {
    const { vars } = await loadAndBuild(
      "08-placeholder-all-fields.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );
    const dc = getVar(vars, "data_connect");
    expect(dc).toContain('"instance_id" = "graphql-svc-dev-001-shared-fdc"');
    expect(dc).toContain('"database" = "dev-001-main"');
  });

  it("全 var で placeholder 文字列が残らない (sanity)", async () => {
    const { vars } = await loadAndBuild(
      "08-placeholder-all-fields.yml",
      "dev-001",
      "graphql-svc-dev-001",
    );
    const allValues = vars.map((v) => v.value).join("\n");
    expect(allValues).not.toContain("${service}");
    expect(allValues).not.toContain("${env}");
  });
});
