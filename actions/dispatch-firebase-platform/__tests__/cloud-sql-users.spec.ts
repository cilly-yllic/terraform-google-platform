import { describe, it, expect } from "vitest";
import { loadAndBuild, loadFirebasePlatform, getVar } from "./helpers.js";
import {
  buildTerraformVariables,
  getAllowedCloudSqlRoles,
} from "../lib/dispatch/index.js";

// ---------------------------------------------------------------------------
// 対象: Cloud SQL users
//   - CLOUD_IAM_USER  … users[].cloud_sql (IAM 連動, role validation, instance 自動採用)
//   - BUILT_IN        … data_connect[].cloud_sql.users (password 注入, sensitive 化)
//   - cloud_sql_user_policy.allowed_roles による env 可変な role gating
// ---------------------------------------------------------------------------

describe("10-cloud-sql-users: CLOUD_IAM_USER (users[].cloud_sql)", () => {
  it("dev-001: editor + owner が cloud_sql access を宣言でき、HCL に出力される", async () => {
    const { vars } = await loadAndBuild(
      "10-cloud-sql-users.yml",
      "dev-001",
      "graphql-svc-dev-001",
      { externalSecrets: { CLOUD_SQL_PW_ADMIN: "s3cret" } },
    );
    const users = getVar(vars, "users");
    expect(users).toContain('"email" = "alice@corp.com"');
    expect(users).toContain('"email" = "dbowner@corp.com"');
    // cloud_sql サブフィールドが passthrough される
    expect(users).toContain("cloud_sql");
    expect(users).toContain('"instance_id" = "graphql-svc-dev-001-fdc"');
  });

  it("prd-001: owner + default policy([owner]) で通る", async () => {
    const { vars } = await loadAndBuild(
      "10-cloud-sql-users.yml",
      "prd-001",
      "graphql-svc-prd-001",
    );
    expect(getVar(vars, "users")).toContain('"email" = "dbowner@corp.com"');
  });
});

describe("10-cloud-sql-users: BUILT_IN password 注入 + sensitive", () => {
  it("cloud_sql_secrets で ${CLOUD_SQL_PW_ADMIN} が実値に置換される", async () => {
    const { vars } = await loadAndBuild(
      "10-cloud-sql-users.yml",
      "dev-001",
      "graphql-svc-dev-001",
      { externalSecrets: { CLOUD_SQL_PW_ADMIN: "s3cret-pw" } },
    );
    const dc = getVar(vars, "data_connect");
    expect(dc).toContain('"name" = "studio_admin"');
    expect(dc).toContain('"password" = "s3cret-pw"');
    expect(dc).not.toContain("${CLOUD_SQL_PW_ADMIN}");
  });

  it("BUILT_IN password を含む data_connect 変数は sensitive=true になる", async () => {
    const { vars } = await loadAndBuild(
      "10-cloud-sql-users.yml",
      "dev-001",
      "graphql-svc-dev-001",
      { externalSecrets: { CLOUD_SQL_PW_ADMIN: "s3cret-pw" } },
    );
    const dcVar = vars.find((v) => v.key === "data_connect");
    expect(dcVar?.sensitive).toBe(true);
  });

  it("BUILT_IN password が無い env の data_connect は sensitive=false のまま", async () => {
    const { vars } = await loadAndBuild(
      "10-cloud-sql-users.yml",
      "prd-001",
      "graphql-svc-prd-001",
    );
    const dcVar = vars.find((v) => v.key === "data_connect");
    expect(dcVar?.sensitive).toBe(false);
  });

  it("cloud_sql_secrets 未指定 → password の placeholder が未解決で fail-fast", async () => {
    await expect(
      loadAndBuild("10-cloud-sql-users.yml", "dev-001", "graphql-svc-dev-001"),
    ).rejects.toThrow(/unresolved placeholder/);
  });
});

describe("cloud_sql_user_policy.allowed_roles", () => {
  it("未指定なら default [owner]", () => {
    expect(getAllowedCloudSqlRoles({ firebase: true })).toEqual(["owner"]);
  });
  it("指定があればそれを採用 (env 可変)", () => {
    expect(
      getAllowedCloudSqlRoles({
        cloud_sql_user_policy: { allowed_roles: ["owner", "editor"] },
      }),
    ).toEqual(["owner", "editor"]);
  });
});

describe("cloud-sql-users validation errors", () => {
  it("E07: viewer が cloud_sql access → role not permitted", async () => {
    const fp = await loadFirebasePlatform(
      "errors/E07-cloud-sql-user-role-not-allowed.yml",
      "prd-001",
    );
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /role "viewer" is not permitted/,
    );
  });

  it("E08: users[].cloud_sql.password → not allowed here", async () => {
    const fp = await loadFirebasePlatform(
      "errors/E08-cloud-sql-user-password-in-users.yml",
      "prd-001",
    );
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /'cloud_sql.password' is not allowed here/,
    );
  });

  it("E09: users[].cloud_sql.instance_id が data_connect に無い → mismatch", async () => {
    const fp = await loadFirebasePlatform(
      "errors/E09-cloud-sql-user-bad-instance.yml",
      "prd-001",
    );
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /does not match any data_connect Cloud SQL instance/,
    );
  });
});
