# airlock

Run a VPN connection in an isolated Linux **network namespace + mount namespace**, and launch **only selected applications** through it — without touching your host routing table or breaking existing connections.

`airlock` is designed for the “I want one browser / one command to go through the VPN, not my whole machine” workflow.

## Features

- **Per-application VPN routing** using Linux network namespaces
- **DNS isolation** using a persistent mount namespace with an overlay on `/etc`
- `airlock up` / `airlock run -- …` / `airlock down` lifecycle
- Config-driven authentication (no hard dependency on `pass`)
- Works with **OpenConnect** (AnyConnect-compatible VPNs)


## Requirements

- Linux with: `ip` (iproute2), `nsenter`, `unshare`, `sudo`
- VPN driver: `openconnect`
- Firewall backend: `nft` or `iptables`
- Optional but common: `systemd-resolved` (handled)


## Installation

From the repo:

```sh
make
sudo make install
```

Uninstall:

```sj
sudo make uninstall
```


## Quick start:

### 1) Create a config

Configs can live in:

- `$XDG_CONFIG_HOME/airlock/<name>.conf` (usually `~/.config/airlock/<name>.conf`)
- `/etc/airlock/<name>.conf`

See section [Configuration overview](#configuration-overview) for details.

### 2) Bring the VPN up

```sh
airlock --profile <name> up
```

### 3) Run applications through the VPN

```sh
airlock --profile <name> run -- curl -sS https://api.ipify.org
```

### 4) Tear down the VPN

```sh
airlock --profile <name> down
```


## Default profile

If you create:

```
~/.config/airlock/default.conf
```

then you can omit `--profile default` from all commands, and it will be used by default:

```sh
airlock up
airlock run -- curl -sS https://api.ipify.org
airlock down
```

You can also set one of these environment variables to specify a different default profile:
- `AIRLOCK_DEFAULT_PROFILE=<name>`
- `AIRLOCK_DEFAULT_CONFIG=<path/to/config>`


## `airlock-firefox` wrapper

`airlock-firefox` is a simple wrapper around `airlock run -- firefox` that passes some extra arguments to Firefox to

1. ensure the VPN is up (runs `airlock up` if needed)
2. launches Firefox with a custom profile by default

### Separate Firefox profile (recommended)

By default, `airlock-firefox` uses a dedicated Firefox profile and forces private browsing.

- Dedicated profile avoids cross-contamination with your main profile
- `-no-remote` allows running alongside your normal Firefox instance

### Temporary profile (auto-clean)

Create a fresh profile directory and delete it after Firefox exits:

```sh
airlock-firefox --temp-profile
```

### Clean profile directory

Delete the configured profile directory (refuses if it appears in use):

```sh
airlock-firefox --clean-profile
```


## Testing "does this actually go through the VPN?"

### Compare public IP (host vs airlock)

```bash
curl -sS https://api.ipify.org; echo
airlock run -- curl -sS https://api.ipify.org; echo
```

### Check routes inside the namespace

```bash
airlock run -- ip route
airlock run -- ip route get 1.1.1.1
```

If the VPN is active, default routing should go via the VPN interface inside the namespace.


## Configuration overview

A config file is just a shell script that sets variables and defines one auth function.

Minimal required variables for OpenConnect:

- `OPENCONNECT_SERVER`
- `OPENCONNECT_USER`
- `AIRLOCK_AUTH_FUNCTION` (name of a function you define)

Example pattern:

```bash
OPENCONNECT_SERVER="vpn.example.com"
OPENCONNECT_USER="alice"
AIRLOCK_AUTH_FUNCTION='my_auth_payload'

my_auth_payload() {
  local otp pw
  read -r -s -p "OTP: " otp < /dev/tty
  echo >&2
  pw="your-password-source-here"
  printf '%s\n%s\n' "$pw" "$otp"
}
```

Notes:
- The auth function must write the payload to stdout
- It should read prompts from `/dev/tty`, because stdout may be piped/redirected
- You can fetch the password from anywhere (prompt, keyring, `pass`, etc)



## How it works

At a high level:

1. `airlock up`
    * creates a network namespace
    * creates a veth pair + NAT so the namespace can reach the internet
    * starts a persistent helper inside:
        - the network namespace, and
        - a new mount namespace where `/etc` is overlaid
    * runs `openconnect` inside that namespace so routes/DNS changes stay contained
2. `airlock run -- <cmd>`
    * enters the helper’s network + mount namespace via `nsenter`
    * drops privileges to the calling user
    * executes the command in the isolated environment
3. `airlock down`
    * stops `openconnect`
    * kills remaining processes in the namespace
    * removes NAT rules and restores sysctl state
    * deletes the namespace


## Security notes

- `airlock` refuses to run as root. It uses `sudo` internally only where required.
- Auth payload is handled in-memory (no temp files by default).
- The mount namespace design prevents common “DNS leakage” pitfalls on systemd-resolved systems.


## Inspiration / credit

This project is heavily inspired by:

- `nsdo` - a practical tool for running commands in namespaces, and especially its approach to dealing with `/etc/resolv.conf` via mount namespace tricks: https://github.com/ausbin/nsdo
- socketbox gist - a concise reference implementation of netns + veth + NAT + VPN patterns: https://gist.github.com/socketbox/929378a16b43ed9026a226eb25fabe18

Thanks to those projects for documenting and demonstrating these patterns.


## Disclaimer

- This project was almost entirely vibe-coded using ChatGPT 5.2 Thinking Mode, with some manual cleanup and testing. It’s possible there are security issues or bugs that I’m not aware of.
- Use at your own risk
