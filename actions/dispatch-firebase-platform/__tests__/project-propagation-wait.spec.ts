import { describe, it, expect } from "vitest";
import {
  resolveProjectPropagationWaitMs,
  PROPAGATION_WAIT_EVENT,
} from "../lib/dispatch/index.js";

// ---------------------------------------------------------------------------
// 対象: resolveProjectPropagationWaitMs (chained-from-A の pre-run sleep 判定)。
//
// repository_dispatch (router 経由 = Action A 直後) の時だけ待ち、手動
// workflow_dispatch や run 0 件のときは待たない、を純関数として検証する。
// ---------------------------------------------------------------------------

describe("resolveProjectPropagationWaitMs", () => {
  it("waits when chained from A (repository_dispatch) and there are targets", () => {
    expect(
      resolveProjectPropagationWaitMs({
        eventName: PROPAGATION_WAIT_EVENT,
        waitSeconds: 60,
        hasTargets: true,
      }),
    ).toBe(60_000);
  });

  it("does not wait on manual workflow_dispatch", () => {
    expect(
      resolveProjectPropagationWaitMs({
        eventName: "workflow_dispatch",
        waitSeconds: 60,
        hasTargets: true,
      }),
    ).toBe(0);
  });

  it("does not wait for unknown / empty event names", () => {
    expect(
      resolveProjectPropagationWaitMs({
        eventName: "",
        waitSeconds: 60,
        hasTargets: true,
      }),
    ).toBe(0);
  });

  it("does not wait when there are no targets (no run will be created)", () => {
    expect(
      resolveProjectPropagationWaitMs({
        eventName: PROPAGATION_WAIT_EVENT,
        waitSeconds: 60,
        hasTargets: false,
      }),
    ).toBe(0);
  });

  it("treats waitSeconds <= 0 as disabled", () => {
    expect(
      resolveProjectPropagationWaitMs({
        eventName: PROPAGATION_WAIT_EVENT,
        waitSeconds: 0,
        hasTargets: true,
      }),
    ).toBe(0);
  });

  it("treats NaN waitSeconds as disabled (defensive against bad input)", () => {
    expect(
      resolveProjectPropagationWaitMs({
        eventName: PROPAGATION_WAIT_EVENT,
        waitSeconds: Number.NaN,
        hasTargets: true,
      }),
    ).toBe(0);
  });

  it("floors fractional seconds to whole milliseconds", () => {
    expect(
      resolveProjectPropagationWaitMs({
        eventName: PROPAGATION_WAIT_EVENT,
        waitSeconds: 1.5,
        hasTargets: true,
      }),
    ).toBe(1_500);
  });
});
