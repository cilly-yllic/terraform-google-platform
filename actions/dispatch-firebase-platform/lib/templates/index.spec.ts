import { describe, it, expect } from "vitest";
import { buildTemplateFiles } from "./index.js";

describe("buildTemplateFiles", () => {
  it("returns main.tf and versions.tf", () => {
    const files = buildTemplateFiles(undefined);
    expect(Object.keys(files).sort()).toEqual(["main.tf", "versions.tf"]);
  });

  it("references the firebase-project-platform module", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    expect(main).toContain(
      'source = "cilly-yllic/platform/google//modules/firebase-project-platform"',
    );
  });

  it("omits the version line when moduleVersion is undefined", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    expect(main).not.toMatch(/^\s*version\s*=/m);
  });

  it("pins the module version when moduleVersion is provided", () => {
    const { "main.tf": main } = buildTemplateFiles("1.2.3");
    expect(main).toMatch(/^\s*version = "1\.2\.3"$/m);
  });

  it("supports version range constraints", () => {
    const { "main.tf": main } = buildTemplateFiles("~> 1.0");
    expect(main).toMatch(/^\s*version = "~> 1\.0"$/m);
  });

  it("declares the google and google-beta providers in versions.tf", () => {
    const { "versions.tf": versions } = buildTemplateFiles(undefined);
    expect(versions).toContain('source  = "hashicorp/google"');
    expect(versions).toContain('source  = "hashicorp/google-beta"');
  });

  it("declares all 23 firebase_platform feature variables (18 single + 5 list)", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    const features = [
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
      // list features (multi-instance)
      "apps",
      "hosting",
      "app_hosting",
      "firestore",
      "data_connect",
    ];
    for (const k of features) {
      expect(main, `should declare variable ${k}`).toContain(
        `variable "${k}"`,
      );
    }
  });

  it("declares AND forwards non-feature passthrough variables (incl. app_hosting_compute_sa_roles)", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    // PASSTHROUGH_KEYS (dispatch/index.ts) に対応する root 変数。宣言だけでなく
    // module ブロックへの受け渡しまで無いと、tfvars に値があっても TFC が
    // "Value for undeclared variable" 警告を出して値を無視する。
    const passthrough = [
      "additional_apis",
      "users",
      "ci_service_account",
      "service_accounts",
      "app_hosting_compute_sa_roles",
      "default_compute_sa_roles",
    ];
    for (const k of passthrough) {
      expect(main, `should declare variable ${k}`).toContain(
        `variable "${k}"`,
      );
      // alignment 用の連続 space を許容するため regex で照合
      expect(main, `should forward ${k} to the module`).toMatch(
        new RegExp(`${k}\\s*=\\s*var\\.${k}\\b`),
      );
    }
  });
});
