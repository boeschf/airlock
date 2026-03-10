#!/usr/bin/env bash
set -euo pipefail

# Usage: exec-with-env0.sh <cmd> [args...]
# Reads NUL-separated KEY=VALUE entries from stdin, exports them, then execs the command.

is_valid_ident() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

drop_var() {
  case "$1" in
    # Airlock/sudo internals
    AIRLOCK_*|SUDO_*)
      return 0
      ;;

    # Exported bash functions show up as BASH_FUNC_name%% and are not safe/portable to replay
    BASH_FUNC_*)

      return 0
      ;;

  esac

  # Drop anything that isn't a legal shell variable name
  is_valid_ident "$1" || return 0

  return 1
}

while IFS= read -r -d '' kv; do
  key="${kv%%=*}"
  val="${kv#*=}"

  if drop_var "$key"; then
    continue
  fi

  export "$key=$val"
done

exec "$@"
