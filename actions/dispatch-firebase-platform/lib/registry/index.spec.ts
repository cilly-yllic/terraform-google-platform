import { describe, it, expect } from "vitest";
import {
  compareSemver,
  pickLatestSemver,
  resolveModuleVersion,
} from "./index.js";

describe("compareSemver", () => {
  it("compares main version numerically per segment", () => {
    expect(compareSemver("1.10.0", "1.2.0")).toBeGreaterThan(0);
    expect(compareSemver("2.0.0", "1.99.0")).toBeGreaterThan(0);
    expect(compareSemver("1.0.0", "1.0.0")).toBe(0);
  });

  it("treats no-pre-release as greater than pre-release", () => {
    expect(compareSemver("1.0.0", "1.0.0-rc1")).toBeGreaterThan(0);
    expect(compareSemver("1.0.0-rc1", "1.0.0")).toBeLessThan(0);
  });

  it("orders rcN pre-releases naturally", () => {
    expect(compareSemver("0.0.0-rc14", "0.0.0-rc2")).toBeGreaterThan(0);
    expect(compareSemver("0.0.0-rc2", "0.0.0-rc14")).toBeLessThan(0);
    expect(compareSemver("0.0.0-rc15", "0.0.0-rc14")).toBeGreaterThan(0);
  });

  it("strips leading v", () => {
    expect(compareSemver("v1.0.0", "1.0.0")).toBe(0);
    expect(compareSemver("v0.0.0-rc15", "0.0.0-rc14")).toBeGreaterThan(0);
  });

  it("handles pure numeric identifiers per SemVer (lower than alphanumeric)", () => {
    expect(compareSemver("1.0.0-1", "1.0.0-alpha")).toBeLessThan(0);
  });
});

describe("pickLatestSemver", () => {
  it("returns latest from rc-only list", () => {
    const versions = [
      "0.0.0-rc1",
      "0.0.0-rc10",
      "0.0.0-rc11",
      "0.0.0-rc2",
      "0.0.0-rc9",
    ];
    expect(pickLatestSemver(versions)).toBe("0.0.0-rc11");
  });

  it("prefers stable over pre-release when both exist", () => {
    const versions = ["1.0.0-rc1", "1.0.0", "0.9.0"];
    expect(pickLatestSemver(versions)).toBe("1.0.0");
  });
});

describe("resolveModuleVersion", () => {
  it("returns explicit value when provided", async () => {
    const fakeFetch = async () => {
      throw new Error("fetch must not be called when explicit is provided");
    };
    const v = await resolveModuleVersion("0.0.0-rc7", fakeFetch as never);
    expect(v).toBe("0.0.0-rc7");
  });

  it("trims explicit value", async () => {
    const fakeFetch = async () => {
      throw new Error("fetch must not be called");
    };
    const v = await resolveModuleVersion("  0.0.0-rc7  ", fakeFetch as never);
    expect(v).toBe("0.0.0-rc7");
  });

  it("auto-resolves from registry when explicit is empty", async () => {
    const fakeFetch = (async () =>
      new Response(
        JSON.stringify({
          modules: [
            {
              versions: [
                { version: "0.0.0-rc14" },
                { version: "0.0.0-rc2" },
                { version: "0.0.0-rc15" },
              ],
            },
          ],
        }),
        { status: 200 },
      )) as typeof fetch;
    const v = await resolveModuleVersion("", fakeFetch);
    expect(v).toBe("0.0.0-rc15");
  });

  it("throws when registry returns non-OK", async () => {
    const fakeFetch = (async () =>
      new Response("oops", { status: 503 })) as typeof fetch;
    await expect(resolveModuleVersion(undefined, fakeFetch)).rejects.toThrow(
      /Terraform Registry/,
    );
  });

  it("throws when no versions are published", async () => {
    const fakeFetch = (async () =>
      new Response(JSON.stringify({ modules: [{ versions: [] }] }), {
        status: 200,
      })) as typeof fetch;
    await expect(resolveModuleVersion(undefined, fakeFetch)).rejects.toThrow(
      /No platform module versions/,
    );
  });
});
