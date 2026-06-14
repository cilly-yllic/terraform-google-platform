import { describe, it, expect } from "vitest";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { buildTarball } from "./index";

function extract(tarball: Buffer): Record<string, string> {
  const dir = mkdtempSync(path.join(tmpdir(), "tarball-test-"));
  try {
    const tarPath = path.join(dir, "out.tar.gz");
    writeFileSync(tarPath, tarball);
    execFileSync("tar", ["-xzf", tarPath, "-C", dir]);
    const result: Record<string, string> = {};
    for (const f of readdirSync(dir)) {
      if (f === "out.tar.gz") continue;
      result[f] = readFileSync(path.join(dir, f), "utf-8");
    }
    return result;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe("buildTarball", () => {
  it("packs in-memory files at the root of a gzipped tar", () => {
    const tarball = buildTarball({
      "main.tf": 'module "x" {}\n',
      "versions.tf": "terraform {}\n",
    });
    expect(tarball[0]).toBe(0x1f);
    expect(tarball[1]).toBe(0x8b);

    const files = extract(tarball);
    expect(files["main.tf"]).toBe('module "x" {}\n');
    expect(files["versions.tf"]).toBe("terraform {}\n");
  });

  it("handles an empty file map", () => {
    const tarball = buildTarball({});
    expect(tarball.length).toBeGreaterThan(0);
    expect(extract(tarball)).toEqual({});
  });
});
