#!/usr/bin/env bash
set -euo pipefail

# Usage: exec-with-env0.sh <cmd> [args...]
# Reads NUL-separated KEY=VALUE entries from stdin, exports them, then execs the command.

# Optionally drop/ignore variables we do NOT want to carry over:
drop_var() {
  case "$1" in
    AIRLOCK_*|SUDO_* ) return 0 ;;
    *) return 1 ;;
  esac
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
