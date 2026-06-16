// Terraform Registry から本プラットフォームモジュール
// (`cilly-yllic/platform/google`) の最新版を解決する。
//
// 設計判断:
//   - GitHub Tags ではなく **Terraform Registry を直接 query**。registry に
//     publish 済 = Terraform が実際に download できる前提で「使える最新版」を
//     返したい。GitHub tag だと publish 前のタグまで拾ってしまう
//   - 未指定時のみ auto-resolve。`module_version` input が指定されている
//     場合はそれを尊重 (consumer 側で pin を強制できる)
//   - pre-release (`0.0.0-rcN`) の比較は SemVer 仕様に従う。`rc14` > `rc2`
//     を localeCompare の numeric mode で実現

const PLATFORM_MODULE_REGISTRY_URL =
  "https://registry.terraform.io/v1/modules/cilly-yllic/platform/google/versions";

const FETCH_TIMEOUT_MS = 15_000;

interface RegistryVersionsResponse {
  modules: Array<{
    versions: Array<{ version: string }>;
  }>;
}

export async function resolveModuleVersion(
  explicit: string | undefined,
  fetchFn: typeof fetch = fetch,
): Promise<string> {
  if (explicit && explicit.trim() !== "") {
    return explicit.trim();
  }
  const res = await fetchFn(PLATFORM_MODULE_REGISTRY_URL, {
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (!res.ok) {
    throw new Error(
      `Failed to fetch platform module versions from Terraform Registry (${res.status}). ` +
        `Set the 'module_version' input explicitly to bypass this lookup.`,
    );
  }
  const data = (await res.json()) as RegistryVersionsResponse;
  const versions = data.modules?.[0]?.versions?.map((v) => v.version) ?? [];
  if (versions.length === 0) {
    throw new Error(
      "No platform module versions found on Terraform Registry. " +
        "Set the 'module_version' input explicitly to bypass this lookup.",
    );
  }
  return pickLatestSemver(versions);
}

export function pickLatestSemver(versions: string[]): string {
  return [...versions].sort((a, b) => compareSemver(b, a))[0];
}

/**
 * SemVer compare. Returns negative/zero/positive like a-b.
 *
 * Rules covered:
 *   - main version は segment ごとに数値比較 (`1.10.0 > 1.2.0`)
 *   - pre-release **無し** > pre-release あり (`1.0.0 > 1.0.0-rc1`)
 *   - 両方 pre-release のときは dot 区切りで identifier 比較:
 *       - 両 identifier が数値なら数値比較
 *       - 片方だけ数値なら数値側が小さい (SemVer の正式仕様)
 *       - 両方 alphanumeric なら localeCompare(numeric:true) で
 *         `rc14 > rc2` のような自然な順序にする (厳密 SemVer は文字列
 *         比較で `rc14 < rc2` だが、本プロジェクトの tag 慣習に合わせる)
 */
export function compareSemver(a: string, b: string): number {
  const aClean = a.replace(/^v/, "");
  const bClean = b.replace(/^v/, "");
  const [aMain, aPre = ""] = aClean.split("-", 2);
  const [bMain, bPre = ""] = bClean.split("-", 2);

  const mainCmp = compareNumericSegments(aMain, bMain);
  if (mainCmp !== 0) return mainCmp;

  if (!aPre && bPre) return 1;
  if (aPre && !bPre) return -1;
  if (!aPre && !bPre) return 0;

  return compareDotIdentifiers(aPre, bPre);
}

function compareNumericSegments(a: string, b: string): number {
  const ap = a.split(".").map((n) => parseInt(n, 10) || 0);
  const bp = b.split(".").map((n) => parseInt(n, 10) || 0);
  const max = Math.max(ap.length, bp.length);
  for (let i = 0; i < max; i++) {
    const d = (ap[i] ?? 0) - (bp[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

function compareDotIdentifiers(a: string, b: string): number {
  const ap = a.split(".");
  const bp = b.split(".");
  const max = Math.max(ap.length, bp.length);
  for (let i = 0; i < max; i++) {
    if (ap[i] === undefined) return -1;
    if (bp[i] === undefined) return 1;
    const aNum = /^\d+$/.test(ap[i]);
    const bNum = /^\d+$/.test(bp[i]);
    if (aNum && bNum) {
      const d = parseInt(ap[i], 10) - parseInt(bp[i], 10);
      if (d !== 0) return d;
    } else if (aNum !== bNum) {
      return aNum ? -1 : 1;
    } else {
      const d = ap[i].localeCompare(bp[i], undefined, { numeric: true });
      if (d !== 0) return d;
    }
  }
  return 0;
}
