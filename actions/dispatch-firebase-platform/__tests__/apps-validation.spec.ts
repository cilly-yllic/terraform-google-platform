import { describe, it, expect } from "vitest";
import {
  loadFirebasePlatform,
  buildTerraformVariables,
} from "./helpers.js";

// ---------------------------------------------------------------------------
// 対象: lib/dispatch/index.ts の validateAppEntry (apps[] の type / 必須 field
// 検証)。
//
// 各 error fixture は「特定 field を欠落させた settings.yml」を持ち、
// build 時点で正規表現マッチする error が throws されることを assert する。
// ---------------------------------------------------------------------------

describe("E01-apps-missing-type", () => {
  it("apps[].type 欠落 → throws", async () => {
    const fp = await loadFirebasePlatform(
      "errors/E01-apps-missing-type.yml",
      "prd-001",
    );
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /'type' must be one of "web" \| "ios" \| "android"/,
    );
  });
});

describe("E02-apps-ios-missing-bundle-id", () => {
  it("type=ios で bundle_id 欠落 → throws", async () => {
    const fp = await loadFirebasePlatform(
      "errors/E02-apps-ios-missing-bundle-id.yml",
      "prd-001",
    );
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /type="ios"\): 'bundle_id' is required/,
    );
  });
});

describe("E03-apps-android-missing-package-name", () => {
  it("type=android で package_name 欠落 → throws", async () => {
    const fp = await loadFirebasePlatform(
      "errors/E03-apps-android-missing-package-name.yml",
      "prd-001",
    );
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /type="android"\): 'package_name' is required/,
    );
  });
});
