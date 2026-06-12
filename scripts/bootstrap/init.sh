# shellcheck shell=bash
# `--init` mode: bootstrap.example.env から .env or .envrc テンプレートを生成する。
# 既存ファイルがある場合は上書きせずエラー終了。
run_init() {
  local target_format="${1:-}"
  local template="${SCRIPT_DIR}/bootstrap.example.env"

  if [[ ! -f "${template}" ]]; then
    error "Template file not found: ${template}"
  fi

  # Determine output format
  if [[ -z "${target_format}" ]]; then
    # Interactive prompt
    echo "Select output format:"
    echo "  1) .env    (KEY=\"value\" — source .env)"
    echo "  2) .envrc  (export KEY=\"value\" — direnv)"
    read -r -p "Choice [1/2]: " choice
    case "${choice}" in
      1) target_format="env" ;;
      2) target_format="envrc" ;;
      *) error "Invalid choice: ${choice}" ;;
    esac
  fi

  local dest
  case "${target_format}" in
    env)
      dest="${REPO_ROOT}/.env"
      ;;
    envrc)
      dest="${REPO_ROOT}/.envrc"
      ;;
    *)
      error "Unknown format: ${target_format}. Use 'env' or 'envrc'."
      ;;
  esac

  # Guard existing file
  if [[ -f "${dest}" ]]; then
    error "${dest} already exists. Remove or rename it before running --init."
  fi

  if [[ "${target_format}" == "envrc" ]]; then
    # Convert to export format
    sed 's/^\([A-Za-z_][A-Za-z_0-9]*=\)/export \1/' "${template}" > "${dest}"
  else
    cp "${template}" "${dest}"
  fi

  info "Created ${dest} from ${template}"
  info "Edit the file and fill in your organization-specific values."
}
