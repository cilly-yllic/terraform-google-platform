import { describe, it, expect } from "vitest";
import { buildTemplateFiles } from "./index";

describe("buildTemplateFiles", () => {
  it("returns main.tf and versions.tf", () => {
    const files = buildTemplateFiles(undefined);
    expect(Object.keys(files).sort()).toEqual(["main.tf", "versions.tf"]);
  });

  it("references the project-bootstrap module", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    expect(main).toContain('source = "cilly-yllic/project-bootstrap/google"');
  });

  it("omits the version line when moduleVersion is undefined", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    expect(main).not.toMatch(/^\s*version\s*=/m);
  });

  it("pins the module version when moduleVersion is provided", () => {
    const { "main.tf": main } = buildTemplateFiles("1.2.3");
    expect(main).toMatch(/^\s*version = "1\.2\.3"$/m);
  });

  it("uses for_each over jsondecode(var.environments)", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    expect(main).toContain("for_each = jsondecode(var.environments)");
  });

  it("declares the variables consumed by the wrapper", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    for (const v of [
      "service",
      "environments",
      "parent",
      "bootstrap_project_id",
      "workload_identity_pool_id",
      "workload_identity_provider_id",
    ]) {
      expect(main, `should declare variable ${v}`).toContain(
        `variable "${v}"`,
      );
    }
  });

  it("passes each.value.* attributes into the module", () => {
    const { "main.tf": main } = buildTemplateFiles(undefined);
    expect(main).toContain("each.value.project_id");
    expect(main).toContain("each.value.billing_account_id");
    expect(main).toContain("each.value.terraform_service_account_id");
    expect(main).toContain("each.value.tfc_workspace_name");
  });

  it("declares the google provider in versions.tf", () => {
    const { "versions.tf": versions } = buildTemplateFiles(undefined);
    expect(versions).toContain('source  = "hashicorp/google"');
  });
});
