import { describe, it, expect } from "vitest";
import { buildTemplateFiles } from "./index";

describe("buildTemplateFiles", () => {
  it("returns main.tf and versions.tf", () => {
    const files = buildTemplateFiles();
    expect(Object.keys(files).sort()).toEqual(["main.tf", "versions.tf"]);
  });

  it("references the project-bootstrap module", () => {
    const { "main.tf": main } = buildTemplateFiles();
    expect(main).toContain(
      'source = "cilly-yllic/platform/google//modules/project-bootstrap"',
    );
  });

  it("omits the version line when moduleVersion is undefined", () => {
    const { "main.tf": main } = buildTemplateFiles();
    expect(main).not.toMatch(/^\s*version\s*=/m);
  });

  it("pins the module version when moduleVersion is provided", () => {
    const { "main.tf": main } = buildTemplateFiles({ moduleVersion: "1.2.3" });
    expect(main).toMatch(/^\s*version = "1\.2\.3"$/m);
  });

  it("uses for_each over jsondecode(var.environments)", () => {
    const { "main.tf": main } = buildTemplateFiles();
    expect(main).toContain("for_each = jsondecode(var.environments)");
  });

  it("declares the variables consumed by the wrapper", () => {
    const { "main.tf": main } = buildTemplateFiles();
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
    const { "main.tf": main } = buildTemplateFiles();
    expect(main).toContain("each.value.project_id");
    expect(main).toContain("each.value.billing_account_id");
    expect(main).toContain("each.value.terraform_service_account_id");
    expect(main).toContain("each.value.tfc_workspace_name");
  });

  it("declares the google provider in versions.tf", () => {
    const { "versions.tf": versions } = buildTemplateFiles();
    expect(versions).toContain('source  = "hashicorp/google"');
  });

  it("requires Terraform >= 1.7 (needed for removed blocks)", () => {
    const { "versions.tf": versions } = buildTemplateFiles();
    expect(versions).toMatch(/required_version\s*=\s*">=\s*1\.7"/);
  });

  it("emits no removed blocks when stateRemoveKeys is empty / omitted", () => {
    const { "main.tf": main } = buildTemplateFiles({ stateRemoveKeys: [] });
    expect(main).not.toContain("removed {");
  });

  it("emits one removed block per state-remove key with destroy = false", () => {
    const { "main.tf": main } = buildTemplateFiles({
      stateRemoveKeys: ["old-001", "archived-002"],
    });
    expect(main).toContain('module.project_factory["old-001"]');
    expect(main).toContain('module.project_factory["archived-002"]');
    // both blocks must opt out of destroy
    const destroyFalseCount = (main.match(/destroy\s*=\s*false/g) ?? []).length;
    expect(destroyFalseCount).toBe(2);
  });

  it("placeholder is replaced even when no stateRemoveKeys is given", () => {
    const { "main.tf": main } = buildTemplateFiles();
    expect(main).not.toContain("##MODULE_VERSION_LINE##");
  });
});
