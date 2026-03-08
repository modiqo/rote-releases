#!/bin/bash
set -e

# dex installer — Time to Agent™
# Usage: curl -fsSL https://raw.githubusercontent.com/modiqo/dex-releases/main/install.sh | bash
# Non-interactive: DEX_YES=1 curl -fsSL ... | bash

# Configuration
REPO="modiqo/dex-releases"
INSTALL_DIR="${DEX_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${DEX_VERSION:-latest}"
AUTO_YES="${DEX_YES:-}"

# ─── Log setup ───────────────────────────────────────────────────────────────
LOG_DIR="$HOME/.dex/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"
: > "$LOG_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# Restore cursor on exit
trap 'printf "\033[?25h" >&2' EXIT

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

    local out_file=$(mktemp /tmp/dex_out.XXXXXX)
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
    log "✓ [$1] $2"
    printf "\r  ${GREEN}●${NC} ${DIM}%s${NC}  %-10s %s\033[K" \
        "$(elapsed)" "$1" "$2" >&2
}

# Clear the progress line before interactive prompts
progress_clear() {
    printf "\r\033[K" >&2
}

# ─── Read user input (works in curl | bash) ──────────────────────────────────
prompt_user() {
    if [ -t 0 ]; then
        read -r "$@"
    else
        read -r "$@" </dev/tty
    fi
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

detect_shell_name() {
    case "$SHELL" in
        */zsh) echo "zsh" ;;
        */bash) echo "bash" ;;
        *) echo "" ;;
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
        mingw* | msys* | cygwin*) OS="windows" ;;
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
        linux-x86_64)   ARTIFACT="dex-linux-x86_64-musl";  ARCHIVE_EXT="tar.gz" ;;
        linux-aarch64)  ARTIFACT="dex-linux-aarch64-musl";  ARCHIVE_EXT="tar.gz" ;;
        macos-x86_64)   ARTIFACT="dex-macos-x86_64";       ARCHIVE_EXT="tar.gz" ;;
        macos-aarch64)  ARTIFACT="dex-macos-aarch64";       ARCHIVE_EXT="tar.gz" ;;
        windows-x86_64) ARTIFACT="dex-windows-x86_64";     ARCHIVE_EXT="zip" ;;
        *)
            printf "\r  ${RED}✗${NC}  detect     No binary for %s\n" "$OS-$ARCH" >&2
            exit 1 ;;
    esac

    PLATFORM_LABEL="$OS-$ARCH"
    log "Platform: $PLATFORM_LABEL, Artifact: $ARTIFACT"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Install sequence
# ═══════════════════════════════════════════════════════════════════════════════
install_dex() {
    local download_url="https://github.com/$REPO/releases/download/v${VERSION}/${ARTIFACT}.${ARCHIVE_EXT}"
    local tmp_dir=$(mktemp -d)
    local archive_file="$tmp_dir/dex.${ARCHIVE_EXT}"

    log "Download URL: $download_url"

    # ── download ──────────────────────────────────────────────────────────
    if ! progress "download" "Fetching dex v${VERSION}..." \
        curl -fsSL "$download_url" -o "$archive_file"; then
        progress_clear
        printf "  ${RED}✗${NC}  download   Download failed — check %s\n" "$LOG_FILE" >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    # ── extract ───────────────────────────────────────────────────────────
    case "$ARCHIVE_EXT" in
        tar.gz) local extract_cmd="tar xzf $archive_file -C $tmp_dir" ;;
        zip)    local extract_cmd="unzip -q $archive_file -d $tmp_dir" ;;
    esac

    if ! progress "extract" "Unpacking archive..." \
        bash -c "$extract_cmd"; then
        progress_clear
        printf "  ${RED}✗${NC}  extract    Extraction failed\n" >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    # ── install binary ────────────────────────────────────────────────────
    mkdir -p "$INSTALL_DIR"

    if [ "$OS" = "windows" ]; then
        mv "$tmp_dir/dex.exe" "$INSTALL_DIR/dex.exe"
        chmod +x "$INSTALL_DIR/dex.exe"
        BINARY_PATH="$INSTALL_DIR/dex.exe"
    else
        mv "$tmp_dir/dex" "$INSTALL_DIR/dex"
        chmod +x "$INSTALL_DIR/dex"
        BINARY_PATH="$INSTALL_DIR/dex"
        if [ -f "$tmp_dir/dex-stdio-daemon" ]; then
            mv "$tmp_dir/dex-stdio-daemon" "$INSTALL_DIR/dex-stdio-daemon"
            chmod +x "$INSTALL_DIR/dex-stdio-daemon"
        fi
    fi

    rm -rf "$tmp_dir"
    progress_ok "install" "Installed to $BINARY_PATH"

    # ── verify ────────────────────────────────────────────────────────────
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        FAILED_STEPS+=("path · $INSTALL_DIR not in PATH")
        STEP_COUNT=$((STEP_COUNT + 1))
    fi

    if command -v dex >/dev/null 2>&1; then
        local ver_output
        ver_output=$(dex --version 2>/dev/null || echo "unknown")
        progress_ok "verify" "$ver_output"
    else
        progress_ok "verify" "Binary installed (restart shell to use)"
    fi

    # ── node.js ───────────────────────────────────────────────────────────
    if command -v dex >/dev/null 2>&1; then
        progress "node" "Setting up Node.js runtime..." \
            dex node install || true
    fi

    # ── path config ───────────────────────────────────────────────────────
    if [ -d "$HOME/.dex/bin" ]; then
        case ":$PATH:" in
            *":$HOME/.dex/bin:"*) ;;
            *) export PATH="$HOME/.dex/bin:$PATH" ;;
        esac

        SHELL_CONFIG=$(detect_shell_config)
        if [ -n "$SHELL_CONFIG" ] && ! grep -qF '/.dex/bin' "$SHELL_CONFIG" 2>/dev/null; then
            echo "" >> "$SHELL_CONFIG"
            echo "# dex bundled runtimes (node, npm, npx, deno)" >> "$SHELL_CONFIG"
            echo 'export PATH="$HOME/.dex/bin:$PATH"' >> "$SHELL_CONFIG"
        fi
        progress_ok "path" "~/.dex/bin in PATH"
    fi

    # ── playwright ────────────────────────────────────────────────────────
    if command -v npx >/dev/null 2>&1; then
        progress "browser" "Installing Playwright Chrome..." \
            npx -y @playwright/test install --with-deps chrome || true
    fi

    # ── stdio servers ─────────────────────────────────────────────────────
    if command -v dex >/dev/null 2>&1; then
        progress "stdio" "Initializing MCP servers..." \
            dex stdio init-baseline || true
    fi

    # ── deno + sdk (interactive) ──────────────────────────────────────────
    if command -v dex >/dev/null 2>&1; then
        progress_clear

        if [ -n "$AUTO_YES" ]; then
            response="Y"
        else
            printf "\r  ${CYAN}?${NC} ${DIM}%s${NC}  %-10s Install Deno runtime for TypeScript flows? ${DIM}[Y/n]${NC} " \
                "$(elapsed)" "deno" >&2
            prompt_user response
            response=${response:-Y}
            # Clear the prompt line so next progress overwrites it
            printf "\r\033[K" >&2
        fi

        if [ "$response" = "Y" ] || [ "$response" = "y" ]; then
            if progress "deno" "Installing Deno runtime..." \
                dex deno install; then

                progress "sdk" "Installing TypeScript SDK..." \
                    dex sdk install || true
            fi
        else
            STEP_COUNT=$((STEP_COUNT + 1))
            COMPLETED_STEPS+=("deno")
            log "· [deno] Skipped"
        fi
    fi

    # ── shell setup (interactive) ─────────────────────────────────────────
    if command -v dex >/dev/null 2>&1; then
        progress_clear

        if [ -n "$AUTO_YES" ]; then
            response="Y"
        else
            printf "\r  ${CYAN}?${NC} ${DIM}%s${NC}  %-10s Set up shell integration? ${DIM}[Y/n]${NC} " \
                "$(elapsed)" "shell" >&2
            prompt_user response
            response=${response:-Y}
            # Clear the prompt line so next progress overwrites it
            printf "\r\033[K" >&2
        fi

        if [ "$response" = "Y" ] || [ "$response" = "y" ]; then
            progress "shell" "Setting up shell integration..." \
                dex shell-setup || true

            SHELL_CONFIG=$(detect_shell_config)
            SHELL_NAME=$(detect_shell_name)

            if [ -n "$SHELL_CONFIG" ]; then
                if ! grep -qF "dex/shell/init.sh" "$SHELL_CONFIG" 2>/dev/null; then
                    echo "" >> "$SHELL_CONFIG"
                    echo "# dex shell integration" >> "$SHELL_CONFIG"
                    echo '[ -f ~/.dex/shell/init.sh ] && source ~/.dex/shell/init.sh' >> "$SHELL_CONFIG"
                fi
                if [ -n "$SHELL_NAME" ] && ! grep -qF "dex completion" "$SHELL_CONFIG" 2>/dev/null; then
                    echo "" >> "$SHELL_CONFIG"
                    echo "# dex completion" >> "$SHELL_CONFIG"
                    echo "eval \"\$(dex completion $SHELL_NAME)\"" >> "$SHELL_CONFIG"
                fi
            fi
        else
            STEP_COUNT=$((STEP_COUNT + 1))
            COMPLETED_STEPS+=("shell")
            log "· [shell] Skipped"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Finale
# ═══════════════════════════════════════════════════════════════════════════════
show_finale() {
    local total_time=$(elapsed)
    local failed_count=${#FAILED_STEPS[@]}
    local success_count=${#COMPLETED_STEPS[@]}

    # Clear progress line
    progress_clear
    echo "" >&2

    # Version + platform
    if [ "$failed_count" -gt 0 ]; then
        printf "  ${GREEN}●${NC} dex v%s · %s · %d/%d steps\n" \
            "$VERSION" "$PLATFORM_LABEL" "$success_count" "$STEP_COUNT" >&2
    else
        printf "  ${GREEN}●${NC} dex v%s · %s · %d steps\n" \
            "$VERSION" "$PLATFORM_LABEL" "$STEP_COUNT" >&2
    fi

    # Show failures
    for fail in "${FAILED_STEPS[@]}"; do
        printf "  ${RED}✗${NC} %s\n" "$fail" >&2
    done

    echo "" >&2

    # Hero metric
    if [ "$failed_count" -gt 0 ]; then
        printf "  ${BOLD}Time to Agent™${NC}  ${YELLOW}%s${NC} ${DIM}(with warnings)${NC}\n" "$total_time" >&2
    else
        printf "  ${BOLD}Time to Agent™${NC}  ${GREEN}%s${NC}\n" "$total_time" >&2
    fi

    echo "" >&2
    printf "  ${DIM}─────────────────────────────────────────────${NC}\n" >&2
    printf "  Then run:  ${GREEN}dex setup${NC}\n" >&2
    printf "  ${DIM}           Adapters, tokens, AI wiring — done.${NC}\n" >&2
    echo "" >&2
    printf "  ${DIM}Full log:  %s${NC}\n" "$LOG_FILE" >&2
    echo "" >&2
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════
main() {
    echo "" >&2
    printf "  ${BOLD}dex installer${NC} ${DIM}· Execution Context Engineering${NC}\n" >&2
    echo "" >&2

    log "=== dex installation started ==="

    # Detect platform (instant)
    detect_platform
    progress_ok "detect" "Platform: $PLATFORM_LABEL"

    # Resolve version
    if progress "fetch" "Resolving latest version..." \
        bash -c '
            REPO="'"$REPO"'"
            VER="'"$VERSION"'"
            LOG="'"$LOG_FILE"'"
            if [ "$VER" = "latest" ]; then
                VER=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>>"$LOG" \
                    | grep "\"tag_name\":" | sed -E "s/.*\"v([^\"]+)\".*/\1/")
                if [ -z "$VER" ]; then exit 1; fi
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

    # Install
    install_dex

    # Finale
    show_finale

    log "=== dex installation complete ==="
}

main
