import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";

/**
 * Build a gzipped tar archive from a set of in-memory files. Files are placed
 * at the root of the archive (no parent directory), which is what the Terraform
 * Cloud configuration-version upload endpoint expects.
 */
export function buildTarball(files: Record<string, string>): Buffer {
  const dir = mkdtempSync(path.join(tmpdir(), "tfc-cv-"));
  try {
    for (const [name, content] of Object.entries(files)) {
      writeFileSync(path.join(dir, name), content);
    }
    return execFileSync("tar", ["-czf", "-", "-C", dir, "."], {
      maxBuffer: 64 * 1024 * 1024,
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
