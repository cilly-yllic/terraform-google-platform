#!/usr/bin/env bash
#
# bootstrap で作成・設定した infra プロジェクトの値を、消費側リポジトリ
# (.env GITHUB_REPOSITORY) の GitHub Actions Secrets / Variables に確認・同期する。
#
# 背景:
#   - 消費側 repo (例: MoooDoNE/infrastructure) の workflow
#     (provision-project / configure-platform / deploy-cloud-run-router 等) は、
#     bootstrap が作った infra の識別子 (project id/number, WIF provider, SA email,
#     folder id) を Secrets/Variables 経由で参照する。
#   - これらの大半は `.env` + gcloud から決定的に導出できるので本スクリプトで
#     自動同期する。外部トークン類 (GitHub App PEM, TFC token 等) は導出不能なので
#     存在チェックと案内のみ行う。
#
# 分類:
#   derived  : .env / gcloud から導出 → check で diff、apply で set
#   manual   : 外部から取得する値 → 存在チェックのみ。env で同名を export していれば set
#   workflow : 他 workflow が自動登録する値 (CLOUD_RUN_WEBHOOK_URL 等) → 存在チェックのみ
#
# usage:
#   scripts/github-sync.sh check     # dry-run。現状と desired の差分を表示
#   scripts/github-sync.sh apply     # derived を set (manual は env があれば set)
#   scripts/github-sync.sh apply --yes
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ---- entry registry ------------------------------------------------------
# "NAME|KIND|SOURCE"  KIND=var|secret  SOURCE=derived|manual|workflow
ENTRIES=(
  # bootstrap (infra) identity — 非機微なので Variable に統一 (旧 GCP_PROJECT_ID /
  # GCP_PROJECT_NUMBER / PARENT_FOLDER_ID の重複を廃し BOOTSTRAP_* に集約)。
  "BOOTSTRAP_PROJECT_ID|var|derived"
  "BOOTSTRAP_PROJECT_NUMBER|var|derived"
  "BOOTSTRAP_FOLDER_ID|var|derived"
  "GH_APP_ID|var|manual"

  # deploy/WIF 用 (identity ではないので GCP_ のまま、Secret)
  "GCP_WORKLOAD_IDENTITY_PROVIDER|secret|derived"
  "GCP_DEPLOY_SERVICE_ACCOUNT|secret|derived"
  "GCP_RUNTIME_SERVICE_ACCOUNT|secret|derived"

  "GH_APP_PRIVATE_KEY|secret|manual"
  "DEPLOY_WEBHOOK|secret|manual"
  "TFC_TOKEN|secret|manual"

  "CLOUD_RUN_WEBHOOK_URL|secret|workflow"
  "TFC_NOTIFICATION_SECRET|secret|workflow"
)

load_env() {
  [[ -f "${ENV_FILE}" ]] || error ".env not found at ${ENV_FILE}. Copy scripts/bootstrap.example.env to .env first."
  # shellcheck source=/dev/null
  source "${ENV_FILE}"

  # backward-compat: 旧変数名 (prefix 無し) → 新名 (BOOTSTRAP_*)。bootstrap の load_env
  # と挙動を揃える。DEPRECATED — 次の major で削除予定。
  for pair in "BILLING_ACCOUNT_ID:BOOTSTRAP_BILLING_ACCOUNT_ID" "FOLDER_NAME:BOOTSTRAP_FOLDER_NAME" "FOLDER_ID:BOOTSTRAP_FOLDER_ID"; do
    old="${pair%%:*}"; new="${pair##*:}"
    if [[ -n "${!old:-}" && -z "${!new:-}" ]]; then
      echo "[WARN]  .env: '${old}' は非推奨です。'${new}' に改名してください (今回は自動マップ)。" >&2
      export "${new}"="${!old}"
    fi
  done

  [[ -n "${GITHUB_REPOSITORY:-}" ]] || error "GITHUB_REPOSITORY is required in .env (format: owner/repo)."
  [[ "${GITHUB_REPOSITORY}" =~ ^[^/]+/[^/]+$ ]] || error "GITHUB_REPOSITORY must be 'owner/repo', got: ${GITHUB_REPOSITORY}"
  [[ -n "${BOOTSTRAP_PROJECT_ID:-}" ]] || error "BOOTSTRAP_PROJECT_ID is required in .env."

  # defaults (bootstrap.example.env と一致させる)
  WORKLOAD_IDENTITY_POOL_ID="${WORKLOAD_IDENTITY_POOL_ID:-terraform-cloud}"
  WORKLOAD_IDENTITY_PROVIDER_ID="${WORKLOAD_IDENTITY_PROVIDER_ID:-terraform-cloud}"
  GITHUB_WIF_PROVIDER_ID="${GITHUB_WIF_PROVIDER_ID:-github-actions}"
  CLOUD_RUN_DEPLOY_SA_ID="${CLOUD_RUN_DEPLOY_SA_ID:-cloud-run-router-deploy}"
  CLOUD_RUN_RUNTIME_SA_ID="${CLOUD_RUN_RUNTIME_SA_ID:-cloud-run-router-runtime}"
  ENABLE_CLOUD_RUN_DEPLOY_SETUP="${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}"
}

check_prereqs() {
  command -v gh >/dev/null 2>&1 || error "'gh' CLI not found. Install gh and run 'gh auth login'."
  gh auth status >/dev/null 2>&1 || error "gh is not authenticated. Run 'gh auth login'."
}

# .env の BOOTSTRAP_PROJECT_ID に WIF pool/provider が実在するか検証する。
#
# 目的 (重要): derived 値 (特に BOOTSTRAP_PROJECT_NUMBER) は BOOTSTRAP_PROJECT_ID から
# gcloud で導出するため、.env が stale (例: 旧 bootstrap project を指したまま) だと
# 「実在しない / 別 project の番号」を黙って set してしまい、Action B の WIF audience が
# invalid_target で落ちる。ここで実在チェックして不一致なら set 前に中止する。
#   - pool: ${WORKLOAD_IDENTITY_POOL_ID}
#   - provider: ${WORKLOAD_IDENTITY_PROVIDER_ID} (= Action B の TFC audience が使う provider)
#   - ENABLE_CLOUD_RUN_DEPLOY_SETUP=true の時は github provider も検証
verify_bootstrap_wif() {
  command -v gcloud >/dev/null 2>&1 || error "'gcloud' not found (WIF 検証に必要)。"
  local loc=global
  gcloud iam workload-identity-pools describe "${WORKLOAD_IDENTITY_POOL_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" --location="${loc}" --format='value(state)' >/dev/null 2>&1 \
    || error "WIF pool '${WORKLOAD_IDENTITY_POOL_ID}' が ${BOOTSTRAP_PROJECT_ID} に見つかりません。.env の BOOTSTRAP_PROJECT_ID が正しいか / make bootstrap 済みか確認してください (stale な値だと誤った BOOTSTRAP_PROJECT_NUMBER を set してしまうため中止しました)。"
  gcloud iam workload-identity-pools providers describe "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" --location="${loc}" --format='value(state)' >/dev/null 2>&1 \
    || error "WIF provider '${WORKLOAD_IDENTITY_PROVIDER_ID}' が ${BOOTSTRAP_PROJECT_ID} に見つかりません (Action B の audience に使われます)。BOOTSTRAP_PROJECT_ID を確認してください。"
  if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP}" == "true" ]]; then
    gcloud iam workload-identity-pools providers describe "${GITHUB_WIF_PROVIDER_ID}" \
      --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
      --project="${BOOTSTRAP_PROJECT_ID}" --location="${loc}" --format='value(state)' >/dev/null 2>&1 \
      || error "GitHub WIF provider '${GITHUB_WIF_PROVIDER_ID}' が ${BOOTSTRAP_PROJECT_ID} に見つかりません (GCP_WORKLOAD_IDENTITY_PROVIDER に使われます)。"
  fi
  info "WIF 検証 OK: ${BOOTSTRAP_PROJECT_ID} に pool='${WORKLOAD_IDENTITY_POOL_ID}' / provider='${WORKLOAD_IDENTITY_PROVIDER_ID}' が実在"
}

# project number を memoize (gcloud 呼び出しは1回だけ)
_PROJECT_NUMBER=""
project_number() {
  if [[ -z "${_PROJECT_NUMBER}" ]]; then
    command -v gcloud >/dev/null 2>&1 || error "'gcloud' not found (needed to resolve BOOTSTRAP_PROJECT_NUMBER)."
    _PROJECT_NUMBER="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" --format='value(projectNumber)' 2>/dev/null || true)"
    [[ -n "${_PROJECT_NUMBER}" ]] || error "could not resolve project number for ${BOOTSTRAP_PROJECT_ID} (gcloud auth / project exist?)."
  fi
  echo "${_PROJECT_NUMBER}"
}

# 指定 repo の Variable 値を返す (無ければ空)。サービス repo 同期で使う。
svc_var() {
  gh variable list --repo "$1" --json name,value --jq ".[] | select(.name==\"$2\") | .value" 2>/dev/null || true
}

# derived な値をグローバル DESIRED / REASON にセットする。
# (command substitution の subshell だと REASON が伝播しないため echo ではなく
#  グローバルに書く設計。導出不能 / 非該当なら DESIRED="" + REASON に理由。)
DESIRED=""
REASON=""
set_desired() {
  local name="$1"
  REASON=""
  DESIRED=""
  case "${name}" in
    BOOTSTRAP_PROJECT_ID)
      DESIRED="${BOOTSTRAP_PROJECT_ID}" ;;
    BOOTSTRAP_PROJECT_NUMBER)
      DESIRED="$(project_number)" ;; # project_number は失敗時 error で exit
    BOOTSTRAP_FOLDER_ID)
      # サービス project の fallback 親 folder (= bootstrap/infra folder)。.env 値そのまま。
      if [[ -z "${BOOTSTRAP_FOLDER_ID:-}" ]]; then REASON="folder mode 未使用 (.env BOOTSTRAP_FOLDER_ID 空)"; else DESIRED="${BOOTSTRAP_FOLDER_ID}"; fi ;;
    GCP_WORKLOAD_IDENTITY_PROVIDER)
      if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP}" != "true" ]]; then REASON="ENABLE_CLOUD_RUN_DEPLOY_SETUP!=true (github WIF provider 未作成)"; else
        DESIRED="projects/$(project_number)/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/providers/${GITHUB_WIF_PROVIDER_ID}"; fi ;;
    GCP_DEPLOY_SERVICE_ACCOUNT)
      if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP}" != "true" ]]; then REASON="ENABLE_CLOUD_RUN_DEPLOY_SETUP!=true (deploy SA 未作成)"; else
        DESIRED="${CLOUD_RUN_DEPLOY_SA_ID}@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com"; fi ;;
    GCP_RUNTIME_SERVICE_ACCOUNT)
      if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP}" != "true" ]]; then REASON="ENABLE_CLOUD_RUN_DEPLOY_SETUP!=true (runtime SA 未作成)"; else
        DESIRED="${CLOUD_RUN_RUNTIME_SA_ID}@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com"; fi ;;
    *)
      # manual: 同名 env を export していれば使う
      DESIRED="${!name:-}" ;;
  esac
}

# 現在の gh variable 値 (無ければ空)。gh の --jq で外部 jq 非依存。
current_var() {
  gh variable list --repo "${GITHUB_REPOSITORY}" --json name,value \
    --jq ".[] | select(.name==\"$1\") | .value" 2>/dev/null || true
}
# secret は値を読めない。存在すれば name を返す。
secret_exists() {
  gh secret list --repo "${GITHUB_REPOSITORY}" --json name \
    --jq ".[] | select(.name==\"$1\") | .name" 2>/dev/null | grep -q "$1"
}

mask() {
  local v="$1"
  if [[ "${#v}" -le 8 ]]; then echo "********"; else echo "${v:0:4}…${v: -2} (len=${#v})"; fi
}

# ---- check ---------------------------------------------------------------
cmd_check() {
  info "Target repo: ${GITHUB_REPOSITORY}"
  printf "\n%-32s %-7s %-9s %s\n" "NAME" "KIND" "SOURCE" "STATUS"
  printf '%s\n' "-------------------------------------------------------------------------------"
  for e in "${ENTRIES[@]}"; do
    IFS='|' read -r name kind source <<<"${e}"
    local desired status
    set_desired "${name}"; desired="${DESIRED}"

    if [[ "${kind}" == "var" ]]; then
      local cur; cur="$(current_var "${name}")"
      if [[ "${source}" == "derived" ]]; then
        if [[ -z "${desired}" ]]; then status="SKIP — ${REASON:-導出不可}"
        elif [[ -z "${cur}" ]]; then status="MISSING → set '${desired}'"
        elif [[ "${cur}" == "${desired}" ]]; then status="OK (${cur})"
        else status="DRIFT cur='${cur}' want='${desired}'"; fi
      else
        if [[ -z "${cur}" ]]; then status="MANUAL — 未設定 (要手動登録)"; else status="OK (${cur})"; fi
      fi
    else
      # secret: 存在のみ判定
      local present="no"; secret_exists "${name}" && present="yes"
      case "${source}" in
        derived)
          if [[ -z "${desired}" ]]; then status="SKIP — ${REASON:-非該当}"
          elif [[ "${present}" == "yes" ]]; then status="SET (値比較不可) want=$(mask "${desired}")"
          else status="MISSING → set $(mask "${desired}")"; fi ;;
        manual)
          if [[ "${present}" == "yes" ]]; then status="OK (set)"
          elif [[ -n "${desired}" ]]; then status="MANUAL — env 検出 → apply で set 可"
          else status="MANUAL — 未設定 (要手動登録)"; fi ;;
        workflow)
          if [[ "${present}" == "yes" ]]; then status="OK (workflow 登録済)"; else status="PENDING — 該当 workflow 実行で自動登録"; fi ;;
      esac
    fi
    printf "%-32s %-7s %-9s %s\n" "${name}" "${kind}" "${source}" "${status}"
  done

  # サービス repo (deploy.yml が WIF で使う) の BOOTSTRAP_PROJECT_NUMBER も確認。
  if [[ -n "${SERVICE_GITHUB_REPOS:-}" ]]; then
    local num; num="$(project_number)"
    echo; info "サービス repo の BOOTSTRAP_PROJECT_NUMBER (deploy.yml WIF 用):"
    local repo cur st
    for repo in ${SERVICE_GITHUB_REPOS}; do
      cur="$(svc_var "${repo}" BOOTSTRAP_PROJECT_NUMBER)"
      if [[ -z "${cur}" ]]; then st="MISSING → set '${num}'"
      elif [[ "${cur}" == "${num}" ]]; then st="OK (${num})"
      else st="DRIFT cur='${cur}' want='${num}'"; fi
      printf "  %-28s %s\n" "${repo}" "${st}"
    done
  fi
  echo
  info "derived の MISSING/DRIFT を反映するには: scripts/github-sync.sh apply"
}

# ---- apply ---------------------------------------------------------------
APPLY_YES="false"
cmd_apply() {
  local -a to_set_desc=()
  for e in "${ENTRIES[@]}"; do
    IFS='|' read -r name kind source <<<"${e}"
    [[ "${source}" == "workflow" ]] && continue
    local desired; set_desired "${name}"; desired="${DESIRED}"
    [[ -z "${desired}" ]] && continue  # 導出不能 / env 未設定 はスキップ
    if [[ "${kind}" == "var" ]]; then
      local cur; cur="$(current_var "${name}")"
      [[ "${cur}" == "${desired}" ]] && continue
      to_set_desc+=("var    ${name} = ${desired}")
    else
      to_set_desc+=("secret ${name} = $(mask "${desired}")")
    fi
  done

  # サービス repo の BOOTSTRAP_PROJECT_NUMBER も差分に含める。
  local svc_num=""
  if [[ -n "${SERVICE_GITHUB_REPOS:-}" ]]; then
    svc_num="$(project_number)"
    local repo cur
    for repo in ${SERVICE_GITHUB_REPOS}; do
      cur="$(svc_var "${repo}" BOOTSTRAP_PROJECT_NUMBER)"
      [[ "${cur}" == "${svc_num}" ]] && continue
      to_set_desc+=("var    BOOTSTRAP_PROJECT_NUMBER = ${svc_num}  [${repo}]")
    done
  fi

  if [[ "${#to_set_desc[@]}" -eq 0 ]]; then
    info "差分なし — set すべき derived/manual(env) はありません。"
    return 0
  fi

  echo "以下を ${GITHUB_REPOSITORY} に set します:"
  printf '  - %s\n' "${to_set_desc[@]}"
  # secret は値比較不可のため derived secret は毎回上書きになる点に注意
  if [[ "${APPLY_YES}" != "true" && "${CONFIRM_BEFORE_APPLY:-true}" != "false" ]]; then
    read -r -p "適用しますか? [y/N] " ans
    [[ "${ans}" =~ ^[Yy]$ ]] || { info "中止しました。"; return 0; }
  fi

  for e in "${ENTRIES[@]}"; do
    IFS='|' read -r name kind source <<<"${e}"
    [[ "${source}" == "workflow" ]] && continue
    local desired; set_desired "${name}"; desired="${DESIRED}"
    [[ -z "${desired}" ]] && continue
    if [[ "${kind}" == "var" ]]; then
      local cur; cur="$(current_var "${name}")"
      [[ "${cur}" == "${desired}" ]] && continue
      gh variable set "${name}" --repo "${GITHUB_REPOSITORY}" --body "${desired}"
      info "var set: ${name}"
    else
      # --body を付けない → gh は値を stdin から読む。
      # 注: `--body -` は値をリテラル "-" にしてしまう (gh の --body は「未指定なら stdin」)。
      # 旧コードはこれで全 secret を "-" に化けさせ、WIF audience / SA 不正の原因になっていた。
      printf '%s' "${desired}" | gh secret set "${name}" --repo "${GITHUB_REPOSITORY}"
      info "secret set: ${name}"
    fi
  done

  # サービス repo に BOOTSTRAP_PROJECT_NUMBER を set。
  if [[ -n "${SERVICE_GITHUB_REPOS:-}" ]]; then
    local repo cur
    for repo in ${SERVICE_GITHUB_REPOS}; do
      cur="$(svc_var "${repo}" BOOTSTRAP_PROJECT_NUMBER)"
      [[ "${cur}" == "${svc_num}" ]] && continue
      gh variable set BOOTSTRAP_PROJECT_NUMBER --repo "${repo}" --body "${svc_num}"
      info "var set: BOOTSTRAP_PROJECT_NUMBER [${repo}]"
    done
  fi
  echo
  info "完了。手動登録が必要な値 (manual で未設定) は check の出力を参照してください。"
}

show_help() {
  cat <<EOF
Usage: $0 <check|apply> [--yes]

bootstrap 済み infra の値を消費側 repo (.env GITHUB_REPOSITORY) の GitHub Actions
Secrets / Variables に確認・同期する。

  check         現状と desired の差分を表示 (書き込まない)
  apply [--yes] derived を set (manual は同名 env を export していれば set)。
                --yes で確認プロンプトをスキップ (CONFIRM_BEFORE_APPLY=false でも可)。

manual (外部トークン) を apply で set したい場合は同名で export:
  GH_APP_ID=12345 TFC_TOKEN=xxx DEPLOY_WEBHOOK=https://... \\
    GH_APP_PRIVATE_KEY="\$(cat key.pem)" scripts/github-sync.sh apply

ENVIRONMENT (.env から読む)
  GITHUB_REPOSITORY              orchestrator 同期先 repo (owner/repo, 必須)
  BOOTSTRAP_PROJECT_ID           infra プロジェクト ID (必須)
  BOOTSTRAP_FOLDER_ID            サービス project の fallback 親 folder (folder mode 時)
  ENABLE_CLOUD_RUN_DEPLOY_SETUP  true の時のみ deploy/runtime SA + github WIF を導出
  SERVICE_GITHUB_REPOS           サービス repo (deploy.yml が WIF で使う) を空白区切りで列挙。
                                 各 repo に BOOTSTRAP_PROJECT_NUMBER (Variable) を同期する。
                                 例: "MoooDoNE/cmonoth MoooDoNE/draft-craft"
EOF
}

main() {
  [[ $# -ge 1 ]] || { show_help >&2; exit 1; }
  local sub="$1"; shift || true
  for a in "$@"; do [[ "${a}" == "--yes" ]] && APPLY_YES="true"; done
  case "${sub}" in
    check) load_env; check_prereqs; verify_bootstrap_wif; cmd_check ;;
    apply) load_env; check_prereqs; verify_bootstrap_wif; cmd_apply ;;
    -h|--help|help) show_help ;;
    *) echo "[ERROR] Unknown subcommand: ${sub}" >&2; echo "" >&2; show_help >&2; exit 1 ;;
  esac
}

main "$@"
