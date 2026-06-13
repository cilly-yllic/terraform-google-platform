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

  it("declares all 23 firebase_platform feature variables (20 single + 3 list)", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    const features = [
      "firebase",
      "authentication",
      "firestore",
      "rtdb",
      "storage",
      "data_connect",
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
    ];
    for (const k of features) {
      expect(main, `should declare variable ${k}`).toContain(
        `variable "${k}"`,
      );
    }
  });
});
