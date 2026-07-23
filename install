#!/bin/bash
set -e

# rote installer — Time to Agent™
# Usage: curl -fsSL https://raw.githubusercontent.com/modiqo/rote-releases/main/install.sh | bash
# Piped installs still prompt through /dev/tty when a prompt TTY is available.

# Configuration
REPO="modiqo/rote-releases"
# ROTE_BIN is preferred; ROTE_INSTALL_DIR kept as legacy alias.
INSTALL_DIR="${ROTE_BIN:-${ROTE_INSTALL_DIR:-$HOME/.local/bin}}"
# ROTE_HOME holds runtime state (logs, bundled runtimes, shell init).
ROTE_HOME="${ROTE_HOME:-$HOME/.rote}"
VERSION="${ROTE_VERSION:-latest}"
# ROTE_RELEASES_BASE_URL overrides the release artifact host (mirror/staging/tests).
RELEASES_BASE_URL="${ROTE_RELEASES_BASE_URL:-https://releases.getrote.dev}"
RELEASES_BASE_URL="${RELEASES_BASE_URL%/}"
AUTO_YES="${ROTE_YES:-}"
RESET_INSTALL="${ROTE_RESET:-}"
FULL_INSTALL="${ROTE_FULL:-}"
FULL_INSTALL_EXPLICIT=""
[ -n "$FULL_INSTALL" ] && FULL_INSTALL_EXPLICIT="1"
SKIP_BROWSER="${ROTE_SKIP_BROWSER:-}"
# --bare skips post-install runtime setup (node/deno/stdio/sdk/shell/browser).
BARE_INSTALL=""
SETUP_SKILL_PATH=""
SETUP_SKILL_STATUS=""
SETUP_ENTRYPOINT="rote-setup/SKILL.md"
INSTALL_NONINTERACTIVE=""
INSTALL_PROFILE_DEFAULTED=""
FULL_SETUP_UNSUPPORTED=""

# Parse --reset / --full flags
for arg in "$@"; do
    case "$arg" in
        --reset) RESET_INSTALL="1" ;;
        --full)  FULL_INSTALL="1"; FULL_INSTALL_EXPLICIT="1" ;;
        --bare)  BARE_INSTALL="1" ;;
    esac
done

# ─── Log setup ───────────────────────────────────────────────────────────────
LOG_DIR="$ROTE_HOME/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"
STATE_FILE="$LOG_DIR/install.state"
BG_DIR=$(mktemp -d /tmp/rote_bg.XXXXXX)

# Reset clears the checkpoint ledger so all steps re-run
if [ -n "$RESET_INSTALL" ]; then
    rm -f "$STATE_FILE"
fi

: > "$LOG_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# ─── Checkpoint ledger ───────────────────────────────────────────────────────
# Each completed step is recorded as a line "step_name=ok" in STATE_FILE.
# On re-run, steps that already have a checkpoint are skipped automatically.

step_done() {
    [ -f "$STATE_FILE" ] && grep -qx "$1=ok" "$STATE_FILE" 2>/dev/null
}

mark_done() {
    echo "$1=ok" >> "$STATE_FILE"
    log "checkpoint: $1=ok"
}

# Restore cursor and remove per-run background job scratch files on exit.
trap 'printf "\033[?25h" >&2; [ -n "${BG_DIR:-}" ] && rm -rf "$BG_DIR"' EXIT

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Global timer ────────────────────────────────────────────────────────────
INSTALL_START=$(date +%s)
STEP_COUNT=0
COMPLETED_STEPS=()
FAILED_STEPS=()

elapsed() {
    local now=$(date +%s)
    local secs=$((now - INSTALL_START))
    printf "%02d:%02d" $((secs / 60)) $((secs % 60))
}

# ─── Progress engine ────────────────────────────────────────────────────────
#
# Single overwrite line with live timer. Runs command in background,
# spinner in foreground. No per-step output — just one line that
# keeps replacing itself.
#
# Usage: progress "phase" "message" command arg1 arg2
# Returns: exit code of command. Stdout in $PROGRESS_STDOUT.

progress() {
    local phase="$1"; shift
    local message="$1"; shift
    # "$@" is the command

    local out_file=$(mktemp /tmp/rote_out.XXXXXX)
    local spinner_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

    # Run command in background
    "$@" > "$out_file" 2>>"$LOG_FILE" &
    local cmd_pid=$!
    local i=0

    # Hide cursor
    printf "\033[?25h\033[?25l" >&2

    while kill -0 "$cmd_pid" 2>/dev/null; do
        local frame="${spinner_frames[$((i % ${#spinner_frames[@]}))]}"
        printf "\r  ${CYAN}%s${NC} ${DIM}%s${NC}  %-10s ${DIM}%s${NC}\033[K" \
            "$frame" "$(elapsed)" "$phase" "$message" >&2
        sleep 0.08
        i=$((i + 1))
    done

    local rc=0
    wait "$cmd_pid" 2>/dev/null || rc=$?
    PROGRESS_STDOUT=$(cat "$out_file" 2>/dev/null)
    rm -f "$out_file"

    # Restore cursor
    printf "\033[?25h" >&2

    STEP_COUNT=$((STEP_COUNT + 1))

    if [ "$rc" = "0" ]; then
        COMPLETED_STEPS+=("$phase")
        mark_done "$phase"
        log "✓ [$phase] $message"
        # Show brief success — gets overwritten by next step
        printf "\r  ${GREEN}●${NC} ${DIM}%s${NC}  %-10s %s\033[K" \
            "$(elapsed)" "$phase" "$message" >&2
    else
        FAILED_STEPS+=("$phase · $message")
        log "✗ [$phase] $message (exit $rc)"
        printf "\r  ${RED}✗${NC} ${DIM}%s${NC}  %-10s %s\033[K" \
            "$(elapsed)" "$phase" "$message" >&2
    fi

    return "$rc"
}

# Instant step (no command to run)
progress_ok() {
    STEP_COUNT=$((STEP_COUNT + 1))
    COMPLETED_STEPS+=("$1")
    mark_done "$1"
    log "✓ [$1] $2"
    printf "\r  ${GREEN}●${NC} ${DIM}%s${NC}  %-10s %s\033[K" \
        "$(elapsed)" "$1" "$2" >&2
}

forget_last_failed_step() {
    local last=$((${#FAILED_STEPS[@]} - 1))
    if [ "$last" -ge 0 ]; then
        unset 'FAILED_STEPS[$last]'
        FAILED_STEPS=("${FAILED_STEPS[@]}")
        STEP_COUNT=$((STEP_COUNT - 1))
    fi
}

forget_last_completed_step() {
    local phase="$1"
    local last=$((${#COMPLETED_STEPS[@]} - 1))
    if [ "$last" -ge 0 ] && [ "${COMPLETED_STEPS[$last]}" = "$phase" ]; then
        unset 'COMPLETED_STEPS[$last]'
        COMPLETED_STEPS=("${COMPLETED_STEPS[@]}")
        STEP_COUNT=$((STEP_COUNT - 1))
    fi
}

# Clear the progress line before interactive prompts
progress_clear() {
    printf "\r\033[K" >&2
}

# ─── Background job tracking ─────────────────────────────────────────────────
#
# Jobs started with bg_start run silently. bg_collect waits for them,
# records the result, and prints a single status line. This lets multiple
# downloads overlap while the foreground spinner covers the longest one.
#
# bg_start "phase" "message" command [args...]
#   Forks the command, writes pid/meta to per-install scratch files.
#
# bg_collect "phase"
#   Waits for the job, prints ● or ✗, returns exit code of the job.

bg_start() {
    local phase="$1"; shift
    local message="$1"; shift
    local pid_file="$BG_DIR/${phase}.pid"
    local out_file="$BG_DIR/${phase}.out"
    local err_file="$BG_DIR/${phase}.err"
    local msg_file="$BG_DIR/${phase}.msg"

    echo "$message" > "$msg_file"
    log "→ [bg:$phase] starting: $*"

    "$@" > "$out_file" 2>"$err_file" &
    echo $! > "$pid_file"
}

bg_collect() {
    local phase="$1"
    local pid_file="$BG_DIR/${phase}.pid"
    local out_file="$BG_DIR/${phase}.out"
    local err_file="$BG_DIR/${phase}.err"
    local msg_file="$BG_DIR/${phase}.msg"

    local pid message rc=0
    pid=$(cat "$pid_file" 2>/dev/null || echo "")
    message=$(cat "$msg_file" 2>/dev/null || echo "$phase")

    if [ -n "$pid" ]; then
        wait "$pid" 2>/dev/null || rc=$?
    fi

    STEP_COUNT=$((STEP_COUNT + 1))

    if [ "$rc" = "0" ]; then
        COMPLETED_STEPS+=("$phase")
        mark_done "$phase"
        log "✓ [bg:$phase] $message"
        printf "\r  ${GREEN}●${NC} ${DIM}%s${NC}  %-10s %s\033[K" \
            "$(elapsed)" "$phase" "$message" >&2
    else
        FAILED_STEPS+=("$phase · $message")
        log "✗ [bg:$phase] $message (exit $rc)"
        if [ -s "$out_file" ]; then
            log "stdout [bg:$phase]:"
            cat "$out_file" >> "$LOG_FILE"
        fi
        if [ -s "$err_file" ]; then
            log "stderr [bg:$phase]:"
            cat "$err_file" >> "$LOG_FILE"
        fi
        printf "\r  ${RED}✗${NC} ${DIM}%s${NC}  %-10s %s\033[K" \
            "$(elapsed)" "$phase" "$message" >&2
    fi

    rm -f "$pid_file" "$out_file" "$err_file" "$msg_file"

    return "$rc"
}

# ─── Read user input (works in curl | bash) ──────────────────────────────────
prompt_user() {
    if [ -t 0 ]; then
        read -r "$@"
    else
        read -r "$@" </dev/tty
    fi
}

has_prompt_tty() {
    if [ -t 0 ]; then
        return 0
    fi
    [ -e /dev/tty ] || return 1
    { : </dev/tty >/dev/tty; } 2>/dev/null
}

install_is_noninteractive() {
    if [ -n "$AUTO_YES" ]; then
        return 0
    fi
    if has_prompt_tty; then
        return 1
    fi
    return 0
}

# ─── Legacy rc cleanup ───────────────────────────────────────────────────────
# Strip stale `# rote completion` + `eval "$(rote completion …)"` blocks left
# behind by older installers. Mirrors `clean_legacy_completion` in
# crates/rote-cli/src/cli/shell/generator.rs:282-316. Runs from main() so
# --bare installs still get the cleanup. Keep patterns in sync with
# `legacy_patterns` there.
clean_legacy_completion() {
    for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
        [ -f "$f" ] && [ -w "$f" ] || continue
        grep -Fxq -e '# rote completion' \
                  -e 'eval "$(rote completion bash)"' \
                  -e 'eval "$(rote completion zsh)"' "$f" 2>/dev/null || continue
        tmp=$(mktemp) || continue
        if grep -Fxv -e '# rote completion' \
                     -e 'eval "$(rote completion bash)"' \
                     -e 'eval "$(rote completion zsh)"' "$f" > "$tmp" 2>/dev/null; then
            # cat > preserves inode/mode/owner and survives symlinks (e.g.
            # ~/.zshrc → ~/dotfiles/zshrc). `mv` would replace the symlink.
            cat "$tmp" > "$f"
        fi
        rm -f "$tmp"
    done
}

# ─── Shell detection ─────────────────────────────────────────────────────────
detect_shell_config() {
    case "$SHELL" in
        */zsh) echo "$HOME/.zshrc" ;;
        */bash)
            if [ -f "$HOME/.bashrc" ]; then echo "$HOME/.bashrc"
            else echo "$HOME/.bash_profile"; fi
            ;;
        *) echo "" ;;
    esac
}

shell_setup_supported() {
    case "$SHELL" in
        */zsh|*/bash) return 0 ;;
        *) return 1 ;;
    esac
}

shell_display_name() {
    local shell_name="${SHELL##*/}"
    case "$shell_name" in
        fish) echo "Fish" ;;
        "") echo "unknown shell" ;;
        *) echo "$shell_name" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# Detect platform
# ═══════════════════════════════════════════════════════════════════════════════
detect_platform() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)

    case "$os" in
        linux)   OS="linux" ;;
        darwin)  OS="macos" ;;
        *)
            printf "\r  ${RED}✗${NC}  detect     Unsupported OS: %s\n" "$os" >&2
            exit 1 ;;
    esac

    case "$arch" in
        x86_64 | amd64)  ARCH="x86_64" ;;
        aarch64 | arm64) ARCH="aarch64" ;;
        *)
            printf "\r  ${RED}✗${NC}  detect     Unsupported arch: %s\n" "$arch" >&2
            exit 1 ;;
    esac

    case "$OS-$ARCH" in
        linux-x86_64)   ARTIFACT="rote-linux-x86_64-musl";  ARCHIVE_EXT="tar.gz" ;;
        linux-aarch64)  ARTIFACT="rote-linux-aarch64-musl";  ARCHIVE_EXT="tar.gz" ;;
        macos-x86_64)   ARTIFACT="rote-macos-x86_64";       ARCHIVE_EXT="tar.gz" ;;
        macos-aarch64)  ARTIFACT="rote-macos-aarch64";       ARCHIVE_EXT="tar.gz" ;;
        *)
            printf "\r  ${RED}✗${NC}  detect     No binary for %s\n" "$OS-$ARCH" >&2
            exit 1 ;;
    esac

    PLATFORM_LABEL="$OS-$ARCH"
    log "Platform: $PLATFORM_LABEL, Artifact: $ARTIFACT"
}

os_release_value() {
    local key="$1"
    local file="$2"
    local value
    value=$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file" 2>/dev/null || true)
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}

detect_full_setup_capability() {
    local capability_os="$OS"
    local capability_arch="$ARCH"
    local release_file="/etc/os-release"
    local macos_version=""
    if [ "${ROTE_TEST_HARNESS:-}" = "install-platform-fixtures-v1" ]; then
        capability_os="${ROTE_TEST_PLATFORM_OS:-$capability_os}"
        capability_arch="${ROTE_TEST_PLATFORM_ARCH:-$capability_arch}"
        release_file="${ROTE_TEST_OS_RELEASE_FILE:-$release_file}"
        macos_version="${ROTE_TEST_MACOS_VERSION:-}"
    fi
    FULL_SETUP_SUPPORTED=""
    FULL_SETUP_UNSUPPORTED=""
    FULL_SETUP_HOST="$capability_os"

    case "$capability_arch" in
        x86_64|aarch64) ;;
        *)
            FULL_SETUP_HOST="architecture '$capability_arch'"
            return
            ;;
    esac

    case "$capability_os" in
        macos)
            if [ "${ROTE_TEST_HARNESS:-}" != "install-platform-fixtures-v1" ]; then
                macos_version=$(sw_vers -productVersion 2>/dev/null || true)
            fi
            if [ -z "$macos_version" ]; then
                FULL_SETUP_HOST="unknown macOS version"
                return
            fi
            local macos_major="${macos_version%%.*}"
            case "$macos_major" in
                ''|*[!0-9]*|0|1|2|3|4|5|6|7|8|9|10|11|12|13)
                    FULL_SETUP_HOST="macOS $macos_version"
                    return
                    ;;
                *) FULL_SETUP_SUPPORTED="1" ;;
            esac
            return
            ;;
        linux) ;;
        *) return ;;
    esac

    if [ ! -r "$release_file" ]; then
        FULL_SETUP_HOST="unknown Linux distribution"
        return
    fi

    local distro_id distro_version
    distro_id=$(os_release_value ID "$release_file")
    distro_version=$(os_release_value VERSION_ID "$release_file")
    FULL_SETUP_HOST="Linux distribution '${distro_id:-unknown}${distro_version:+ $distro_version}'"

    case "$distro_id" in
        ubuntu)
            case "$distro_version" in
                22.04|24.04|26.04) FULL_SETUP_SUPPORTED="1" ;;
            esac
            return
            ;;
        debian)
            case "$distro_version" in
                12|13) FULL_SETUP_SUPPORTED="1" ;;
            esac
            return
            ;;
    esac
}

print_unsupported_full_guidance() {
    printf "  ${YELLOW}!${NC} %s does not support local Full browser setup.\n" "$FULL_SETUP_HOST" >&2
    printf "    rote local Full supports macOS 14+ and exact Debian 12/13 or Ubuntu 22.04/24.04/26.04 hosts on x86-64 or arm64.\n" >&2
    printf "    Playwright upstream supports additional hosts, but rote cannot safely install its managed local runtime here.\n" >&2
    printf "    Use this CLI-only install, or run ${GREEN}rote setup --full${NC} on a supported browser host and use that host for browser work.\n" >&2
}

print_browser_skipped_guidance() {
    local binary_path="$1"
    if [ -n "$FULL_SETUP_UNSUPPORTED" ]; then
        printf "  Use a supported browser host for browser work; run rote setup --full on that host.\n" >&2
    else
        printf "  Complete it later: \"%s\" setup --full\n" "$binary_path" >&2
    fi
}

binary_supports_full_setup() {
    local binary_path="$1"
    local help_output

    if help_output=$("$binary_path" setup --help 2>&1); then
        if printf '%s\n' "$help_output" | grep -Eq '^[[:space:]]*--full([[:space:]]{2,}|$)'; then
            return 0
        fi
    fi

    if help_output=$("$binary_path" help setup 2>&1); then
        if printf '%s\n' "$help_output" | grep -Eq '^[[:space:]]*--full([[:space:]]{2,}|$)'; then
            return 0
        fi
    fi

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Select the standard installation profile
# ═══════════════════════════════════════════════════════════════════════════════
validate_install_profile() {
    if [ -n "$FULL_INSTALL" ] && [ -n "$SKIP_BROWSER" ]; then
        printf "  ${RED}✗${NC} ROTE_FULL and ROTE_SKIP_BROWSER cannot both be set\n" >&2
        return 1
    fi
}

apply_platform_install_profile() {
    if [ -n "$FULL_SETUP_SUPPORTED" ]; then
        return
    fi
    FULL_SETUP_UNSUPPORTED="1"
    if [ -n "$FULL_INSTALL_EXPLICIT" ]; then
        printf "  ${RED}✗${NC} Full browser setup is unavailable on %s.\n" "$FULL_SETUP_HOST" >&2
        printf "    rote local Full supports macOS 14+ and exact Debian 12/13 or Ubuntu 22.04/24.04/26.04 hosts on x86-64 or arm64.\n" >&2
        printf "    Playwright upstream supports additional hosts, but rote cannot safely install its managed local runtime here.\n" >&2
        printf "    No release was downloaded and no browser runtime changes were made.\n" >&2
        printf "    Re-run this installer with ${GREEN}ROTE_SKIP_BROWSER=1${NC}, or use ${GREEN}rote setup --full${NC} on a supported browser host.\n" >&2
        return 1
    fi

    print_unsupported_full_guidance
    if [ -z "$SKIP_BROWSER" ]; then
        SKIP_BROWSER="1"
        INSTALL_PROFILE_DEFAULTED="cli-only-unsupported"
        log "local browser setup unsupported; selecting CLI-only installation"
    fi
}

collect_install_profile() {
    if [ -n "$FULL_INSTALL" ] || [ -n "$SKIP_BROWSER" ]; then
        return
    fi

    if [ -n "$AUTO_YES" ] || ! has_prompt_tty; then
        FULL_INSTALL="1"
        INSTALL_PROFILE_DEFAULTED="1"
        log "non-interactive install detected; defaulting to full installation"
        return
    fi

    echo "" >&2
    printf "  ${BOLD}Browser automation${NC} enables rote-browse and full browser workflows.\n" >&2
    echo "" >&2

    while true; do
        local browser_choice=""
        printf "  ${CYAN}?${NC} Install browser automation? ${DIM}[Y/n]${NC}: " >&2
        prompt_user browser_choice || browser_choice=""
        case "$browser_choice" in
            ""|y|Y|yes|Yes|YES)
                FULL_INSTALL="1"
                printf "  ${GREEN}✓${NC} Installing the CLI with browser automation.\n" >&2
                return
                ;;
            n|N|no|No|NO)
                SKIP_BROWSER="1"
                printf "  ${GREEN}✓${NC} Installing the CLI only. Add browser support later with: ${GREEN}rote setup --full${NC}\n" >&2
                return
                ;;
            *)
                printf "  ${YELLOW}!${NC} Enter y or n.\n" >&2
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Install sequence
# ═══════════════════════════════════════════════════════════════════════════════

# Verify the downloaded archive against its colocated .sha256. Guards against a
# corrupted/truncated download, not a tampered CDN — the checksum is served from
# the same origin as the binary, so it carries no separate trust. Compare the
# hash only (not "sha256sum -c"): the local archive is renamed to rote.<ext>
# while the checksum file names the upstream artifact.
verify_sha256() {
    local archive="$1"
    local checksum_url="$2"
    local expected actual

    local hasher
    if command -v sha256sum >/dev/null 2>&1; then
        hasher="sha256sum"
    elif command -v shasum >/dev/null 2>&1; then
        hasher="shasum -a 256"
    else
        echo "no sha256 tool available (need sha256sum or shasum)" >&2
        return 1
    fi

    expected=$(curl -fsSL "$checksum_url" | awk '{print $1}')
    if [ "${#expected}" -ne 64 ]; then
        echo "invalid or missing checksum at $checksum_url" >&2
        return 1
    fi

    actual=$($hasher "$archive" | awk '{print $1}')
    if [ "$expected" != "$actual" ]; then
        echo "checksum mismatch at $checksum_url: expected $expected, got $actual" >&2
        return 1
    fi
}

setup_skill_unavailable() {
    local reason="$1"
    local cleanup_dir="${2:-}"
    SETUP_SKILL_STATUS="$reason"
    log "setup skill: unavailable ($reason)"
    if [ -n "$cleanup_dir" ]; then
        rm -rf "$cleanup_dir"
    fi
    return 0
}

# Stage the binary-bundled skills to a temp dir so an LLM agent driving the
# install can read the setup entrypoint. No network: the installed rote
# binary writes its embedded skills, so content always matches the version.
stage_setup_skills() {
    local rote_bin setup_dir entrypoint_path safe_version setup_parent

    case "$VERSION" in
        *[!A-Za-z0-9._-]*|"") safe_version="unknown" ;;
        *) safe_version="$VERSION" ;;
    esac

    if [ "$OS" = "windows" ]; then
        rote_bin="$INSTALL_DIR/rote.exe"
    else
        rote_bin="$INSTALL_DIR/rote"
    fi
    if [ ! -x "$rote_bin" ]; then
        setup_skill_unavailable "rote binary not found at $rote_bin"
        return 0
    fi

    setup_parent="${ROTE_SETUP_SKILL_DIR:-${ROTE_ONBOARD_DIR:-}}"
    if [ -n "$setup_parent" ]; then
        # Caller owns this parent; installer only removes generated children.
        case "$setup_parent" in
            /)
                setup_skill_unavailable "refusing setup skill directory $setup_parent"
                return 0
                ;;
            /*) ;;
            *)
                setup_skill_unavailable "setup skill directory must be an absolute path"
                return 0
                ;;
        esac
        if [ "${setup_parent%/}" = "${HOME%/}" ]; then
            setup_skill_unavailable "refusing setup skill directory $setup_parent"
            return 0
        fi
        if ! mkdir -p "$setup_parent" 2>>"$LOG_FILE"; then
            setup_skill_unavailable "could not prepare $setup_parent"
            return 0
        fi
        if ! setup_dir="$(mktemp -d "${setup_parent%/}/rote-skills-v${safe_version}.XXXXXX")"; then
            setup_skill_unavailable "could not create staging directory"
            return 0
        fi
    else
        # Unpredictable staging path avoids symlink games in shared temp dirs.
        if ! setup_dir="$(mktemp -d "${TMPDIR:-/tmp}/rote-skills-v${safe_version}.XXXXXX")"; then
            setup_skill_unavailable "could not create staging directory"
            return 0
        fi
    fi
    if ! "$rote_bin" install skill --path "$setup_dir" --package '*' --force >>"$LOG_FILE" 2>&1; then
        log "setup skill: package-aware staging failed; retrying legacy install"
        if ! "$rote_bin" install skill --path "$setup_dir" --force >>"$LOG_FILE" 2>&1; then
            setup_skill_unavailable "bundled skill install failed" "$setup_dir"
            return 0
        fi
    fi

    entrypoint_path="$setup_dir/$SETUP_ENTRYPOINT"
    if [ ! -f "$entrypoint_path" ]; then
        # Older binaries write the main skill directly at the path root.
        if [ -f "$setup_dir/SKILL.md" ]; then
            entrypoint_path="$setup_dir/SKILL.md"
        else
            setup_skill_unavailable "$SETUP_ENTRYPOINT not staged" "$setup_dir"
            return 0
        fi
    fi

    SETUP_SKILL_PATH="$entrypoint_path"
    SETUP_SKILL_STATUS="ok"
    log "setup skill: staged $SETUP_SKILL_PATH"
    return 0
}

json_escape() {
    local input="$1"
    local output=""
    local char
    local i

    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        case "$char" in
            '"') output="${output}\\\"" ;;
            \\) output="${output}\\\\" ;;
            $'\b') output="${output}\\b" ;;
            $'\f') output="${output}\\f" ;;
            $'\n') output="${output}\\n" ;;
            $'\r') output="${output}\\r" ;;
            $'\t') output="${output}\\t" ;;
            *) output="${output}${char}" ;;
        esac
    done

    printf '%s' "$output"
}

record_install_marker() {
    local binary_path="$1"
    local state_dir="$ROTE_HOME/state"
    local canonical_binary_path
    local marker_tmp

    [ -n "$binary_path" ] || return 0
    [ -e "$binary_path" ] || return 1
    canonical_binary_path=$(
        cd "$(dirname "$binary_path")" 2>/dev/null && \
        printf '%s/%s' "$(pwd -P)" "$(basename "$binary_path")"
    ) || return 1
    mkdir -p "$state_dir" || return 1
    marker_tmp=$(mktemp "$state_dir/install.json.XXXXXX") || return 1

    if printf '{ "method": "script", "bin": "%s" }\n' "$(json_escape "$canonical_binary_path")" \
        > "$marker_tmp" && mv "$marker_tmp" "$state_dir/install.json"; then
        return 0
    fi

    rm -f "$marker_tmp"
    return 1
}

install_rote() {
    local download_url="${RELEASES_BASE_URL}/v${VERSION}/${ARTIFACT}.${ARCHIVE_EXT}"
    local tmp_dir=$(mktemp -d)
    local archive_file="$tmp_dir/rote.${ARCHIVE_EXT}"
    local binary_path="$INSTALL_DIR/rote"

    log "Download URL: $download_url"

    # ── download ──────────────────────────────────────────────────────────
    # A stale ledger (binary deleted/outdated) must re-download, not no-op.
    local install_checkpoint_valid=""
    if step_done "install"; then
        local installed_version
        installed_version=$("$binary_path" --version 2>/dev/null) || installed_version=""
        if [ "${installed_version#rote }" = "$VERSION" ]; then
            install_checkpoint_valid="1"
        else
            log "install checkpoint stale (have: ${installed_version:-no working binary}, want: rote $VERSION) — re-downloading"
            # sdk/stdio artifacts are written from the binary, so a new binary
            # must re-run them; node/deno/shell are not binary-coupled.
            if grep -v -e '^sdk=ok$' -e '^stdio=ok$' "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null; then
                mv "$STATE_FILE.tmp" "$STATE_FILE"
            else
                rm -f "$STATE_FILE.tmp"
            fi
        fi
    fi

    if [ -n "$install_checkpoint_valid" ]; then
        if ! record_install_marker "$binary_path"; then
            log "failed to record install marker for $binary_path"
        fi
        progress_clear
        printf "  ${GREEN}●${NC} ${DIM}%s${NC}  %-10s %s\033[K\n" \
            "$(elapsed)" "install" "Already installed — skipping download" >&2
        COMPLETED_STEPS+=("download" "checksum" "extract" "install")
        STEP_COUNT=$((STEP_COUNT + 4))
    else
        local max_attempts=5
        local attempt=1
        while true; do
            rm -f "$archive_file"
            if progress "download" "Fetching rote v${VERSION}..." \
                curl -fsSL "$download_url" -o "$archive_file"; then
                # ── verify checksum ───────────────────────────────────────────
                if progress "checksum" "Verifying sha256..." \
                    verify_sha256 "$archive_file" "${download_url}.sha256"; then
                    break
                fi

                if [ "$attempt" -ge "$max_attempts" ]; then
                    progress_clear
                    printf "  ${RED}✗${NC}  checksum   Checksum verification failed after %s attempts — check %s\n" \
                        "$max_attempts" "$LOG_FILE" >&2
                    rm -rf "$tmp_dir"
                    exit 1
                fi

                forget_last_failed_step
                forget_last_completed_step "download"
                log "Retrying download after checksum mismatch (attempt $attempt/$max_attempts)"
            else
                if [ "$attempt" -ge "$max_attempts" ]; then
                    progress_clear
                    printf "  ${RED}✗${NC}  download   Download failed after %s attempts — check %s\n" \
                        "$max_attempts" "$LOG_FILE" >&2
                    rm -rf "$tmp_dir"
                    exit 1
                fi

                forget_last_failed_step
                log "Retrying download after fetch failure (attempt $attempt/$max_attempts)"
            fi

            local delay=$((attempt * 2))
            progress_clear
            printf "  ${YELLOW}↻${NC} ${DIM}%s${NC}  retry     Waiting %ss before retry %s/%s\033[K\n" \
                "$(elapsed)" "$delay" "$((attempt + 1))" "$max_attempts" >&2
            sleep "$delay"
            attempt=$((attempt + 1))
        done

        # ── extract ───────────────────────────────────────────────────────────
        local extract_cmd="tar xzf $archive_file -C $tmp_dir"

        if ! progress "extract" "Unpacking archive..." \
            bash -c "$extract_cmd"; then
            progress_clear
            printf "  ${RED}✗${NC}  extract    Extraction failed\n" >&2
            rm -rf "$tmp_dir"
            exit 1
        fi

        # ── install binary ────────────────────────────────────────────────────
        mkdir -p "$INSTALL_DIR"

        mv "$tmp_dir/rote" "$INSTALL_DIR/rote"
        chmod +x "$INSTALL_DIR/rote"
        if [ -f "$tmp_dir/rote-stdio-daemon" ]; then
            mv "$tmp_dir/rote-stdio-daemon" "$INSTALL_DIR/rote-stdio-daemon"
            chmod +x "$INSTALL_DIR/rote-stdio-daemon"
        fi

        rm -rf "$tmp_dir"
        if ! record_install_marker "$binary_path"; then
            log "failed to record install marker for $binary_path"
        fi
        progress_ok "install" "Installed to $binary_path"
    fi

    # ── verify + PATH ─────────────────────────────────────────────────────
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) ;;
        *)
            SHELL_CONFIG=$(detect_shell_config)
            if [ -n "$SHELL_CONFIG" ] && ! grep -qF "$INSTALL_DIR" "$SHELL_CONFIG" 2>/dev/null; then
                echo "" >> "$SHELL_CONFIG"
                echo "# rote CLI" >> "$SHELL_CONFIG"
                echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$SHELL_CONFIG"
            fi
            export PATH="$INSTALL_DIR:$PATH"
            progress_ok "path" "$INSTALL_DIR added to PATH (restart shell or: source $SHELL_CONFIG)"
            ;;
    esac

    if step_done "verify" && "$binary_path" --version >/dev/null 2>&1; then
        : # verified in a prior run and the installed binary still responds
    elif command -v rote >/dev/null 2>&1; then
        local ver_output
        ver_output=$(rote --version 2>/dev/null || echo "unknown")
        progress_ok "verify" "$ver_output"
    else
        progress_ok "verify" "Binary installed (restart shell to use)"
    fi

    # ══════════════════════════════════════════════════════════════════════
    # PARALLEL PHASE
    #
    # Dependency graph:
    #   node  ──────────────────────────────────────→ playwright
    #   deno  ──────────────────→ sdk
    #   stdio (no dependencies)
    #
    # Fire all independent jobs together. The visible spinner covers whichever
    # job takes longest. Background jobs log to $LOG_FILE.
    # bg_collect prints a newline per job so the terminal builds up a
    # clean list of completed steps.
    # ══════════════════════════════════════════════════════════════════════
    if [ -z "$BARE_INSTALL" ] && command -v rote >/dev/null 2>&1; then

        echo "" >&2
        printf "  ${DIM}Racing the clock — node · deno · stdio fetching simultaneously${NC}\n" >&2
        echo "" >&2

        # ── fire background jobs ──────────────────────────────────────────

        # node: always install (playwright depends on it) — skip if done
        if step_done "node"; then
            COMPLETED_STEPS+=("node"); STEP_COUNT=$((STEP_COUNT + 1))
            log "· [node] already done, skipping"
        else
            bg_start "node" "Setting up Node.js runtime..." \
                rote node install
        fi

        # deno: always install — skip if done
        if step_done "deno"; then
            COMPLETED_STEPS+=("deno"); STEP_COUNT=$((STEP_COUNT + 1))
            log "· [deno] already done, skipping"
        else
            bg_start "deno" "Installing Deno runtime..." \
                rote deno install
        fi

        # stdio: independent, fire immediately — skip if done
        if step_done "stdio"; then
            COMPLETED_STEPS+=("stdio"); STEP_COUNT=$((STEP_COUNT + 1))
            log "· [stdio] already done, skipping"
        else
            bg_start "stdio" "Initializing MCP servers..." \
                rote stdio init-baseline
        fi

        # ── spinner covers the parallel phase ─────────────────────────────
        # Show a combined waiting spinner while all background jobs run.
        # We poll until all pid files are gone (jobs complete).

        local spinner_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        printf "\033[?25l" >&2  # hide cursor

        while true; do
            # Check if any bg job is still running
            local any_running=0
            for phase in node deno stdio; do
                local pid_file="$BG_DIR/${phase}.pid"
                if [ -f "$pid_file" ]; then
                    local pid
                    pid=$(cat "$pid_file" 2>/dev/null || echo "")
                    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                        any_running=1
                        break
                    fi
                fi
            done
            [ "$any_running" = "0" ] && break

            local frame="${spinner_frames[$((i % ${#spinner_frames[@]}))]}"
            printf "\r  ${CYAN}%s${NC} ${DIM}%s${NC}  %-10s ${DIM}%s${NC}\033[K" \
                "$frame" "$(elapsed)" "racing" "node · deno · stdio" >&2
            sleep 0.08
            i=$((i + 1))
        done

        printf "\033[?25h" >&2  # restore cursor
        printf "\r\033[K" >&2   # clear spinner line

        # ── collect results (prints one line per job) ─────────────────────
        bg_collect "node"  || true

        bg_collect "stdio" || true

        # ── PATH for $ROTE_HOME/bin (node installed it) ───────────────────
        if [ -d "$ROTE_HOME/bin" ]; then
            case ":$PATH:" in
                *":$ROTE_HOME/bin:"*) ;;
                *) export PATH="$ROTE_HOME/bin:$PATH" ;;
            esac

            SHELL_CONFIG=$(detect_shell_config)
            if [ -n "$SHELL_CONFIG" ] && ! grep -qE '# rote bundled runtimes|/\.rote/bin' "$SHELL_CONFIG" 2>/dev/null; then
                echo "" >> "$SHELL_CONFIG"
                echo "# rote bundled runtimes (node, npm, npx, deno)" >> "$SHELL_CONFIG"
                if [ "$ROTE_HOME" = "$HOME/.rote" ]; then
                    echo 'export PATH="$HOME/.rote/bin:$PATH"' >> "$SHELL_CONFIG"
                else
                    printf 'export PATH="%s/bin:$PATH"\n' "$ROTE_HOME" >> "$SHELL_CONFIG"
                fi
            fi
            progress_ok "path" "$ROTE_HOME/bin in PATH"
        fi

        # ── browser runtime ────────────────────────────────────────────────
        if step_done "browser"; then
            COMPLETED_STEPS+=("browser"); STEP_COUNT=$((STEP_COUNT + 1))
            log "· [browser] already done, skipping"
        elif [ -n "$SKIP_BROWSER" ]; then
            STEP_COUNT=$((STEP_COUNT + 1))
            COMPLETED_STEPS+=("browser")
            mark_done "browser_skipped"
            log "· [browser] skipped (CLI-only profile)"
            printf "\r  ${YELLOW}!${NC} ${DIM}%s${NC}  %-10s %s\033[K\n" \
                "$(elapsed)" "browser" \
                "Browser automation unavailable; this CLI-only install does not provide full rote capabilities." >&2
            print_browser_skipped_guidance "$binary_path"
        elif ! binary_supports_full_setup "$binary_path"; then
            local installed_version
            installed_version=$("$binary_path" --version 2>/dev/null || printf 'rote (unknown version)')
            printf "  ${RED}✗${NC} Downloaded %s does not support Full browser setup.\n" "$installed_version" >&2
            printf "    The installer script is newer than the downloaded binary release.\n" >&2
            printf "    The CLI is installed, but browser automation is unavailable.\n" >&2
            printf "    Retry after upgrading: \"%s\" setup --full\n" "$binary_path" >&2
            printf "    Or install CLI-only now: ${GREEN}ROTE_SKIP_BROWSER=1${NC} bash -c \"\$(curl -fsSL https://getrote.dev/install)\"\n" >&2
            log "browser setup unavailable: installed binary lacks setup --full"
            return 2
        else
            if progress "browser" "Installing Playwright browser runtime..." \
                "$binary_path" setup --full; then
                :
            else
                local browser_setup_rc=$?
                progress_clear
                printf "  ${RED}✗${NC} Browser runtime setup failed.\n" >&2
                printf "  Log: %s\n" "$LOG_FILE" >&2
                printf "  Retry: \"%s\" setup --full\n" "$binary_path" >&2
                return "$browser_setup_rc"
            fi
        fi

        # ── deno: collect + sdk (sdk depends on deno being done) ──────────
        if ! step_done "deno"; then
            bg_collect "deno" || true
        fi
        if step_done "deno"; then
            if step_done "sdk"; then
                COMPLETED_STEPS+=("sdk"); STEP_COUNT=$((STEP_COUNT + 1))
                log "· [sdk] already done, skipping"
            else
                progress "sdk" "Installing TypeScript SDK..." \
                    rote sdk install || true
            fi
        fi

    fi

    # ── shell setup (serial, fast, writes config files) ───────────────────
    if [ -z "$BARE_INSTALL" ] && command -v rote >/dev/null 2>&1; then
        if step_done "shell"; then
            COMPLETED_STEPS+=("shell"); STEP_COUNT=$((STEP_COUNT + 1))
            log "· [shell] already done, skipping"
        elif ! shell_setup_supported; then
            local shell_name
            shell_name=$(shell_display_name)
            STEP_COUNT=$((STEP_COUNT + 1))
            COMPLETED_STEPS+=("shell")
            mark_done "shell_skipped"
            log "· [shell] Skipped ($shell_name unsupported)"
            printf "\r  ${GREEN}●${NC} ${DIM}%s${NC}  %-10s %s\033[K\n" \
                "$(elapsed)" "shell" "Skipped ($shell_name unsupported)" >&2
        else
            progress "shell" "Setting up shell integration..." \
                rote shell-setup || true

            SHELL_CONFIG=$(detect_shell_config)

            if [ -n "$SHELL_CONFIG" ]; then
                if ! grep -qE '# rote shell integration|rote/shell/init\.sh' "$SHELL_CONFIG" 2>/dev/null; then
                    echo "" >> "$SHELL_CONFIG"
                    echo "# rote shell integration" >> "$SHELL_CONFIG"
                    if [ "$ROTE_HOME" = "$HOME/.rote" ]; then
                        echo '[ -f ~/.rote/shell/init.sh ] && source ~/.rote/shell/init.sh' >> "$SHELL_CONFIG"
                    else
                        printf '[ -f "%s/shell/init.sh" ] && . "%s/shell/init.sh"\n' \
                            "$ROTE_HOME" "$ROTE_HOME" >> "$SHELL_CONFIG"
                    fi
                fi
            fi
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Finale
# ═══════════════════════════════════════════════════════════════════════════════
show_finale() {
    local failed_count=${#FAILED_STEPS[@]}
    local success_count=${#COMPLETED_STEPS[@]}
    local binary_path="$INSTALL_DIR/rote"
    # Probe the binary — $VERSION is only the resolved target, not what landed.
    local probed_version
    probed_version=$("$binary_path" --version 2>/dev/null) || probed_version=""
    probed_version="${probed_version#rote }"

    # Clear progress line
    progress_clear
    echo "" >&2

    # Version + platform
    if [ -z "$probed_version" ]; then
        # Broken outcome: report, skip the celebration copy, fail the run.
        printf "  ${RED}✗${NC} no working rote binary at %s — check %s\n" \
            "$binary_path" "$LOG_FILE" >&2
        for fail in "${FAILED_STEPS[@]}"; do
            printf "  ${RED}✗${NC} %s\n" "$fail" >&2
        done
        echo "" >&2
        printf "  ${DIM}Re-run with --reset (or ROTE_RESET=1) to start fresh.${NC}\n" >&2
        echo "" >&2
        log "=== rote installation failed: no working rote binary ==="
        exit 1
    elif [ "$failed_count" -gt 0 ]; then
        printf "  ${GREEN}●${NC} rote v%s · %s · %d/%d steps\n" \
            "$probed_version" "$PLATFORM_LABEL" "$success_count" "$STEP_COUNT" >&2
    else
        printf "  ${GREEN}●${NC} rote v%s · %s · %d steps\n" \
            "$probed_version" "$PLATFORM_LABEL" "$STEP_COUNT" >&2
    fi

    # Show failures
    for fail in "${FAILED_STEPS[@]}"; do
        printf "  ${RED}✗${NC} %s\n" "$fail" >&2
    done

    echo "" >&2

    printf "  ${DIM}─────────────────────────────────────────────${NC}\n" >&2
    printf "  ${BOLD}Welcome aboard.${NC} ${DIM}Time to wire things up.${NC}\n" >&2
    echo "" >&2
    printf "  ${BOLD}Power user?${NC}    ${GREEN}rote setup${NC}\n" >&2
    printf "  ${DIM}               Start connecting your APIs, credentials, and agent skills.${NC}\n" >&2
    echo "" >&2
    printf "  ${BOLD}Want a tour?${NC}   ${GREEN}rote how${NC}\n" >&2
    printf "  ${DIM}               Take a step-by-step live tour before wiring APIs.${NC}\n" >&2
    echo "" >&2
    printf "  ${BOLD}Then:${NC}          ${GREEN}rote setup${NC}\n" >&2
    printf "  ${DIM}               Adapters, tokens, AI wiring — done.${NC}\n" >&2
    printf "  ${BOLD}Help:${NC}          ${GREEN}rote setup --help${NC}\n" >&2
    if [ -n "$INSTALL_NONINTERACTIVE" ]; then
        echo "" >&2
        if [ -n "$SETUP_SKILL_PATH" ]; then
            printf "  ${BOLD}LLM-assisted:${NC} ${GREEN}%s${NC}\n" "$SETUP_SKILL_PATH" >&2
            printf "  ${DIM}               Agent: MUST read this setup SKILL.md before continuing setup.${NC}\n" >&2
        else
            printf "  ${BOLD}LLM-assisted:${NC} ${YELLOW}setup skill unavailable${NC}\n" >&2
            if [ -n "$SETUP_SKILL_STATUS" ]; then
                printf "  ${DIM}               %s. Use rote setup --help as fallback.${NC}\n" "$SETUP_SKILL_STATUS" >&2
            else
                printf "  ${DIM}               Use rote setup --help as fallback.${NC}\n" >&2
            fi
        fi
    fi
    echo "" >&2
    printf "  ${DIM}Full log:  %s${NC}\n" "$LOG_FILE" >&2
    echo "" >&2
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════
main() {
    echo "" >&2
    printf "  ${BOLD}rote installer${NC} ${DIM}· Execution Context Engineering${NC}\n" >&2
    echo "" >&2

    if install_is_noninteractive; then
        INSTALL_NONINTERACTIVE="1"
    fi

    detect_platform
    detect_full_setup_capability

    if [ -z "$BARE_INSTALL" ]; then
        validate_install_profile
        apply_platform_install_profile
        collect_install_profile
    fi

    if [ -n "$INSTALL_NONINTERACTIVE" ] && [ -z "$BARE_INSTALL" ]; then
        if [ "$INSTALL_PROFILE_DEFAULTED" = "1" ]; then
            printf "  ${BOLD}Non-interactive:${NC} ${GREEN}full installation selected by default${NC}\n" >&2
        elif [ -n "$SKIP_BROWSER" ]; then
            printf "  ${BOLD}Non-interactive:${NC} ${GREEN}CLI-only installation selected${NC}\n" >&2
        else
            printf "  ${BOLD}Non-interactive:${NC} ${GREEN}full installation selected${NC}\n" >&2
        fi
        echo "" >&2
    fi

    # Show resume notice if a prior run was interrupted
    if [ -f "$STATE_FILE" ] && [ -z "$RESET_INSTALL" ]; then
        local done_count
        done_count=$(grep -c "=ok" "$STATE_FILE" 2>/dev/null || echo 0)
        printf "  ${CYAN}→${NC} ${DIM}Resuming interrupted install (%s steps already complete)${NC}\n" \
            "$done_count" >&2
        printf "  ${DIM}  Run with --reset to start fresh.${NC}\n" >&2
        echo "" >&2
    fi

    log "=== rote installation started ==="

    # Strip legacy rote completion lines from rc files (best-effort, silent).
    # Runs unconditionally so --bare upgrades also get cleaned.
    clean_legacy_completion

    progress_ok "detect" "Platform: $PLATFORM_LABEL"

    # Resolve version
    if progress "fetch" "Resolving latest version..." \
        bash -c '
            REPO="'"$REPO"'"
            VER="'"$VERSION"'"
            LOG="'"$LOG_FILE"'"
            if [ "$VER" = "latest" ]; then
                # Resolve via github.com redirect, not api.github.com — the
                # API has a 60/hr unauth quota that NAT/CI/corp IPs blow
                # through, returning 403. The redirect has no rate limit.
                URL=$(curl -fsSLI -o /dev/null -w "%{url_effective}" \
                    "https://github.com/$REPO/releases/latest" 2>>"$LOG")
                # Require redirect into /releases/tag/<tag>, then strip
                # optional leading `v`. Rejects 200-no-redirect, error pages,
                # and unexpected URL shapes that would otherwise feed garbage
                # into the download URL.
                case "$URL" in
                    */releases/tag/*) TAG="${URL##*/tag/}"; VER="${TAG#v}" ;;
                    *) exit 1 ;;
                esac
                case "$VER" in ""|*/*) exit 1 ;; esac
            fi
            echo "$VER"
        '; then
        VERSION="$PROGRESS_STDOUT"
        progress_ok "fetch" "Resolved v$VERSION"
    else
        progress_clear
        printf "  ${RED}✗${NC}  fetch      Failed to resolve version\n" >&2
        exit 1
    fi

    log "Version: v$VERSION"

    # Install binary + run parallel phase
    install_rote

    # Best-effort local context for LLM-assisted setup.
    if [ -n "$INSTALL_NONINTERACTIVE" ]; then
        stage_setup_skills
    fi

    # Finale
    show_finale

    log "=== rote installation complete ==="
}

main
