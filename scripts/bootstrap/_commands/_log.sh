# shellcheck shell=bash
# 共通ログヘルパー。INFO は stdout、ERROR は stderr に出して exit 1。

info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }
