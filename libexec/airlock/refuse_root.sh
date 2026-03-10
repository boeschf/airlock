#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

airlock_refuse_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    if [[ -n "${SUDO_USER:-}" ]]; then
      printf 'Error: do not run airlock via sudo.\nRun as %s: airlock ...\n' "$SUDO_USER" >&2
    else
      printf 'Error: do not run airlock as root.\nRun it as a regular user; it will sudo internally when needed.\n' >&2
    fi
    exit 1
  fi
}
