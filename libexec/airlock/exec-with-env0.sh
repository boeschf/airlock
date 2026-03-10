#!/usr/bin/env bash
set -euo pipefail

is_valid_ident() { [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; }

drop_var() {
  case "$1" in
    AIRLOCK_*|SUDO_*|BASH_FUNC_* ) return 0 ;;
  esac
  is_valid_ident "$1" || return 0
  return 1
}

read_env0_from_fd() {
  local fd="$1" kv key val
  while IFS= read -r -d '' kv <&"$fd"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    drop_var "$key" && continue
    export "$key=$val"
  done
}

# Prefer a FIFO provided by caller; otherwise read from stdin
if [[ -n "${AIRLOCK_ENV_FIFO:-}" ]]; then
  exec 3<"$AIRLOCK_ENV_FIFO"
  unset AIRLOCK_ENV_FIFO
  read_env0_from_fd 3
  exec 3<&-
else
  read_env0_from_fd 0
fi

# If caller provided a desired working directory, try to use it.
# If it's not accessible inside the namespace, fall back to $HOME, then /.
if [[ -n "${AIRLOCK_CWD:-}" ]]; then
  if ! cd -- "$AIRLOCK_CWD" 2>/dev/null; then
    cd -- "${HOME:-/}" 2>/dev/null || cd /
  fi
  unset AIRLOCK_CWD
fi

exec "$@"
