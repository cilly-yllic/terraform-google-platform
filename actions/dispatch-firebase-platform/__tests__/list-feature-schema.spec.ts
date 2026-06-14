import { describe, it, expect } from "vitest";
import {
  loadFirebasePlatform,
  buildTerraformVariables,
} from "./helpers.js";

// ---------------------------------------------------------------------------
// 対象: lib/dispatch/index.ts の normalizeListFeatureFlag (LIST_FEATURE_KEYS
// が array 以外の入力を reject すること)。
//
// rc5 以降 hosting / app_hosting / firestore / data_connect / apps は全て
// array 必須。旧 object 形式 (rc4 まで) を渡すと build 時点で reject される。
// ---------------------------------------------------------------------------

describe("E06-old-schema-hosting-object", () => {
  it("旧 object 形式 (rc4 まで) の hosting → throws", async () => {
    const fp = await loadFirebasePlatform(
      "errors/E06-old-schema-hosting-object.yml",
      "prd-001",
    );
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /expected null or array of objects but got object/,
    );
  });
});
