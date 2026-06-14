import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  loadSettings,
  extractFirebasePlatform,
} from "../lib/settings/index.js";
import {
  buildTerraformVariables,
  expandFirebasePlatformPlaceholders,
} from "../lib/dispatch/index.js";

// ---------------------------------------------------------------------------
// Shared test helpers for fixture-based spec files.
//
// fixtures は `__tests__/fixtures/settings/` 配下、error fixtures は
// その `errors/` サブディレクトリ。spec 側は fixture 名 (相対 path) だけを
// 指定する。実 src/index.ts と同じ pipeline を通す。
// ---------------------------------------------------------------------------

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES_DIR = resolve(__dirname, "fixtures/settings");

/**
 * fixture を読んで loadSettings → expandFirebasePlatformPlaceholders →
 * buildTerraformVariables の pipeline を通す。実 src/index.ts と同じ順序。
 */
export const loadAndBuild = async (
  fixture: string,
  env: string,
  projectId: string,
) => {
  const settings = await loadSettings(`${FIXTURES_DIR}/${fixture}`);
  const raw = extractFirebasePlatform(settings, env);
  const fp = expandFirebasePlatformPlaceholders(raw, {
    service: settings.service,
    env,
  });
  return {
    settings,
    fp,
    vars: buildTerraformVariables(projectId, fp),
  };
};

/**
 * loadSettings + extractFirebasePlatform だけして、buildTerraformVariables は
 * 呼ばない (error fixture で「build 時点で throws」を assert する用)。
 */
export const loadFirebasePlatform = async (fixture: string, env: string) => {
  const settings = await loadSettings(`${FIXTURES_DIR}/${fixture}`);
  return extractFirebasePlatform(settings, env);
};

/**
 * 変数配列から key で value を引く小道具。
 */
export const getVar = (
  vars: Array<{ key: string; value: string }>,
  key: string,
): string | undefined => vars.find((v) => v.key === key)?.value;

export { buildTerraformVariables };
