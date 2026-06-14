import { describe, it, expect } from "vitest";
import {
  loadFirebasePlatform,
  buildTerraformVariables,
} from "./helpers.js";

// ---------------------------------------------------------------------------
// 対象: lib/dispatch/index.ts の validateFirestoreEntry (firestore[] の必須
// field / type 値域 検証)。
// ---------------------------------------------------------------------------

describe("E04-firestore-missing-database-id", () => {
  it("firestore[].database_id 欠落 → throws", async () => {
    const fp = await loadFirebasePlatform(
      "errors/E04-firestore-missing-database-id.yml",
      "prd-001",
    );
    expect(() => buildTerraformVariables("p", fp)).toThrow(
      /firestore\[0\]: 'database_id' is required/,
    );
  });
});
