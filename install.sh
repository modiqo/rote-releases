#!/bin/bash
# Binary bootstrap only. Native `rote install setup` owns all setup and reporting.
# Checksums from the artifact host guard corruption, not independent provenance.
set -e
set -o pipefail
INSTALL_DIR="${ROTE_BIN:-${ROTE_INSTALL_DIR:-$HOME/.local/bin}}"
ROTE_HOME="${ROTE_HOME:-$HOME/.rote}"
VERSION="${ROTE_VERSION:-latest}"
RELEASES_BASE_URL="${ROTE_RELEASES_BASE_URL:-https://releases.getrote.dev}"
RELEASES_BASE_URL="${RELEASES_BASE_URL%/}"
CURL_STALL_OPTS=(--connect-timeout 10 --speed-limit 1024 --speed-time 20)
RESET_INSTALL="${ROTE_RESET:-}"
AUTO_YES="${ROTE_YES:-}"
for arg in "$@"; do
    case "$arg" in
        --reset) RESET_INSTALL=1 ;;
        --yes|-y) AUTO_YES=1 ;;
    esac
done
mkdir -p "$ROTE_HOME/log" "$INSTALL_DIR"
INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd -P)
ROTE_HOME=$(cd "$ROTE_HOME" && pwd -P)
LOG_FILE="$ROTE_HOME/log/install.log"
STATE_FILE="$ROTE_HOME/log/install.state"
[ -z "$RESET_INSTALL" ] || rm -f "$STATE_FILE"
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }
status() { printf '%s\n' "$*" >&2; log "$*"; }
fail() { status "$* See $LOG_FILE"; exit 1; }
step_done() { [ -f "$STATE_FILE" ] && grep -qx "$1=ok" "$STATE_FILE"; }
mark_done() { step_done "$1" || printf '%s=ok\n' "$1" >> "$STATE_FILE"; }
json_escape() {
    local text="$1"
    text="${text//\\/\\\\}"; text="${text//\"/\\\"}"
    text="${text//$'\n'/\\n}"; text="${text//$'\r'/\\r}"; text="${text//$'\t'/\\t}"
    printf '%s' "$text"
}
record_install_marker() {
    local marker_tmp
    mkdir -p "$ROTE_HOME/state"
    marker_tmp=$(mktemp "$ROTE_HOME/state/install.json.XXXXXX")
    printf '{ "method": "script", "bin": "%s" }\n' "$(json_escape "$INSTALL_DIR/rote")" > "$marker_tmp"
    mv "$marker_tmp" "$ROTE_HOME/state/install.json"
}
verify_sha256() {
    local expected actual
    local hasher=()
    if command -v sha256sum >/dev/null 2>&1; then hasher=(sha256sum)
    elif command -v shasum >/dev/null 2>&1; then hasher=(shasum -a 256)
    else log 'no sha256 tool available'; return 1; fi
    expected=$(curl -fsSL "${CURL_STALL_OPTS[@]}" "$2" 2>>"$LOG_FILE" | awk '{print $1}') || return 1
    [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { log 'invalid or missing checksum'; return 1; }
    actual=$("${hasher[@]}" "$1" | awk '{print $1}') || return 1
    [ "$expected" = "$actual" ] || { log "checksum mismatch: expected $expected, got $actual"; return 1; }
}
main() {
    local os arch artifact url tag tmp_dir archive attempt reason previous observed
    os=$(uname -s); arch=$(uname -m)
    case "$os" in Linux) os=linux ;; Darwin) os=macos ;; *) fail "Unsupported OS: $os." ;; esac
    case "$arch" in x86_64|amd64) arch=x86_64 ;; arm64|aarch64) arch=aarch64 ;; *) fail "Unsupported architecture: $arch." ;; esac
    artifact="rote-$os-$arch"
    [ "$os" != linux ] || artifact="$artifact-musl"
    if [ "$VERSION" = latest ]; then
        status 'Resolving latest Rote release...'
        url=$(curl -fsSLI --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' https://github.com/modiqo/rote-releases/releases/latest 2>>"$LOG_FILE") || fail 'Failed to resolve the release version.'
        case "$url" in */releases/tag/*) tag="${url##*/tag/}"; VERSION="${tag#v}" ;; *) fail 'Failed to resolve the release version.' ;; esac
    fi
    case "$VERSION" in ''|*/*) fail 'Invalid release version.' ;; esac
    previous=$("$INSTALL_DIR/rote" --version 2>>"$LOG_FILE") || previous=''
    previous="${previous#rote }"
    if ! step_done install || [ "$previous" != "$VERSION" ]; then
        if [ -f "$STATE_FILE" ]; then
            grep -v -e '^install=ok$' -e '^sdk=ok$' -e '^stdio=ok$' "$STATE_FILE" > "$STATE_FILE.tmp" || true
            mv "$STATE_FILE.tmp" "$STATE_FILE"
        fi
        tmp_dir=$(mktemp -d)
        trap 'rm -rf "$tmp_dir"' EXIT
        archive="$tmp_dir/rote.tar.gz"
        url="$RELEASES_BASE_URL/v$VERSION/$artifact.tar.gz"
        attempt=1
        while true; do
            status "Fetching Rote v$VERSION (attempt $attempt/5)..."
            rm -f "$archive"
            reason='Download failed'
            if curl -fsSL "${CURL_STALL_OPTS[@]}" "$url" -o "$archive" >>"$LOG_FILE" 2>&1; then
                reason='Checksum verification failed'
                if verify_sha256 "$archive" "$url.sha256"; then break; fi
            fi
            [ "$attempt" -lt 5 ] || fail "$reason after 5 attempts."
            status "$reason; retrying with a fresh download."
            sleep "$((attempt * 2))"
            attempt=$((attempt + 1))
        done
        tar xzf "$archive" -C "$tmp_dir" >>"$LOG_FILE" 2>&1 || fail 'Extraction failed.'
        [ -f "$tmp_dir/rote" ] || fail 'Archive contains no Rote binary.'
        chmod +x "$tmp_dir/rote"
        mv "$tmp_dir/rote" "$INSTALL_DIR/rote"
        if [ -f "$tmp_dir/rote-stdio-daemon" ]; then
            chmod +x "$tmp_dir/rote-stdio-daemon"
            mv "$tmp_dir/rote-stdio-daemon" "$INSTALL_DIR/rote-stdio-daemon"
        fi
        rm -rf "$tmp_dir"
        trap - EXIT
    fi
    observed=$("$INSTALL_DIR/rote" --version 2>>"$LOG_FILE") || fail 'No working Rote binary after installation.'
    [ -n "$observed" ] || fail 'No working Rote binary after installation.'
    record_install_marker || fail 'Failed to record installation marker.'
    mark_done install
    export ROTE_BOOTSTRAP=1 ROTE_BOOTSTRAP_PREVIOUS_VERSION="$previous"
    export ROTE_BIN="$INSTALL_DIR" ROTE_HOME
    export ROTE_BOOTSTRAP_ORIGINAL_PATH="$PATH"
    case ":$PATH:" in *":$INSTALL_DIR:"*) ;; *) export PATH="$INSTALL_DIR:$PATH" ;; esac
    log "Handing off to $INSTALL_DIR/rote install setup"
    if [ -z "$AUTO_YES" ]; then
        if [ -t 0 ]; then exec "$INSTALL_DIR/rote" install setup "$@"; fi
        if { : </dev/tty; } 2>/dev/null; then exec "$INSTALL_DIR/rote" install setup "$@" </dev/tty; fi
    fi
    exec "$INSTALL_DIR/rote" install setup "$@" </dev/null
}
main "$@"
