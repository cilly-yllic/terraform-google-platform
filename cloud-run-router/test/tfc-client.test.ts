import { describe, it, expect } from "vitest";
import { parseRunMessage } from "../src/tfc-client.js";

describe("parseRunMessage", () => {
  it("parses valid metadata JSON", () => {
    const result = parseRunMessage(
      '{"service":"svc","env":"dev","source_repo":"owner/repo"}',
    );
    expect(result).toEqual({
      service: "svc",
      env: "dev",
      source_repo: "owner/repo",
    });
  });

  it("returns null for non-JSON string", () => {
    expect(parseRunMessage("hello world")).toBeNull();
  });

  it("returns null when required fields are missing", () => {
    expect(parseRunMessage('{"service":"svc"}')).toBeNull();
  });

  it("returns null when fields are empty strings", () => {
    expect(
      parseRunMessage('{"service":"","env":"dev","source_repo":"o/r"}'),
    ).toBeNull();
  });

  it("returns null for empty string", () => {
    expect(parseRunMessage("")).toBeNull();
  });

  it("returns null for JSON with non-string values", () => {
    expect(
      parseRunMessage('{"service":123,"env":"dev","source_repo":"o/r"}'),
    ).toBeNull();
  });
});
