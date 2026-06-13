# shellcheck shell=bash
# `print-env` subcommand: apply 完了済みプロジェクトから設定値を再出力する。
# 実体ロジック (print_env) は _commands/print_env.sh に置いてある。
run_print_env() {
  check_commands
  check_gcloud_auth
  check_required_vars

  if ! project_exists; then
    error "Project ${BOOTSTRAP_PROJECT_ID} does not exist. Run 'make bootstrap' first."
  fi

  print_env
}
