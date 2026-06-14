import { describe, it, expect } from "vitest";
import {
  loadFirebasePlatform,
  buildTerraformVariables,
} from "./helpers.js";

// ---------------------------------------------------------------------------
// 対象: lib/dispatch/index.ts の validateDataConnectEntry (data_connect[] の
// 必須 field / cloud_sql の必須 sub-field 検証)。
// ---------------------------------------------------------------------------

describe("E05-data-connect-missing-cloud-sql", () => {
  it("data_connect[].cloud_sql 欠落 → throws", async () => {
    const fp = await loadFirebasePlatform(
      "errors/E05-data-connect-missing-cloud-sql.yml",
      "prd-001",
    );
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /'cloud_sql' is required/,
    );
  });
});
