#!/bin/bash
# Binary bootstrap only. Native `rote install setup` owns all setup and reporting.
# Checksums from the artifact host guard corruption, not independent provenance.
# On a first install into a ROTE_HOME, `rote __install-ci-opt-out` disables
# auto-update when CI is set and preferences do not already choose; a pipeline
# that reuses a home can set ROTE_NO_AUTO_UPDATE=1.
set -e
set -o pipefail
INSTALL_DIR="${ROTE_BIN:-${ROTE_INSTALL_DIR:-$HOME/.local/bin}}"
ROTE_HOME="${ROTE_HOME:-$HOME/.rote}"
# Captured before record_install_marker writes the marker: the CI auto-update opt-out
# applies only to a first install, so agent shells that export CI and rerun
# the installer on a dev machine never silently opt the user out.
FIRST_INSTALL=""
[ -e "$ROTE_HOME/state/install.json" ] || FIRST_INSTALL="1"
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
# SHA-256 of the binary this script installed. A same-version binary from
# anywhere else (a local build, another installer) is not reused.
BINARY_SHA_FILE="$ROTE_HOME/log/install.sha256"
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
# CI runners should stay on the version they installed. The runtime no longer
# reads CI (agent harnesses export it on dev machines), so opt out here: on a
# first install, or on a reinstall after a first install could not get an
# answer (an I/O failure, or a pinned older binary without the command).
# The binary owns the CI truthiness rule and the preferences parsing.
disable_auto_update_on_ci() {
    local outcome
    local pending="$ROTE_HOME/state/ci-opt-out.pending"
    [ -n "$FIRST_INSTALL" ] || [ -e "$pending" ] || return 0
    outcome=$(ROTE_HOME="$ROTE_HOME" "$INSTALL_DIR/rote" __install-ci-opt-out 2>>"$LOG_FILE") || outcome=''
    case "$outcome" in
        disabled) status 'Auto-update disabled because CI is set; re-enable with `rote update auto enable`.' ;;
        kept) log 'CI is set; keeping the existing self_update preference' ;;
        not-ci) ;;
        *)
            log "CI auto-update opt-out unavailable (output: ${outcome:-none}); retrying on the next install"
            : > "$pending" 2>/dev/null || log "could not record $pending"
            return 0
            ;;
    esac
    rm -f "$pending"
}
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else log 'no sha256 tool available'; return 1; fi
}
verify_sha256() {
    local expected actual
    expected=$(curl -fsSL "${CURL_STALL_OPTS[@]}" "$2" 2>>"$LOG_FILE" | awk '{print $1}') || return 1
    [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { log 'invalid or missing checksum'; return 1; }
    actual=$(sha256_of "$1") || return 1
    [ "$expected" = "$actual" ] || { log "checksum mismatch: expected $expected, got $actual"; return 1; }
}
main() {
    local os arch artifact url tag tmp_dir archive attempt reason previous observed installed_sha
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
    installed_sha=$(sha256_of "$INSTALL_DIR/rote" 2>>"$LOG_FILE") || installed_sha=''
    if [ -n "$installed_sha" ] && [ "$installed_sha" != "$(cat "$BINARY_SHA_FILE" 2>/dev/null)" ]; then
        log "$INSTALL_DIR/rote is not the binary this script installed; reinstalling"
        installed_sha=''
    fi
    if ! step_done install || [ "$previous" != "$VERSION" ] || [ -z "$installed_sha" ]; then
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
        for helper in rote-stdio-daemon rote-code-supervisor; do
            if [ -f "$tmp_dir/$helper" ]; then
                chmod +x "$tmp_dir/$helper"
                mv "$tmp_dir/$helper" "$INSTALL_DIR/$helper"
            fi
        done
        mv "$tmp_dir/rote" "$INSTALL_DIR/rote"
        sha256_of "$INSTALL_DIR/rote" > "$BINARY_SHA_FILE" || fail 'Failed to record the installed binary checksum.'
        rm -rf "$tmp_dir"
        trap - EXIT
    fi
    observed=$("$INSTALL_DIR/rote" --version 2>>"$LOG_FILE") || fail 'No working Rote binary after installation.'
    [ -n "$observed" ] || fail 'No working Rote binary after installation.'
    record_install_marker || fail 'Failed to record installation marker.'
    mark_done install
    disable_auto_update_on_ci
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
