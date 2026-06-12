import { describe, it, expect } from "vitest";
import { parseRunMessage } from "../src/tfc-client.js";

describe("parseRunMessage", () => {
  it("parses the hybrid shape (environments + labels)", () => {
    const result = parseRunMessage(
      '{"service":"svc","environments":["dev-001","dev-002"],"labels":["^tier:dev$"],"source_repo":"owner/repo","sha":"abc"}',
    );
    expect(result).toEqual({
      service: "svc",
      environments: ["dev-001", "dev-002"],
      labels: ["^tier:dev$"],
      source_repo: "owner/repo",
    });
  });

  it("defaults labels to [] when absent (forward compat)", () => {
    const result = parseRunMessage(
      '{"service":"svc","environments":["dev-001"],"source_repo":"o/r"}',
    );
    expect(result).toEqual({
      service: "svc",
      environments: ["dev-001"],
      labels: [],
      source_repo: "o/r",
    });
  });

  it("accepts an explicitly empty labels array", () => {
    const result = parseRunMessage(
      '{"service":"svc","environments":["prd-001"],"labels":[],"source_repo":"o/r"}',
    );
    expect(result?.labels).toEqual([]);
  });

  it("returns null for non-JSON string", () => {
    expect(parseRunMessage("hello world")).toBeNull();
  });

  it("returns null when required fields are missing", () => {
    expect(parseRunMessage('{"service":"svc"}')).toBeNull();
  });

  it("returns null when service is an empty string", () => {
    expect(
      parseRunMessage('{"service":"","environments":["dev-001"],"source_repo":"o/r"}'),
    ).toBeNull();
  });

  it("returns null when environments is missing", () => {
    expect(parseRunMessage('{"service":"svc","source_repo":"o/r"}')).toBeNull();
  });

  it("returns null when environments is an empty array", () => {
    expect(parseRunMessage('{"service":"svc","environments":[],"source_repo":"o/r"}')).toBeNull();
  });

  it("returns null when environments contains non-string entries", () => {
    expect(
      parseRunMessage('{"service":"svc","environments":["dev-001",42],"source_repo":"o/r"}'),
    ).toBeNull();
  });

  it("returns null when labels contains non-string entries", () => {
    expect(
      parseRunMessage(
        '{"service":"svc","environments":["dev-001"],"labels":[1],"source_repo":"o/r"}',
      ),
    ).toBeNull();
  });

  it("returns null for empty string", () => {
    expect(parseRunMessage("")).toBeNull();
  });

  it("returns null for the legacy singular env shape", () => {
    // Run messages emitted before PR #10 used `env: string`. Those are
    // intentionally rejected — Phase 2 was broken with the old shape anyway.
    expect(parseRunMessage('{"service":"svc","env":"dev-001","source_repo":"o/r"}')).toBeNull();
  });
});
