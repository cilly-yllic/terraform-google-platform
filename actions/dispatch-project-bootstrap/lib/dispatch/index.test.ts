import { describe, it, expect } from "vitest";
import {
  expandWorkspaceName,
  buildRunMessage,
  mergeEnvironmentsMap,
} from "./index";

describe("expandWorkspaceName", () => {
  it("replaces {service} placeholders", () => {
    expect(expandWorkspaceName("project-factory-{service}", { service: "svc" }))
      .toBe("project-factory-svc");
  });

  it("replaces all occurrences globally", () => {
    expect(expandWorkspaceName("{service}-{service}", { service: "svc" })).toBe(
      "svc-svc",
    );
  });

  it("leaves unknown placeholders untouched", () => {
    expect(expandWorkspaceName("{foo}", { service: "svc" })).toBe("{foo}");
  });

  it("escapes special regex characters in the substituted value", () => {
    // value contains $ (regex special); must be inserted literally
    expect(
      expandWorkspaceName("{service}", { service: "svc-$1-end" }),
    ).toBe("svc-$1-end");
  });
});

describe("buildRunMessage", () => {
  it("serializes the metadata as JSON", () => {
    const msg = buildRunMessage({
      service: "svc",
      environment: "prd-001",
      source_repo: "o/r",
      sha: "deadbeef",
    });
    expect(JSON.parse(msg)).toEqual({
      service: "svc",
      environment: "prd-001",
      source_repo: "o/r",
      sha: "deadbeef",
    });
  });
});

describe("mergeEnvironmentsMap", () => {
  it("adds a new environment entry into an empty map", () => {
    const result = mergeEnvironmentsMap({}, "dev-001", { project_id: "p1" });
    expect(result).toEqual({ "dev-001": { project_id: "p1" } });
  });

  it("overrides an existing entry for the same env key", () => {
    const result = mergeEnvironmentsMap(
      { "dev-001": { project_id: "old" } },
      "dev-001",
      { project_id: "new" },
    );
    expect(result["dev-001"]).toEqual({ project_id: "new" });
  });

  it("preserves other env entries while updating one", () => {
    const result = mergeEnvironmentsMap(
      {
        "dev-001": { project_id: "p1" },
        "prd-001": { project_id: "pPrd" },
      },
      "dev-001",
      { project_id: "p1-updated" },
    );
    expect(result).toEqual({
      "dev-001": { project_id: "p1-updated" },
      "prd-001": { project_id: "pPrd" },
    });
  });
});
