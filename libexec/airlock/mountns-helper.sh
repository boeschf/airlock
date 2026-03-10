#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

: "${AIRLOCK_LIBEXEC_DIR:?AIRLOCK_LIBEXEC_DIR must be set}"
: "${AIRLOCK_CONFIG:?AIRLOCK_CONFIG must be set}"

# shellcheck source=/dev/null
source "${AIRLOCK_LIBEXEC_DIR}/airlock/common.sh"
airlock_load_config_file
airlock_mountns_child
