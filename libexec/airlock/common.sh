#!/usr/bin/env bash
# shellcheck shell=bash

if [[ -n "${AIRLOCK_COMMON_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
readonly AIRLOCK_COMMON_SH_LOADED=1

set -euo pipefail

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _airlock_common_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  readonly _airlock_common_dir
fi

: "${AIRLOCK_PROGRAM_NAME:=airlock}"
: "${AIRLOCK_DRIVER:=openconnect}"
: "${AIRLOCK_FW_BACKEND:=auto}"
: "${AIRLOCK_RUNTIME_ROOT:=/run/airlock}"
: "${AIRLOCK_STATE_ROOT:=/var/lib/airlock}"
: "${AIRLOCK_SYSTEM_CONFIG_DIR:=/etc/airlock}"
: "${AIRLOCK_NAMESPACE:=airlock}"
: "${AIRLOCK_SUBNET_CIDR:=10.200.200.0/24}"
: "${AIRLOCK_HOST_IP_CIDR:=10.200.200.1/24}"
: "${AIRLOCK_NS_IP_CIDR:=10.200.200.2/24}"
: "${AIRLOCK_VETH_HOST:=alh0}"
: "${AIRLOCK_VETH_NS:=aln0}"
: "${AIRLOCK_CONFIG_NAME:=default}"
if [[ -n "${_airlock_common_dir:-}" ]]; then
  : "${AIRLOCK_LIBEXEC_DIR:=$(cd -- "${_airlock_common_dir}/.." && pwd -P)}"
else
  : "${AIRLOCK_LIBEXEC_DIR:=}"
fi

AIRLOCK_RUNTIME_DIR="${AIRLOCK_RUNTIME_ROOT}/${AIRLOCK_CONFIG_NAME}"
AIRLOCK_STATE_DIR="${AIRLOCK_STATE_ROOT}/${AIRLOCK_CONFIG_NAME}"
AIRLOCK_PIDFILE="${AIRLOCK_RUNTIME_DIR}/openconnect.pid"
AIRLOCK_MOUNTNS_PIDFILE="${AIRLOCK_RUNTIME_DIR}/mountns.pid"
AIRLOCK_SYSCTL_SNAPSHOT="${AIRLOCK_RUNTIME_DIR}/ip_forward.prev"
AIRLOCK_WAN_IF_FILE="${AIRLOCK_RUNTIME_DIR}/wan.if"
AIRLOCK_FW_BACKEND_FILE="${AIRLOCK_RUNTIME_DIR}/fw.backend"
AIRLOCK_ETC_UPPER_DIR="${AIRLOCK_STATE_DIR}/etc.upper"
AIRLOCK_ETC_WORK_DIR="${AIRLOCK_STATE_DIR}/etc.work"
AIRLOCK_NFT_TABLE="$(printf 'airlock_%s' "$AIRLOCK_CONFIG_NAME" | tr -c '[:alnum:]_' '_')"

export AIRLOCK_PROGRAM_NAME AIRLOCK_DRIVER AIRLOCK_FW_BACKEND AIRLOCK_RUNTIME_ROOT AIRLOCK_STATE_ROOT
export AIRLOCK_SYSTEM_CONFIG_DIR AIRLOCK_NAMESPACE AIRLOCK_SUBNET_CIDR AIRLOCK_HOST_IP_CIDR AIRLOCK_NS_IP_CIDR
export AIRLOCK_VETH_HOST AIRLOCK_VETH_NS AIRLOCK_AUTH_FUNCTION AIRLOCK_CONFIG_NAME AIRLOCK_LIBEXEC_DIR
export AIRLOCK_RUNTIME_DIR AIRLOCK_STATE_DIR AIRLOCK_PIDFILE AIRLOCK_MOUNTNS_PIDFILE AIRLOCK_SYSCTL_SNAPSHOT
export AIRLOCK_WAN_IF_FILE AIRLOCK_FW_BACKEND_FILE AIRLOCK_ETC_UPPER_DIR AIRLOCK_ETC_WORK_DIR AIRLOCK_NFT_TABLE

if [[ "${AIRLOCK_DRIVER}" == "openconnect" ]]; then
  : "${OPENCONNECT_SERVER:=}"
  : "${OPENCONNECT_USER:=}"
  : "${OPENCONNECT_USERGROUP:=}"
  : "${OPENCONNECT_USERAGENT:=AnyConnect}"
  : "${OPENCONNECT_PROTOCOL:=}"
  : "${OPENCONNECT_VPNC_SCRIPT:=}"
  export OPENCONNECT_SERVER OPENCONNECT_USER OPENCONNECT_USERGROUP OPENCONNECT_USERAGENT OPENCONNECT_PROTOCOL OPENCONNECT_VPNC_SCRIPT
  if ! declare -p OPENCONNECT_EXTRA_ARGS >/dev/null 2>&1; then
    declare -ag OPENCONNECT_EXTRA_ARGS=()
  fi
fi

# Control:
#   AIRLOCK_COLOR=auto|always|never   (default: auto)
#   AIRLOCK_DEBUG=0|1                (default: 0)

: "${AIRLOCK_COLOR:=auto}"
: "${AIRLOCK_DEBUG:=0}"

_airlock_is_tty_stderr() { [[ -t 2 ]]; }

_airlock_use_color() {
  case "$AIRLOCK_COLOR" in
    always) return 0 ;;
    never)  return 1 ;;
    auto)   _airlock_is_tty_stderr ;;
    *)      _airlock_is_tty_stderr ;;
  esac
}

_airlock_color() {
  # Usage: _airlock_color <name>
  # names: reset bold dim red green yellow blue magenta cyan gray
  _airlock_use_color || { printf ''; return 0; }
  case "$1" in
    reset)   printf '\033[0m' ;;
    bold)    printf '\033[1m' ;;
    dim)     printf '\033[2m' ;;
    red)     printf '\033[31m' ;;
    green)   printf '\033[32m' ;;
    yellow)  printf '\033[33m' ;;
    blue)    printf '\033[34m' ;;
    magenta) printf '\033[35m' ;;
    cyan)    printf '\033[36m' ;;
    gray)    printf '\033[90m' ;;
    *)       printf '' ;;
  esac
}

_airlock_prefix() {
  # Use config name if loaded, otherwise "default"
  local profile="${AIRLOCK_CONFIG_NAME:-default}"
  printf '%s[%s]' "${AIRLOCK_PROGRAM_NAME:-airlock}" "$profile"
}

_airlock_emit() {
  # _airlock_emit LEVEL COLOR MSG...
  local level="$1"; shift
  local color="$1"; shift
  local prefix msg
  prefix="$(_airlock_prefix)"

  # Build message from remaining args (preserve spacing)
  msg="$*"

  # Format: airlock[profile]: LEVEL message
  printf '%s: %s%s%s %s\n' \
    "$prefix" \
    "$(_airlock_color "$color")" \
    "$level" \
    "$(_airlock_color reset)" \
    "$msg" >&2
}

airlock_log()  { _airlock_emit INFO  cyan   "$*"; }
airlock_warn() { _airlock_emit WARN  yellow "$*"; }
airlock_err()  { _airlock_emit ERROR red    "$*"; }

airlock_debug() {
  [[ "${AIRLOCK_DEBUG}" == "1" ]] || return 0
  _airlock_emit DEBUG gray "$*"
}

airlock_die() {
  airlock_err "$*"
  exit 1
}

airlock_require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || airlock_die "Missing required command: $cmd"
  done
}

airlock_as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo -- "$@"
  fi
}

#airlock_root_test() { airlock_as_root sh -c 'test '"$1"' "$2"' _ "$2"; }
airlock_root_test() {
  local op="$1" path="$2"
  airlock_as_root sh -c 'test "$1" "$2"' _ "$op" "$path"
}
airlock_root_isfile() { airlock_as_root sh -c 'test -f "$1"' _ "$1"; }
airlock_root_isreadable() { airlock_as_root sh -c 'test -r "$1"' _ "$1"; }

airlock_root_cat()  { airlock_as_root sh -c 'cat "$1"' _ "$1"; }

airlock_orig_user() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    printf '%s\n' "$SUDO_USER"
  else
    printf '%s\n' "${USER:?USER not set}"
  fi
}

airlock_validate_ifname() {
  local ifname="${1:?ifname required}"
  [[ ${#ifname} -le 15 ]] || airlock_die "Interface name too long: $ifname"
}

airlock_config_path_for_profile() {
  local profile="${1:?profile required}"
  local user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/airlock"

  if [[ -r "${user_dir}/${profile}.conf" ]]; then
    printf '%s\n' "${user_dir}/${profile}.conf"
  elif [[ -r "${AIRLOCK_SYSTEM_CONFIG_DIR}/${profile}.conf" ]]; then
    printf '%s\n' "${AIRLOCK_SYSTEM_CONFIG_DIR}/${profile}.conf"
  else
    return 1
  fi
}

airlock_find_vpnc_script() {
  local candidate

  for candidate in \
    "$OPENCONNECT_VPNC_SCRIPT" \
    /usr/share/vpnc-scripts/vpnc-script \
    /etc/vpnc/vpnc-script \
    /usr/local/share/vpnc-scripts/vpnc-script
  do
    [[ -n "$candidate" && -x "$candidate" ]] && {
      printf '%s\n' "$candidate"
      return 0
    }
  done

  candidate="$(command -v vpnc-script || true)"
  [[ -n "$candidate" && -x "$candidate" ]] && {
    printf '%s\n' "$candidate"
    return 0
  }

  return 1
}

airlock_require_config_loaded() {
  [[ -n "${AIRLOCK_CONFIG:-}" ]] || airlock_die 'AIRLOCK_CONFIG is not set'
  [[ -r "$AIRLOCK_CONFIG" ]] || airlock_die "Config file is not readable: $AIRLOCK_CONFIG"
}

airlock_load_config_file() {
  airlock_require_config_loaded

  airlock_log "Loading config from: $AIRLOCK_CONFIG"
  # shellcheck disable=SC1090
  source "$AIRLOCK_CONFIG"

  : "${AIRLOCK_CONFIG_NAME:=$(basename -- "$AIRLOCK_CONFIG" .conf)}"
  : "${AIRLOCK_NAMESPACE:=$AIRLOCK_CONFIG_NAME}"
  AIRLOCK_RUNTIME_DIR="${AIRLOCK_RUNTIME_ROOT}/${AIRLOCK_CONFIG_NAME}"
  AIRLOCK_STATE_DIR="${AIRLOCK_STATE_ROOT}/${AIRLOCK_CONFIG_NAME}"
  AIRLOCK_PIDFILE="${AIRLOCK_RUNTIME_DIR}/openconnect.pid"
  AIRLOCK_MOUNTNS_PIDFILE="${AIRLOCK_RUNTIME_DIR}/mountns.pid"
  AIRLOCK_SYSCTL_SNAPSHOT="${AIRLOCK_RUNTIME_DIR}/ip_forward.prev"
  AIRLOCK_WAN_IF_FILE="${AIRLOCK_RUNTIME_DIR}/wan.if"
  AIRLOCK_FW_BACKEND_FILE="${AIRLOCK_RUNTIME_DIR}/fw.backend"
  AIRLOCK_ETC_UPPER_DIR="${AIRLOCK_STATE_DIR}/etc.upper"
  AIRLOCK_ETC_WORK_DIR="${AIRLOCK_STATE_DIR}/etc.work"
  AIRLOCK_NFT_TABLE="$(printf 'airlock_%s' "$AIRLOCK_CONFIG_NAME" | tr -c '[:alnum:]_' '_')"
  AIRLOCK_LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/airlock/${AIRLOCK_CONFIG_NAME}"
  AIRLOCK_OPENCONNECT_LOG="${AIRLOCK_LOG_DIR}/openconnect.log"

  export AIRLOCK_CONFIG_NAME AIRLOCK_NAMESPACE
  export AIRLOCK_RUNTIME_DIR AIRLOCK_STATE_DIR AIRLOCK_PIDFILE AIRLOCK_MOUNTNS_PIDFILE AIRLOCK_SYSCTL_SNAPSHOT
  export AIRLOCK_WAN_IF_FILE AIRLOCK_FW_BACKEND_FILE AIRLOCK_ETC_UPPER_DIR AIRLOCK_ETC_WORK_DIR AIRLOCK_NFT_TABLE
  export AIRLOCK_LOG_DIR AIRLOCK_OPENCONNECT_LOG

  if [[ "$AIRLOCK_DRIVER" == "openconnect" ]]; then
    [[ -n "$OPENCONNECT_SERVER" ]] || airlock_die 'OPENCONNECT_SERVER must be set in config'
    [[ -n "$OPENCONNECT_USER" ]] || airlock_die 'OPENCONNECT_USER must be set in config'
  else
    airlock_die "Unsupported AIRLOCK_DRIVER: $AIRLOCK_DRIVER"
  fi

  airlock_validate_ifname "$AIRLOCK_VETH_HOST"
  airlock_validate_ifname "$AIRLOCK_VETH_NS"

  airlock_log "Config loaded successfully with config name: $AIRLOCK_CONFIG_NAME and namespace: $AIRLOCK_NAMESPACE"
  airlock_log "Runtime dir: $AIRLOCK_RUNTIME_DIR, State dir: $AIRLOCK_STATE_DIR, PID file: $AIRLOCK_PIDFILE, MountNS PID file: $AIRLOCK_MOUNTNS_PIDFILE"
  airlock_log "Log dir: $AIRLOCK_LOG_DIR, OpenConnect log: $AIRLOCK_OPENCONNECT_LOG"
  mkdir -p "$AIRLOCK_LOG_DIR"
  chmod 700 "$AIRLOCK_LOG_DIR"
  : >"$AIRLOCK_OPENCONNECT_LOG"
  chmod 600 "$AIRLOCK_OPENCONNECT_LOG"
}

airlock_auth_payload() {
  local fn="${AIRLOCK_AUTH_FUNCTION:?AIRLOCK_AUTH_FUNCTION is not set}"
  declare -F "$fn" >/dev/null 2>&1 || airlock_die "Auth function not defined: $fn"
  "$fn"
}

airlock_build_openconnect_cmd() {
  local vpnc_script="${1:?vpnc-script path required}"
  local -a cmd

  cmd=(
    openconnect
    "--non-inter"
    "--user=${OPENCONNECT_USER}"
    "--useragent=${OPENCONNECT_USERAGENT}"
    "--passwd-on-stdin"
    "--background"
    "--pid-file=${AIRLOCK_PIDFILE}"
    "--script=${vpnc_script}"
  )

  [[ -n "$OPENCONNECT_USERGROUP" ]] && cmd+=("--usergroup=${OPENCONNECT_USERGROUP}")
  [[ -n "$OPENCONNECT_PROTOCOL" ]] && cmd+=("--protocol=${OPENCONNECT_PROTOCOL}")
  if ((${#OPENCONNECT_EXTRA_ARGS[@]} > 0)); then
    cmd+=("${OPENCONNECT_EXTRA_ARGS[@]}")
  fi
  cmd+=("${OPENCONNECT_SERVER}")

  #printf '%s\0' "${cmd[@]}" " >${AIRLOCK_OPENCONNECT_LOG} 2>&1"
  printf '%s\0' "${cmd[@]}"
}

airlock_openconnect_pid() {
  local pid

  pid="$(airlock_as_root sh -c '
    test -f "$1" || exit 1
    cat "$1"
  ' _ "$AIRLOCK_PIDFILE" 2>/dev/null)" || return 1

  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$pid"
}

airlock_openconnect_running() {
  local pid
  pid="$(airlock_openconnect_pid)" || return 1
  airlock_as_root sh -c 'kill -0 "$1" 2>/dev/null' _ "$pid"
}

airlock_mountns_pid() {
  local pid

  pid="$(
    airlock_as_root sh -c '
      test -f "$1" || exit 1
      cat "$1"
    ' _ "$AIRLOCK_MOUNTNS_PIDFILE" 2>/dev/null
  )" || return 1

  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$pid"
}

airlock_mountns_all_pids() {
  #airlock_as_root sh -c 'ip netns pids "$1" 2>/dev/null || true' _ "$AIRLOCK_NAMESPACE"
  local -a pids=()
  # Read PIDs safely into an array
  mapfile -t pids < <(airlock_as_root ip netns pids "$AIRLOCK_NAMESPACE" 2>/dev/null || true)
  #((${#pids[@]})) || return 0
  airlock_log "Found processes in namespace $AIRLOCK_NAMESPACE: ${pids[*]}"
}

airlock_mountns_running() {
  local pid
  pid="$(airlock_mountns_pid)" || return 1
  airlock_as_root sh -c 'kill -0 "$1" 2>/dev/null' _ "$pid"
}

airlock_ns_exists() {
  ip netns list | awk '{print $1}' | grep -Fxq "$AIRLOCK_NAMESPACE"
}

airlock_ns_create() {
  airlock_ns_exists && return 0
  airlock_as_root ip netns add "$AIRLOCK_NAMESPACE"
  airlock_log "Created network namespace: $AIRLOCK_NAMESPACE"
}

airlock_ns_delete() {
  airlock_ns_exists || return 0
  airlock_as_root ip netns delete "$AIRLOCK_NAMESPACE"
  airlock_log "Deleted network namespace: $AIRLOCK_NAMESPACE"
}

airlock_ensure_root_dirs() {
  airlock_log "Ensuring runtime dir ($AIRLOCK_RUNTIME_DIR) and state dir ($AIRLOCK_STATE_DIR) exist with correct permissions"
  airlock_as_root install -d -m 700 "$AIRLOCK_RUNTIME_DIR"
  airlock_as_root install -d -m 700 "$AIRLOCK_STATE_DIR"
}

airlock_prepare_overlay_dirs() {
  if airlock_mountns_running; then
    airlock_die "Refusing to wipe overlay dirs while mountns helper is running"
  fi
  airlock_ensure_root_dirs
  airlock_as_root rm -rf -- "$AIRLOCK_ETC_UPPER_DIR" "$AIRLOCK_ETC_WORK_DIR"
  airlock_as_root install -d -m 700 "$AIRLOCK_ETC_UPPER_DIR" "$AIRLOCK_ETC_WORK_DIR"
}

airlock_wan_if() {
  local dev
  dev="$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") { print $(i+1); exit }}')"
  [[ -n "$dev" ]] || airlock_die 'Could not determine default egress interface'
  printf '%s\n' "$dev"
}

airlock_snapshot_sysctl() {
  airlock_ensure_root_dirs
  airlock_log "Snapshotting current sysctl value for net.ipv4.ip_forward to: $AIRLOCK_SYSCTL_SNAPSHOT"
  airlock_as_root sh -c "sysctl -n net.ipv4.ip_forward > '$AIRLOCK_SYSCTL_SNAPSHOT'"
}

airlock_restore_sysctl() {
  local prev
  airlock_log "Restoring sysctl value for net.ipv4.ip_forward from snapshot if it exists at: $AIRLOCK_SYSCTL_SNAPSHOT"
  airlock_log "Checking if sysctl snapshot file exists and is readable at: $AIRLOCK_SYSCTL_SNAPSHOT"
  # needs to run as root
  if airlock_root_isfile "$AIRLOCK_SYSCTL_SNAPSHOT"; then
    airlock_log "Snapshot file exists, reading previous value for net.ipv4.ip_forward"
    prev="$(airlock_root_cat "$AIRLOCK_SYSCTL_SNAPSHOT")"
    airlock_log "Restoring sysctl value for net.ipv4.ip_forward from snapshot: $prev"
    if [[ "$prev" =~ ^[01]$ ]]; then
      airlock_log "Setting net.ipv4.ip_forward back to $prev"
      airlock_as_root sysctl -w "net.ipv4.ip_forward=$prev" >/dev/null
    else
      airlock_log "Invalid snapshot value for net.ipv4.ip_forward: $prev - skipping restore"
    fi
    airlock_log "Removing sysctl snapshot file: $AIRLOCK_SYSCTL_SNAPSHOT"
    airlock_as_root rm -f -- "$AIRLOCK_SYSCTL_SNAPSHOT"
  fi
}

airlock_pick_fw_backend() {
  case "$AIRLOCK_FW_BACKEND" in
    nft|iptables)
      printf '%s\n' "$AIRLOCK_FW_BACKEND"
      ;;
    auto)
      if command -v nft >/dev/null 2>&1; then
        printf 'nft\n'
      elif command -v iptables >/dev/null 2>&1; then
        printf 'iptables\n'
      else
        airlock_die 'Need either nft or iptables'
      fi
      ;;
    *)
      airlock_die "Unsupported AIRLOCK_FW_BACKEND: $AIRLOCK_FW_BACKEND"
      ;;
  esac
}

airlock_fw_apply() {
  local wan backend
  wan="$(airlock_wan_if)"
  backend="$(airlock_pick_fw_backend)"
  airlock_log "Applying firewall rules for backend: $backend on WAN interface: $wan"

  airlock_ensure_root_dirs
  airlock_log "Saving WAN interface ($wan) at: $AIRLOCK_WAN_IF_FILE and firewall backend ($backend) at: $AIRLOCK_FW_BACKEND_FILE for later cleanup"
  printf '%s\n' "$wan" | airlock_as_root tee "$AIRLOCK_WAN_IF_FILE" >/dev/null
  printf '%s\n' "$backend" | airlock_as_root tee "$AIRLOCK_FW_BACKEND_FILE" >/dev/null

  airlock_snapshot_sysctl

  airlock_log "Enabling IP forwarding via sysctl"
  airlock_as_root sysctl -w net.ipv4.ip_forward=1 >/dev/null

  case "$backend" in
    nft)
      airlock_log "Setting up nftables rules in table: $AIRLOCK_NFT_TABLE"
      airlock_as_root nft delete table ip "$AIRLOCK_NFT_TABLE" 2>/dev/null || true
      airlock_as_root nft -f - <<EOF_NFT

table ip $AIRLOCK_NFT_TABLE {
  chain forward {
    type filter hook forward priority 0; policy drop;
    iifname "$AIRLOCK_VETH_HOST" oifname "$wan" accept
    iifname "$wan" oifname "$AIRLOCK_VETH_HOST" ct state established,related accept
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "$wan" ip saddr $AIRLOCK_SUBNET_CIDR masquerade
  }
}
EOF_NFT
      ;;
    iptables)
      airlock_as_root iptables -C FORWARD -i "$AIRLOCK_VETH_HOST" -o "$wan" -j ACCEPT 2>/dev/null || \
        airlock_as_root iptables -A FORWARD -i "$AIRLOCK_VETH_HOST" -o "$wan" -j ACCEPT
      airlock_as_root iptables -C FORWARD -i "$wan" -o "$AIRLOCK_VETH_HOST" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        airlock_as_root iptables -A FORWARD -i "$wan" -o "$AIRLOCK_VETH_HOST" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      airlock_as_root iptables -t nat -C POSTROUTING -s "$AIRLOCK_SUBNET_CIDR" -o "$wan" -j MASQUERADE 2>/dev/null || \
        airlock_as_root iptables -t nat -A POSTROUTING -s "$AIRLOCK_SUBNET_CIDR" -o "$wan" -j MASQUERADE
      ;;
  esac
}

airlock_fw_remove() {
  local backend wan

  airlock_log "Removing firewall rules and restoring sysctl settings if $AIRLOCK_FW_BACKEND_FILE exists"

  if ! airlock_root_isfile "$AIRLOCK_FW_BACKEND_FILE"; then
    airlock_restore_sysctl
    return 0
  fi

  backend="$(airlock_root_cat "$AIRLOCK_FW_BACKEND_FILE")"
  wan=''
  if airlock_root_isfile "$AIRLOCK_WAN_IF_FILE"; then
    wan="$(airlock_root_cat "$AIRLOCK_WAN_IF_FILE")"
  fi

  airlock_log "Removing firewall rules for backend: $backend (wan=${wan:-unknown})"

  case "$backend" in
    nft)
      airlock_as_root nft delete table ip "$AIRLOCK_NFT_TABLE" 2>/dev/null || true
      ;;
    iptables)
      if [[ -n "$wan" ]]; then
        airlock_as_root iptables -D FORWARD -i "$AIRLOCK_VETH_HOST" -o "$wan" -j ACCEPT 2>/dev/null || true
        airlock_as_root iptables -D FORWARD -i "$wan" -o "$AIRLOCK_VETH_HOST" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        airlock_as_root iptables -t nat -D POSTROUTING -s "$AIRLOCK_SUBNET_CIDR" -o "$wan" -j MASQUERADE 2>/dev/null || true
      fi
      ;;
  esac

  airlock_as_root rm -f -- "$AIRLOCK_WAN_IF_FILE" "$AIRLOCK_FW_BACKEND_FILE"
  airlock_restore_sysctl
}

airlock_ns_setup_base_network() {
  airlock_ns_create
  airlock_log "Setting up veth pair: $AIRLOCK_VETH_HOST <-> $AIRLOCK_VETH_NS"
  airlock_as_root ip link del "$AIRLOCK_VETH_HOST" 2>/dev/null || true
  airlock_as_root ip link add "$AIRLOCK_VETH_HOST" type veth peer name "$AIRLOCK_VETH_NS"
  airlock_as_root ip link set "$AIRLOCK_VETH_NS" netns "$AIRLOCK_NAMESPACE"
  airlock_log "Configuring host interface: $AIRLOCK_VETH_HOST with IP $AIRLOCK_HOST_IP_CIDR"
  airlock_as_root ip addr replace "$AIRLOCK_HOST_IP_CIDR" dev "$AIRLOCK_VETH_HOST"
  airlock_as_root ip link set "$AIRLOCK_VETH_HOST" up
  airlock_as_root ip -n "$AIRLOCK_NAMESPACE" link set lo up
  airlock_as_root ip -n "$AIRLOCK_NAMESPACE" addr replace "$AIRLOCK_NS_IP_CIDR" dev "$AIRLOCK_VETH_NS"
  airlock_as_root ip -n "$AIRLOCK_NAMESPACE" link set "$AIRLOCK_VETH_NS" up
  airlock_as_root ip -n "$AIRLOCK_NAMESPACE" route replace default via "${AIRLOCK_HOST_IP_CIDR%/*}" dev "$AIRLOCK_VETH_NS"
}

airlock_bootstrap_resolv_conf() {
  local src tmp
  if [[ -r /run/systemd/resolve/resolv.conf ]]; then
    src='/run/systemd/resolve/resolv.conf'
  elif [[ -r /etc/resolv.conf ]]; then
    src='/etc/resolv.conf'
  else
    airlock_die 'Could not find a bootstrap resolv.conf source'
  fi

  tmp='/etc/resolv.conf.airlock-tmp'
  # Using cp -L to dereference any symlink and get the actual file content,
  # then move it into place atomically
  cp -fL -- "$src" "$tmp"
  mv -f -- "$tmp" /etc/resolv.conf
  ls -la /etc/resolv.conf
}

airlock_find_false_bin() {
  local p=""
  p="$(type -P false 2>/dev/null || true)"
  if [[ -n "$p" && -x "$p" ]]; then
    printf '%s\n' "$p"
    return 0
  fi
  for p in /usr/bin/false /bin/false; do
    if [[ -x "$p" ]]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  airlock_die "Could not locate an external 'false' binary"
}

airlock_mask_resolved_tools() {
  # resolvectl called from inside a netns can effectively “escape” and modify
  # the host resolver state. To prevent this, we can bind mount a harmless
  # binary (like /bin/false) over the resolvectl and busctl binaries inside the
  # mount namespace, effectively neutering them.
  local false_bin
  #false_bin="$(command -v false)"
  false_bin="$(airlock_find_false_bin)"
  #[[ -x /usr/bin/resolvectl ]] && mount --bind "$false_bin" /usr/bin/resolvectl
  #[[ -x /usr/bin/busctl ]] && mount --bind "$false_bin" /usr/bin/busctl
  for target in /usr/bin/resolvectl /usr/bin/busctl; do
    [[ -e "$target" ]] || continue
    real="$(readlink -f "$target" 2>/dev/null || printf '%s' "$target")"
    mount --bind "$false_bin" "$real"
  done
}

airlock_mountns_child() {
  #umask 077
  umask 022
  #mkdir -p -- "$AIRLOCK_RUNTIME_DIR" "$AIRLOCK_ETC_UPPER_DIR" "$AIRLOCK_ETC_WORK_DIR"
  install -d -m 700 -- "$AIRLOCK_RUNTIME_DIR" "$AIRLOCK_ETC_UPPER_DIR" "$AIRLOCK_ETC_WORK_DIR"
  #ls -ld -- "$AIRLOCK_RUNTIME_DIR" "$AIRLOCK_ETC_UPPER_DIR" "$AIRLOCK_ETC_WORK_DIR"
  mount --make-rprivate /
  mount -t overlay overlay -o "lowerdir=/etc,upperdir=$AIRLOCK_ETC_UPPER_DIR,workdir=$AIRLOCK_ETC_WORK_DIR" /etc

  # Ensure /etc itself is traversable for non-root apps inside the namespace.
  # (Without this, you can break TLS, DNS, and many tools.)
  chmod 0755 /etc || true

  # Ensure common trust/DNS directories remain traversable too (best-effort).
  chmod 0755 /etc/ssl 2>/dev/null || true
  chmod 0755 /etc/ssl/certs 2>/dev/null || true

  airlock_bootstrap_resolv_conf
  airlock_mask_resolved_tools

  umask 077
  printf '%s\n' "$$" >"$AIRLOCK_MOUNTNS_PIDFILE"
  trap 'rm -f -- "$AIRLOCK_MOUNTNS_PIDFILE"' EXIT INT TERM
  exec sleep infinity
}

airlock_mountns_start() {
  local helper i
  helper="${AIRLOCK_LIBEXEC_DIR}/airlock/mountns-helper.sh"
  [[ -x "$helper" ]] || airlock_die "Mount namespace helper not found: $helper"

  airlock_prepare_overlay_dirs

  # Start helper inside:
  #   - the network namespace ($AIRLOCK_NAMESPACE)
  #   - a fresh mount namespace (unshare --mount)
  airlock_as_root sh -c '
    set -euo pipefail

    pidfile="$1"
    ns="$2"
    helper="$3"
    shift 3

    # $@ now contains ENV assignments like KEY=VALUE

    # Make sure we start fresh
    rm -f "$pidfile"

    # Run helper in the background
    env "$@" \
      ip netns exec "$ns" \
      unshare --mount --propagation private --fork \
      "$helper" >/dev/null 2>&1 &
  ' _ \
    "$AIRLOCK_MOUNTNS_PIDFILE" \
    "$AIRLOCK_NAMESPACE" \
    "$helper" \
    "AIRLOCK_CONFIG=$AIRLOCK_CONFIG" \
    "AIRLOCK_LIBEXEC_DIR=$AIRLOCK_LIBEXEC_DIR"

  for ((i = 0; i < 100; i++)); do
    if airlock_mountns_running; then
      return 0
    fi
    sleep 0.1
  done

  airlock_die 'Failed to start persistent mount namespace helper'
}
airlock_mountns_stop() {
  local pid=""

  if airlock_root_isfile "$AIRLOCK_MOUNTNS_PIDFILE"; then
    pid="$(airlock_root_cat "$AIRLOCK_MOUNTNS_PIDFILE" 2>/dev/null || true)"
  fi

  if [[ "$pid" =~ ^[0-9]+$ ]] && airlock_as_root sh -c 'kill -0 "$1" 2>/dev/null' _ "$pid"; then
    airlock_log "Stopping mount namespace helper with PID: $pid"
    airlock_as_root sh -c 'kill "$1" 2>/dev/null || true' _ "$pid"
    for _ in {1..30}; do
      airlock_as_root sh -c 'kill -0 "$1" 2>/dev/null' _ "$pid" || break
      sleep 0.1
    done
    airlock_as_root sh -c 'kill -KILL "$1" 2>/dev/null || true' _ "$pid"
  fi

  airlock_as_root rm -f "$AIRLOCK_MOUNTNS_PIDFILE" 2>/dev/null || true
}

airlock_nsenter() {
  local pid
  pid="$(airlock_mountns_pid)" || airlock_die 'Mount namespace helper is not running'
  #airlock_log "Entering mount namespace of helper with PID: $pid to run command: $*"
  airlock_as_root nsenter --target "$pid" --mount --net -- "$@"
}

airlock_nsenter_as_user() {
  local user="${1:?user required}"
  shift

  local helper="${AIRLOCK_LIBEXEC_DIR}/airlock/exec-with-env0.sh"
  [[ -x "$helper" ]] || airlock_die "Missing helper: $helper"

  airlock_require_cmd mkfifo rm env

  local fifo=''       # init for set -u safety
  local writer=''     # init for set -u safety
  local rc=0

  cleanup() {
    # Kill writer if still around
    if [[ -n "${writer:-}" ]]; then
      kill "$writer" 2>/dev/null || true
      wait "$writer" 2>/dev/null || true
    fi

    # Remove FIFO
    if [[ -n "${fifo:-}" ]]; then
      rm -f -- "$fifo" 2>/dev/null || true
    fi
  }
  trap cleanup RETURN

  fifo="$(mktemp -u "${XDG_RUNTIME_DIR:-/tmp}/airlock-env.${AIRLOCK_CONFIG_NAME}.XXXXXX")"
  mkfifo -m 600 "$fifo"

  ( env -0 >"$fifo" ) &
  writer="$!"

  if command -v setpriv >/dev/null 2>&1; then
    local uid gid
    uid="$(id -u "$user")" || airlock_die "Unknown user: $user"
    gid="$(id -g "$user")" || airlock_die "Unknown user: $user"

    set +e
    airlock_nsenter setpriv \
      --reuid "$uid" \
      --regid "$gid" \
      --init-groups \
      -- env AIRLOCK_ENV_FIFO="$fifo" AIRLOCK_CWD="$PWD" "$helper" "$@"
    rc=$?
    set -e
    return "$rc"
  fi

  if command -v runuser >/dev/null 2>&1; then
    set +e
    airlock_nsenter runuser -u "$user" -- env AIRLOCK_ENV_FIFO="$fifo" AIRLOCK_CWD="$PWD" "$helper" "$@"
    rc=$?
    set -e
    return "$rc"
  fi

  airlock_die "Need setpriv or runuser to drop privileges without sudo"
}

airlock_stop_openconnect() {
  local pid i

  # If we can’t read a valid pid, treat as already stopped.
  if ! pid="$(airlock_openconnect_pid)"; then
    airlock_as_root rm -f "$AIRLOCK_PIDFILE" 2>/dev/null || true
    return 0
  fi

  # If process is already gone, clean up pidfile.
  if ! airlock_as_root sh -c 'kill -0 "$1" 2>/dev/null' _ "$pid"; then
    airlock_as_root rm -f "$AIRLOCK_PIDFILE" 2>/dev/null || true
    return 0
  fi

  airlock_log "Stopping openconnect (PID $pid) ..."
  airlock_as_root sh -c 'kill "$1" 2>/dev/null || true' _ "$pid"

  # Wait up to ~5s for clean exit
  for ((i = 0; i < 50; i++)); do
    if ! airlock_as_root sh -c 'kill -0 "$1" 2>/dev/null' _ "$pid"; then
      airlock_as_root rm -f "$AIRLOCK_PIDFILE" 2>/dev/null || true
      airlock_log "openconnect stopped"
      return 0
    fi
    sleep 0.1
  done

  airlock_warn "openconnect did not exit after SIGTERM; sending SIGKILL"
  airlock_as_root sh -c 'kill -KILL "$1" 2>/dev/null || true' _ "$pid"

  # Wait a bit more for SIGKILL to take effect
  for ((i = 0; i < 20; i++)); do
    if ! airlock_as_root sh -c 'kill -0 "$1" 2>/dev/null' _ "$pid"; then
      break
    fi
    sleep 0.1
  done

  airlock_as_root rm -f "$AIRLOCK_PIDFILE" 2>/dev/null || true
  airlock_log "openconnect stopped (forced if needed)"
}

airlock_kill_ns_processes() {
  local -a pids=()

  airlock_ns_exists || return 0

  # Read PIDs safely into an array
  mapfile -t pids < <(airlock_as_root ip netns pids "$AIRLOCK_NAMESPACE" 2>/dev/null || true)
  ((${#pids[@]})) || return 0

  airlock_log "Found processes in namespace $AIRLOCK_NAMESPACE: ${pids[*]} - sending SIGTERM"
  airlock_as_root kill "${pids[@]}" 2>/dev/null || true

  sleep 0.2

  mapfile -t pids < <(airlock_as_root ip netns pids "$AIRLOCK_NAMESPACE" 2>/dev/null || true)
  airlock_log "Remaining after SIGTERM: ${pids[*]:-<none>}"

  ((${#pids[@]})) || return 0

  airlock_as_root kill -KILL "${pids[@]}" 2>/dev/null || true
}

airlock_cleanup_stale_state() {
  airlock_stop_openconnect || true
  airlock_kill_ns_processes || true
  airlock_ns_delete || true
  airlock_fw_remove || true
  airlock_as_root rm -f -- "$AIRLOCK_MOUNTNS_PIDFILE" "$AIRLOCK_PIDFILE" || true
}

airlock_teardown_stack() {
  airlock_stop_openconnect
  airlock_mountns_stop
  airlock_kill_ns_processes
  airlock_ns_delete
  airlock_fw_remove
  airlock_as_root rm -f -- "$AIRLOCK_MOUNTNS_PIDFILE" "$AIRLOCK_PIDFILE"
}
