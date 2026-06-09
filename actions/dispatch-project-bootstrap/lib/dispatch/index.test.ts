import { describe, it, expect } from "vitest";
import {
  expandWorkspaceName,
  buildRunMessage,
  mergeEnvironmentsMap,
  parseLabelsInput,
  evaluateEnvironmentGate,
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

describe("parseLabelsInput", () => {
  it("returns [] for empty / whitespace-only input", () => {
    expect(parseLabelsInput("")).toEqual([]);
    expect(parseLabelsInput("   \n  \n")).toEqual([]);
  });

  it("parses a JSON array of strings", () => {
    expect(
      parseLabelsInput('["^tier:dev$", "^region:apne1$"]'),
    ).toEqual(["^tier:dev$", "^region:apne1$"]);
  });

  it("returns [] for a literal empty JSON array", () => {
    expect(parseLabelsInput("[]")).toEqual([]);
  });

  it("tolerates surrounding whitespace / multi-line JSON", () => {
    expect(
      parseLabelsInput('\n  [\n    "a",\n    "b"\n  ]\n'),
    ).toEqual(["a", "b"]);
  });

  it("throws on invalid JSON", () => {
    expect(() => parseLabelsInput("not json")).toThrow(
      /Invalid labels input/,
    );
  });

  it("throws when the JSON value is not an array", () => {
    expect(() => parseLabelsInput('"single string"')).toThrow(
      /expected a JSON array/,
    );
    expect(() => parseLabelsInput("{}")).toThrow(/expected a JSON array/);
  });

  it("throws when an array element is not a string", () => {
    expect(() => parseLabelsInput('["ok", 42]')).toThrow(
      /element \[1\] must be a string/,
    );
  });
});

describe("evaluateEnvironmentGate", () => {
  it("skips when status is inactive (no label check needed)", () => {
    const d = evaluateEnvironmentGate({
      status: "inactive",
      envLabels: ["tier:prd"],
      inputLabelPatterns: ["^tier:prd$"],
    });
    expect(d.skip).toBe(true);
    expect(d.reason).toBe("status_inactive");
  });

  it("runs when status is active and no input labels are given", () => {
    expect(
      evaluateEnvironmentGate({
        status: "active",
        envLabels: [],
        inputLabelPatterns: [],
      }),
    ).toEqual({ skip: false });
  });

  it("AND-matches every input pattern against env labels", () => {
    expect(
      evaluateEnvironmentGate({
        status: "active",
        envLabels: ["tier:prd", "region:apne1"],
        inputLabelPatterns: ["^tier:prd$", "^region:"],
      }),
    ).toEqual({ skip: false });
  });

  it("skips when any single input pattern fails to match", () => {
    const d = evaluateEnvironmentGate({
      status: "active",
      envLabels: ["tier:prd", "region:apne1"],
      inputLabelPatterns: ["^tier:prd$", "^owner:"],
    });
    expect(d.skip).toBe(true);
    expect(d.reason).toBe("labels_mismatch");
    expect(d.detail).toContain("^owner:");
  });

  it("regex test() is unanchored by default (partial match works)", () => {
    expect(
      evaluateEnvironmentGate({
        status: "active",
        envLabels: ["tier:prd-001"],
        inputLabelPatterns: ["tier:prd"],
      }),
    ).toEqual({ skip: false });
  });

  it("anchored patterns force exact match", () => {
    const d = evaluateEnvironmentGate({
      status: "active",
      envLabels: ["tier:prd-001"],
      inputLabelPatterns: ["^tier:prd$"],
    });
    expect(d.skip).toBe(true);
    expect(d.reason).toBe("labels_mismatch");
  });

  it("skips when env labels are empty but input patterns are given", () => {
    const d = evaluateEnvironmentGate({
      status: "active",
      envLabels: [],
      inputLabelPatterns: ["anything"],
    });
    expect(d.skip).toBe(true);
    expect(d.reason).toBe("labels_mismatch");
  });

  it("throws for invalid regex syntax in input", () => {
    expect(() =>
      evaluateEnvironmentGate({
        status: "active",
        envLabels: ["x"],
        inputLabelPatterns: ["[unclosed"],
      }),
    ).toThrow(/Invalid regex in labels input/);
  });
});
