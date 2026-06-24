import { describe, it, expect } from "vitest";
import {
  expandWorkspaceName,
  buildRunMessage,
  mergeEnvironmentsMap,
  parseLabelsInput,
  evaluateEnvironmentGate,
  selectTargetEnvs,
  computeEnvDiff,
  buildEnvEntry,
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
  it("serializes the metadata as JSON with environments + labels arrays", () => {
    const msg = buildRunMessage({
      service: "svc",
      environments: ["prd-001", "dev-002"],
      labels: ["^tier:prd$"],
      source_repo: "o/r",
      sha: "deadbeef",
      module_version: "1.2.3",
    });
    expect(JSON.parse(msg)).toEqual({
      service: "svc",
      environments: ["prd-001", "dev-002"],
      labels: ["^tier:prd$"],
      source_repo: "o/r",
      sha: "deadbeef",
      module_version: "1.2.3",
    });
  });

  it("handles an empty environments array (state-only / destroy diff)", () => {
    const msg = buildRunMessage({
      service: "svc",
      environments: [],
      labels: [],
      source_repo: "o/r",
      sha: "x",
      module_version: "1.2.3",
    });
    expect(JSON.parse(msg).environments).toEqual([]);
    expect(JSON.parse(msg).labels).toEqual([]);
  });

  it("carries labels even when only a single env was targeted by name", () => {
    const msg = buildRunMessage({
      service: "svc",
      environments: ["prd-001"],
      labels: [],
      source_repo: "o/r",
      sha: "x",
      module_version: "1.2.3",
    });
    expect(JSON.parse(msg)).toMatchObject({
      environments: ["prd-001"],
      labels: [],
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

describe("selectTargetEnvs", () => {
  const settings = {
    service: "svc",
    retained_envs: [] as string[],
    environments: {
      "prd-001": {
        status: "active" as const,
        labels: ["tier:prd", "region:apne1"],
        billing_account_id: "A",
      },
      "stg-001": {
        status: "inactive" as const,
        labels: ["tier:stg"],
        billing_account_id: "B",
      },
      "dev-001": {
        status: "active" as const,
        labels: ["tier:dev"],
        billing_account_id: "C",
      },
    },
  };

  it("picks just the named env when environmentInput is set and gate passes", () => {
    const r = selectTargetEnvs({
      settings,
      environmentInput: "prd-001",
      inputLabelPatterns: [],
    });
    expect(r.targets).toEqual(["prd-001"]);
    expect(r.filtered).toEqual([]);
  });

  it("filters the named env out via labels", () => {
    const r = selectTargetEnvs({
      settings,
      environmentInput: "prd-001",
      inputLabelPatterns: ["^tier:dev$"],
    });
    expect(r.targets).toEqual([]);
    expect(r.filtered).toHaveLength(1);
    expect(r.filtered[0].env).toBe("prd-001");
    expect(r.filtered[0].reason).toBe("labels_mismatch");
  });

  it("filters the named env out when status is inactive", () => {
    const r = selectTargetEnvs({
      settings,
      environmentInput: "stg-001",
      inputLabelPatterns: [],
    });
    expect(r.targets).toEqual([]);
    expect(r.filtered).toHaveLength(1);
    expect(r.filtered[0].reason).toBe("status_inactive");
  });

  it("throws with available keys when the named env does not exist", () => {
    expect(() =>
      selectTargetEnvs({
        settings,
        environmentInput: "missing",
        inputLabelPatterns: [],
      }),
    ).toThrow(/Available: prd-001, stg-001, dev-001/);
  });

  it("iterates all envs when environmentInput is empty and applies label filter", () => {
    const r = selectTargetEnvs({
      settings,
      environmentInput: "",
      inputLabelPatterns: ["^tier:dev$"],
    });
    expect(r.targets).toEqual(["dev-001"]);
    // prd-001: labels mismatch, stg-001: inactive
    expect(r.filtered.map((f) => f.env).sort()).toEqual(["prd-001", "stg-001"]);
  });

  it("iterates all active envs when no environmentInput and no labels", () => {
    // (input combo validation lives in the caller; this just tests behaviour.)
    const r = selectTargetEnvs({
      settings,
      environmentInput: "",
      inputLabelPatterns: [],
    });
    expect(r.targets.sort()).toEqual(["dev-001", "prd-001"]);
    expect(r.filtered.map((f) => f.env)).toEqual(["stg-001"]);
  });
});

describe("computeEnvDiff", () => {
  it("returns empty diff when prev keys are all present in settings", () => {
    expect(
      computeEnvDiff({
        prevKeys: ["a", "b"],
        settingsKeys: ["a", "b"],
        retainedKeys: [],
      }),
    ).toEqual({ stateRemoveKeys: [], destroyKeys: [] });
  });

  it("destroys envs removed from settings when not retained", () => {
    expect(
      computeEnvDiff({
        prevKeys: ["a", "b", "old-1"],
        settingsKeys: ["a", "b"],
        retainedKeys: [],
      }),
    ).toEqual({ stateRemoveKeys: [], destroyKeys: ["old-1"] });
  });

  it("state-removes envs that were removed from settings but listed in retained", () => {
    expect(
      computeEnvDiff({
        prevKeys: ["a", "b", "old-1"],
        settingsKeys: ["a", "b"],
        retainedKeys: ["old-1"],
      }),
    ).toEqual({ stateRemoveKeys: ["old-1"], destroyKeys: [] });
  });

  it("separates state-only from destroy when both occur", () => {
    expect(
      computeEnvDiff({
        prevKeys: ["a", "old-1", "old-2"],
        settingsKeys: ["a"],
        retainedKeys: ["old-1"],
      }),
    ).toEqual({ stateRemoveKeys: ["old-1"], destroyKeys: ["old-2"] });
  });

  it("ignores retained entries that are still in settings (safety net is dormant)", () => {
    expect(
      computeEnvDiff({
        prevKeys: ["a", "b"],
        settingsKeys: ["a", "b"],
        retainedKeys: ["a"],
      }),
    ).toEqual({ stateRemoveKeys: [], destroyKeys: [] });
  });

  it("ignores retained entries that were never in prev map", () => {
    expect(
      computeEnvDiff({
        prevKeys: [],
        settingsKeys: [],
        retainedKeys: ["a"],
      }),
    ).toEqual({ stateRemoveKeys: [], destroyKeys: [] });
  });
});

describe("buildEnvEntry", () => {
  const envConfig = {
    status: "active" as const,
    labels: [],
    billing_account_id: "AAAA",
  };

  it("builds project_id / sa id / workspace name from service + env", () => {
    expect(
      buildEnvEntry({ service: "svc", env: "prd-001", envConfig }),
    ).toEqual({
      project_id: "svc-prd-001",
      billing_account_id: "AAAA",
      terraform_service_account_id: "terraform-svc-prd-001",
      tfc_workspace_name: "svc-prd-001",
      deletion_policy: "PREVENT",
    });
  });

  it("defaults deletion_policy to PREVENT (safe floor) when omitted", () => {
    expect(
      buildEnvEntry({ service: "svc", env: "prd-001", envConfig }).deletion_policy,
    ).toBe("PREVENT");
  });

  it("passes through an explicit deletion_policy (e.g. DELETE for teardown)", () => {
    expect(
      buildEnvEntry({
        service: "svc",
        env: "dev-004",
        envConfig: { ...envConfig, deletion_policy: "DELETE" as const },
      }).deletion_policy,
    ).toBe("DELETE");
  });

  it("throws when terraform SA id would exceed 30 chars", () => {
    expect(() =>
      buildEnvEntry({
        service: "a-really-long-service-name",
        env: "prd-001",
        envConfig,
      }),
    ).toThrow(/GCP limit is 30/);
  });

  it("error message names the offending env", () => {
    expect(() =>
      buildEnvEntry({
        service: "long-service-name-here",
        env: "some-env",
        envConfig,
      }),
    ).toThrow(/env "some-env"/);
  });
});
