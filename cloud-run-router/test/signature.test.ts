import { describe, it, expect } from "vitest";
import { createHmac } from "node:crypto";
import { verifySignature } from "../src/signature.js";

const SECRET = "test-hmac-secret";

function sign(body: string, secret: string): string {
  return createHmac("sha512", secret).update(body).digest("hex");
}

describe("verifySignature", () => {
  it("returns true for a valid HMAC-SHA512 signature", () => {
    const body = Buffer.from('{"hello":"world"}');
    const sig = sign(body.toString(), SECRET);
    expect(verifySignature(body, sig, SECRET)).toBe(true);
  });

  it("returns false when signature is missing", () => {
    const body = Buffer.from("data");
    expect(verifySignature(body, undefined, SECRET)).toBe(false);
  });

  it("returns false when signature is wrong", () => {
    const body = Buffer.from("data");
    expect(verifySignature(body, "bad-sig", SECRET)).toBe(false);
  });

  it("returns false when body was tampered", () => {
    const sig = sign("original", SECRET);
    const tampered = Buffer.from("tampered");
    expect(verifySignature(tampered, sig, SECRET)).toBe(false);
  });

  it("returns false when secret differs", () => {
    const body = Buffer.from("data");
    const sig = sign("data", "other-secret");
    expect(verifySignature(body, sig, SECRET)).toBe(false);
  });
});
