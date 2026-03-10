#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

if [[ -n "${AIRLOCK_CLI_UTILS_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
readonly AIRLOCK_CLI_UTILS_SH_LOADED=1

airlock_cli_select_config() {
  local explicit_config='' profile=''
  local default_profile="${AIRLOCK_DEFAULT_PROFILE:-default}"
  declare -ag AIRLOCK_CLI_REMAINING_ARGS=()

  while (($# > 0)); do
    case "$1" in
      --config)
        (($# >= 2)) || airlock_die '--config requires a path'
        explicit_config="$2"
        shift 2
        ;;
      --profile)
        (($# >= 2)) || airlock_die '--profile requires a name'
        profile="$2"
        shift 2
        ;;
      -h|--help)
        if declare -F airlock_cli_usage >/dev/null 2>&1; then
          airlock_cli_usage
          exit 0
        fi
        airlock_die "Help requested but airlock_cli_usage() is not defined in this script"
        ;;
      *)
        AIRLOCK_CLI_REMAINING_ARGS=("$@")
        break
        ;;
    esac
  done

  if [[ -n "$explicit_config" && -n "$profile" ]]; then
    airlock_die 'Use either --config or --profile, not both'
  fi

  # Select config in this precedence order:
  # 1) explicit --config
  # 2) explicit --profile
  # 3) AIRLOCK_DEFAULT_CONFIG (path)
  # 4) AIRLOCK_DEFAULT_PROFILE (name) or "default"
  if [[ -n "$explicit_config" ]]; then
    AIRLOCK_CONFIG="$explicit_config"

  elif [[ -n "$profile" ]]; then
    AIRLOCK_CONFIG="$(airlock_config_path_for_profile "$profile")" \
      || airlock_die "Profile not found: $profile"

  elif [[ -n "${AIRLOCK_DEFAULT_CONFIG:-}" ]]; then
    AIRLOCK_CONFIG="$AIRLOCK_DEFAULT_CONFIG"
    [[ -r "$AIRLOCK_CONFIG" ]] || airlock_die "AIRLOCK_DEFAULT_CONFIG is not readable: $AIRLOCK_CONFIG"

  else
    # Fall back to default profile name
    AIRLOCK_CONFIG="$(airlock_config_path_for_profile "$default_profile")" || airlock_die \
      "No --profile/--config given and default profile '${default_profile}' not found.
Create ${XDG_CONFIG_HOME:-$HOME/.config}/airlock/${default_profile}.conf (or /etc/airlock/${default_profile}.conf),
or set AIRLOCK_DEFAULT_PROFILE / AIRLOCK_DEFAULT_CONFIG, or pass --profile/--config explicitly."
  fi

  export AIRLOCK_CONFIG
  airlock_load_config_file
}
