import { describe, it, expect } from "vitest";
import { loadAndBuild, getVar } from "./helpers.js";

// ---------------------------------------------------------------------------
// 対象: YAML anchor (`&`) + alias (`*`) + merge key (`<<:`) の挙動
//
// loadSettings の `parseYaml(raw, { merge: true })` が anchor 由来の object を
// shallow-merge して継承する仕組みが、settings.yml の env 跨ぎ共有パターンで
// 期待通り動くことを確認する。
// ---------------------------------------------------------------------------

describe("06-yaml-anchor-shared-config", () => {
  it("そのまま *anchor: anchor 由来の config が継承される", async () => {
    const dev001 = await loadAndBuild(
      "06-yaml-anchor-shared-config.yml",
      "dev-001",
      "anchored-svc-dev-001",
    );
    expect(dev001.fp.firebase).toBe(true);
    expect(dev001.fp.authentication).toBe(true);
    expect(getVar(dev001.vars, "apps")).toContain('"name" = "main"');
    // anchor の firestore は (default) at asia-northeast1
    expect(getVar(dev001.vars, "firestore")).toContain(
      '"location" = "asia-northeast1"',
    );
  });

  it("<<: *anchor で merge してから個別 field override すると、override 側が勝つ", async () => {
    const dev002 = await loadAndBuild(
      "06-yaml-anchor-shared-config.yml",
      "dev-002",
      "anchored-svc-dev-002",
    );
    // anchor からの継承
    expect(dev002.fp.firebase).toBe(true);
    expect(dev002.fp.authentication).toBe(true);
    // firestore は override → us-central1 に変わっている
    const fs = getVar(dev002.vars, "firestore");
    expect(fs).toContain('"location" = "us-central1"');
    expect(fs).not.toContain('"location" = "asia-northeast1"');
  });
});
