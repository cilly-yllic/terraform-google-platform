/**
 * TFC (Terraform Cloud) の metadata 解決ヘルパー。
 *
 * Run metadata (service / environments / labels / source_repo) を取得する
 * 経路として 2 系統を提供する:
 *
 *   - parseRunMessage(runMessage)
 *       Option B。Action A/B が `run_message` フィールドに埋め込んだ JSON を
 *       直接 parse する。TFC API への HTTP 呼び出し不要なので高速かつ
 *       TFC_API_TOKEN を必要としない。
 *
 *   - fetchRunMetadata(runId, baseUrl, token)
 *       Option A。TFC API で対象 Run の workspace 変数を引いて metadata を
 *       組み立てる。旧 Action や run_message が空のフォールバック用途。
 *
 * 切替は Config.metadataSource (run_message / run_variables / both) で行う。
 *
 * @see ./router.ts        — resolveMetadata でどちらを使うかを判断
 * @see ../README.md       — 各 Option の使い分けと注意点 (cumulative env 問題等)
 */

/** TFC API 呼び出しの全体 timeout (内部リトライしないので大きめ) */
const FETCH_TIMEOUT_MS = 30_000

/** エラーログに載せるレスポンスボディの最大長 (PII / secret 漏洩抑止) */
const MAX_ERROR_BODY_LENGTH = 200

export interface TfcRunMeta {
  service: string

  /**
   * 今回 Run で実際に処理対象だった env キーの配列。
   * Option B (run_message) なら正確に「今回の Run の対象」になる。
   * Option A (run_variables) は workspace の管理対象を**累積**で返す仕様上、
   * 「今回ではなく workspace が管理する全 env」となる点に注意 (README 参照)。
   */
  environments: string[]

  /**
   * Action A 起動時の input labels (JS RegExp 文字列の配列)。
   * Action B 側で settings.yml を再解決するための情報源。
   * - Action A が `environment` 単数で呼ばれていた場合は空配列
   * - Option A 経由 (TFC API) では復元不能なので常に空配列
   */
  labels: string[]

  /** dispatch 先 GitHub repo ("owner/name") */
  source_repo: string
}

/**
 * Option A: TFC API 経由で metadata を取得する。
 *
 * 手順:
 *   1. GET /api/v2/runs/{runId} → workspace_id を取り出す
 *      (Run は relationships.workspace で workspace に紐づいている)
 *   2. GET /api/v2/workspaces/{workspaceId}/vars をページングで全件取得
 *   3. 取得した変数マップから service / source_repo / environments を抽出
 *
 * 変数キーの解決優先度:
 *   - service     : TF_VAR_service    or METADATA_SERVICE
 *   - source_repo : TF_VAR_source_repo or METADATA_SOURCE_REPO
 *   両方ある場合は TF_VAR_* を優先 (Terraform Run 中にも参照可能なため整合性が取りやすい)。
 *
 * environments の扱い:
 *   Action A の per-service workspace は `environments` 変数に
 *   "env_key → entry" を JSON 文字列で保持しており、その keys を env リストとする。
 *   この shape は Action A 由来なので、それ以外の workspace では空配列のままになる。
 *
 * @throws レスポンスが non-OK / workspace_id が無い / 必須 metadata 欠落の場合
 */
export const fetchRunMetadata = async (runId: string, baseUrl: string, token: string): Promise<TfcRunMeta> => {
  // 1. Run から workspace_id を引く
  const runRes = await fetch(`${baseUrl}/api/v2/runs/${runId}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.api+json',
    },
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  })
  if (!runRes.ok) {
    const body = await runRes.text()
    throw new Error(`TFC API /runs/${runId} returned ${runRes.status}: ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`)
  }

  // レスポンスの形は JSON:API 仕様で、必要なフィールドだけ optional として narrow する。
  // 全フィールドを書き起こさないのは、TFC 側スキーマ追加の影響を受けないため。
  interface TfcRunResponse {
    data?: {
      relationships?: {
        workspace?: { data?: { id?: string } }
      }
    }
  }
  const runData = (await runRes.json()) as TfcRunResponse
  const workspaceId = runData.data?.relationships?.workspace?.data?.id
  if (!workspaceId) {
    throw new Error(`TFC API /runs/${runId} response missing workspace id`)
  }

  interface TfcVarsResponse {
    data?: Array<{ attributes?: { key?: string; value?: string } }>
    meta?: { pagination?: { next_page?: number | null } }
  }

  // 2. workspace 変数を全件取得 (ページング)。
  //    TFC API の page size 最大は 100。組織によっては変数が 100 超のことがあるため
  //    next_page を辿って必ず最後まで取り切る。
  const allVars: Array<{ attributes?: { key?: string; value?: string } }> = []
  let page = 1
  while (true) {
    const varsRes = await fetch(
      `${baseUrl}/api/v2/workspaces/${workspaceId}/vars?page%5Bnumber%5D=${page}&page%5Bsize%5D=100`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/vnd.api+json',
        },
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      }
    )
    if (!varsRes.ok) {
      const body = await varsRes.text()
      throw new Error(
        `TFC API /workspaces/${workspaceId}/vars returned ${varsRes.status}: ${body.slice(0, MAX_ERROR_BODY_LENGTH)}`
      )
    }
    const varsData = (await varsRes.json()) as TfcVarsResponse
    if (!Array.isArray(varsData.data)) {
      throw new Error(`TFC API /workspaces/${workspaceId}/vars response missing data array`)
    }
    allVars.push(...varsData.data)
    const nextPage = varsData.meta?.pagination?.next_page
    if (!nextPage) break
    page = nextPage
  }

  // 3. 変数を key→value の Map に畳んでから必要な値を引く。
  //    sensitive 変数は value が undefined で返ってくるため typeof で防御している。
  const varMap = new Map<string, string>()
  for (const v of allVars) {
    const key = v.attributes?.key
    const value = v.attributes?.value
    if (typeof key === 'string' && typeof value === 'string') {
      varMap.set(key, value)
    }
  }

  const service = varMap.get('TF_VAR_service') ?? varMap.get('METADATA_SERVICE') ?? ''
  const sourceRepo = varMap.get('TF_VAR_source_repo') ?? varMap.get('METADATA_SOURCE_REPO') ?? ''

  // Action A の per-service workspace が保持する `environments` 変数は
  // "env_key → entry" の JSON map。keys を env リストとして採用する。
  //
  // ただし重要な注意:
  //   この値は workspace が管理する **全 env** を累積で保持しており、
  //   今回 Run の対象 env と一致するとは限らない。Run 毎に正確な env リストが
  //   必要な場合は metadataSource を "run_message" にすること (README 参照)。
  let environments: string[] = []
  const envsVar = varMap.get('environments')
  if (envsVar) {
    try {
      const parsed = JSON.parse(envsVar) as Record<string, unknown>
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        environments = Object.keys(parsed)
      }
    } catch {
      // 変数の中身が壊れている場合は environments を空のままにして、
      // 後続の必須チェックで明示的に reject させる (silent fallback はしない)。
    }
  }

  if (!service || environments.length === 0 || !sourceRepo) {
    throw new Error(
      `Missing metadata in workspace variables: service=${service}, environments=[${environments.join(',')}], source_repo=${sourceRepo}`
    )
  }

  // labels は workspace 変数からは復元できない (input の RegExp 文字列が
  // どこにも残らないため)。常に空配列を返す。
  return { service, environments, labels: [], source_repo: sourceRepo }
}

/**
 * Option B: `run_message` フィールドに JSON として埋め込まれた metadata を parse する。
 *
 * Action A / B (dispatch-project-bootstrap / dispatch-firebase-platform) が
 * Run 作成時に必ずこの shape を埋めて emit する想定:
 *   {
 *     "service": "X",
 *     "environments": ["dev-001", ...],
 *     "labels": ["^tier:dev$", ...],
 *     "source_repo": "owner/name",
 *     "sha": "..."
 *   }
 *
 * 互換性ポリシー:
 *   - `labels` が無い場合は空配列を補う (前方互換: 昔の Action は
 *     labels フィールドを emit していなかった)。
 *   - 一方、`environments` が無い / 空 / 文字列以外を含む shape は
 *     旧仕様 (`env: string` 単数) を意図的に reject するため、null を返す。
 *
 * 失敗時の挙動:
 *   parse 不能 / 必須フィールド欠落 / 型不一致 のすべてで null を返す。
 *   呼び出し元 (router.resolveMetadata) は metadataSource 設定に応じて
 *   - "run_message" 単独    → throw
 *   - "both"                → TFC API へフォールバック
 *   と動作を切り替える。
 */
export const parseRunMessage = (runMessage: string): TfcRunMeta | null => {
  try {
    const parsed = JSON.parse(runMessage) as Record<string, unknown>
    const service = parsed['service']
    const environments = parsed['environments']
    const labelsRaw = parsed['labels']
    const sourceRepo = parsed['source_repo']

    // 必須フィールドの shape チェック。
    // 文字列の空チェックや配列要素の型チェックまで含めて厳格に弾く
    // (downstream に空文字や undefined が漏れて意味不明な GitHub API 失敗に
    //  なるのを防ぐため)。
    // environments は **空配列を許容**する: settings.yml から env を全削除した
    // teardown Run (Action A が project を destroy) では run_message が
    // environments:[] になる。これは壊れた metadata ではなく正常な teardown 通知
    // なので null を返して 500 にしてはいけない (dispatch 側 #106 の teardown 許容と整合)。
    // 空配列時に dispatch をスキップする判断は呼び出し元 (router) で行う。
    if (
      typeof service !== 'string' ||
      !service ||
      typeof sourceRepo !== 'string' ||
      !sourceRepo ||
      !Array.isArray(environments) ||
      !environments.every(v => typeof v === 'string' && v.length > 0)
    ) {
      return null
    }

    // labels は optional。存在する場合は配列かつ全要素が string であることを要求。
    // 不正な要素混入は前方互換と扱わず明示的に reject する (型壊れを下流に流さない)。
    let labels: string[] = []
    if (Array.isArray(labelsRaw)) {
      if (!labelsRaw.every(v => typeof v === 'string')) return null
      labels = labelsRaw as string[]
    }

    return {
      service,
      environments: environments as string[],
      labels,
      source_repo: sourceRepo,
    }
  } catch {
    // JSON.parse の SyntaxError は単なる「run_message が JSON ではない」状態。
    // 攻撃でも例外でもなく旧 Action の正常出力もここに来るため、null を返すだけ。
    return null
  }
}
