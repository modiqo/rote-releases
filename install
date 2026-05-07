#!/bin/bash
set -e

# rote installer — Time to Agent™
# Usage: curl -fsSL https://raw.githubusercontent.com/modiqo/rote-releases/main/install.sh | bash
# Non-interactive: ROTE_YES=1 curl -fsSL ... | bash

# Configuration
REPO="modiqo/rote-releases"
# ROTE_BIN is preferred; ROTE_INSTALL_DIR kept as legacy alias.
INSTALL_DIR="${ROTE_BIN:-${ROTE_INSTALL_DIR:-$HOME/.local/bin}}"
# ROTE_HOME holds runtime state (logs, bundled runtimes, shell init).
ROTE_HOME="${ROTE_HOME:-$HOME/.rote}"
VERSION="${ROTE_VERSION:-latest}"
AUTO_YES="${ROTE_YES:-}"
RESET_INSTALL="${ROTE_RESET:-}"
FULL_INSTALL="${ROTE_FULL:-}"
# ROTE_BARE skips post-install runtime setup (node/deno/stdio/sdk/shell).
# Used by integration tests to verify the binary install path without the
# heavy network-bound subcommands.
BARE_INSTALL="${ROTE_BARE:-}"

# Parse --reset / --full flags
for arg in "$@"; do
    case "$arg" in
        --reset) RESET_INSTALL="1" ;;
        --full)  FULL_INSTALL="1" ;;
        --bare)  BARE_INSTALL="1" ;;
    esac
done

# ─── Log setup ───────────────────────────────────────────────────────────────
LOG_DIR="$ROTE_HOME/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"
STATE_FILE="$LOG_DIR/install.state"

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
#   Forks the command, writes pid/meta to /tmp/rote_bg_<phase>.
#
# bg_collect "phase"
#   Waits for the job, prints ● or ✗, returns exit code of the job.

bg_start() {
    local phase="$1"; shift
    local message="$1"; shift
    local pid_file="/tmp/rote_bg_${phase}.pid"
    local out_file="/tmp/rote_bg_${phase}.out"
    local msg_file="/tmp/rote_bg_${phase}.msg"

    echo "$message" > "$msg_file"
    log "→ [bg:$phase] starting: $*"

    "$@" > "$out_file" 2>>"$LOG_FILE" &
    echo $! > "$pid_file"
}

bg_collect() {
    local phase="$1"
    local pid_file="/tmp/rote_bg_${phase}.pid"
    local out_file="/tmp/rote_bg_${phase}.out"
    local msg_file="/tmp/rote_bg_${phase}.msg"

    local pid message rc=0
    pid=$(cat "$pid_file" 2>/dev/null || echo "")
    message=$(cat "$msg_file" 2>/dev/null || echo "$phase")

    if [ -n "$pid" ]; then
        wait "$pid" 2>/dev/null || rc=$?
    fi

    rm -f "$pid_file" "$out_file" "$msg_file"

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
        printf "\r  ${RED}✗${NC} ${DIM}%s${NC}  %-10s %s\033[K" \
            "$(elapsed)" "$phase" "$message" >&2
    fi

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

# ─── Legacy rc cleanup ───────────────────────────────────────────────────────
# Strip stale `# rote completion` + `eval "$(rote completion …)"` blocks left
# behind by older installers. Mirrors `clean_legacy_completion` in
# crates/rote-cli/src/cli/shell/generator.rs:282-316. Runs from main() so
# --bare and WANT_SHELL=N paths (which never invoke `rote shell-setup`) still
# get the cleanup. Keep patterns in sync with `legacy_patterns` there.
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
        linux-x86_64)   ARTIFACT="rote-linux-x86_64-musl";  ARCHIVE_EXT="tar.gz" ;;
        linux-aarch64)  ARTIFACT="rote-linux-aarch64-musl";  ARCHIVE_EXT="tar.gz" ;;
        macos-x86_64)   ARTIFACT="rote-macos-x86_64";       ARCHIVE_EXT="tar.gz" ;;
        macos-aarch64)  ARTIFACT="rote-macos-aarch64";       ARCHIVE_EXT="tar.gz" ;;
        windows-x86_64) ARTIFACT="rote-windows-x86_64";     ARCHIVE_EXT="zip" ;;
        *)
            printf "\r  ${RED}✗${NC}  detect     No binary for %s\n" "$OS-$ARCH" >&2
            exit 1 ;;
    esac

    PLATFORM_LABEL="$OS-$ARCH"
    log "Platform: $PLATFORM_LABEL, Artifact: $ARTIFACT"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Detect Playwright browser
# ═══════════════════════════════════════════════════════════════════════════════
detect_playwright_browser() {
    if [ -n "$ROTE_PLAYWRIGHT_BROWSER" ]; then
        echo "$ROTE_PLAYWRIGHT_BROWSER"
        return
    fi

    local browser="chrome"

    if [ "$OS" = "linux" ] && [ -f /etc/os-release ]; then
        local distro_id=""
        local version_id=""

        while IFS='=' read -r key value; do
            value="${value%\"}"
            value="${value#\"}"
            case "$key" in
                ID) distro_id="$value" ;;
                VERSION_ID) version_id="$value" ;;
            esac
        done < /etc/os-release

        if [ "$distro_id" = "ubuntu" ]; then
            case "$version_id" in
                22.04|24.04|26.04)
                    browser="chrome"
                    ;;
                *)
                    browser="firefox"
                    log "Ubuntu $version_id is not in Playwright's supported list for Chrome"
                    log "Falling back to Firefox"
                    ;;
            esac
        fi
    fi

    echo "$browser"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Collect user preferences upfront (interactive only)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Populated by collect_preferences(). Read by install_rote().
WANT_DENO=""
WANT_SHELL=""

collect_preferences() {
    if [ -n "$AUTO_YES" ]; then
        WANT_DENO="Y"
        WANT_SHELL="Y"
        return
    fi

    # Only ask if rote will be available to run deno/shell commands.
    # At this point the binary isn't installed yet, but we know we're about
    # to install it — ask now so downloads can overlap.
    echo "" >&2
    printf "  ${BOLD}Quick setup questions${NC} ${DIM}(your answers let us fetch everything at once)${NC}\n" >&2
    echo "" >&2

    progress_clear
    printf "  ${CYAN}?${NC}  %-10s Install Deno runtime for TypeScript flows? ${DIM}[Y/n]${NC} " \
        "deno" >&2
    prompt_user WANT_DENO
    WANT_DENO=${WANT_DENO:-Y}

    printf "  ${CYAN}?${NC}  %-10s Set up shell integration (hooks, PATH)? ${DIM}[Y/n]${NC} " \
        "shell" >&2
    prompt_user WANT_SHELL
    WANT_SHELL=${WANT_SHELL:-Y}

    echo "" >&2
}

# ═══════════════════════════════════════════════════════════════════════════════
# Install sequence
# ═══════════════════════════════════════════════════════════════════════════════
install_rote() {
    local download_url="https://releases.getrote.dev/v${VERSION}/${ARTIFACT}.${ARCHIVE_EXT}"
    local tmp_dir=$(mktemp -d)
    local archive_file="$tmp_dir/rote.${ARCHIVE_EXT}"

    log "Download URL: $download_url"

    # ── download ──────────────────────────────────────────────────────────
    if step_done "install"; then
        progress_clear
        printf "  ${GREEN}●${NC} ${DIM}%s${NC}  %-10s %s\033[K\n" \
            "$(elapsed)" "install" "Already installed — skipping download" >&2
        COMPLETED_STEPS+=("download" "extract" "install")
        STEP_COUNT=$((STEP_COUNT + 3))
    else
        if ! progress "download" "Fetching rote v${VERSION}..." \
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
            mv "$tmp_dir/rote.exe" "$INSTALL_DIR/rote.exe"
            chmod +x "$INSTALL_DIR/rote.exe"
            BINARY_PATH="$INSTALL_DIR/rote.exe"
        else
            mv "$tmp_dir/rote" "$INSTALL_DIR/rote"
            chmod +x "$INSTALL_DIR/rote"
            BINARY_PATH="$INSTALL_DIR/rote"
            if [ -f "$tmp_dir/rote-stdio-daemon" ]; then
                mv "$tmp_dir/rote-stdio-daemon" "$INSTALL_DIR/rote-stdio-daemon"
                chmod +x "$INSTALL_DIR/rote-stdio-daemon"
            fi
        fi

        rm -rf "$tmp_dir"
        progress_ok "install" "Installed to $BINARY_PATH"
    fi

    # ── verify + PATH ─────────────────────────────────────────────────────
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        SHELL_CONFIG=$(detect_shell_config)
        if [ -n "$SHELL_CONFIG" ] && ! grep -qF "$INSTALL_DIR" "$SHELL_CONFIG" 2>/dev/null; then
            echo "" >> "$SHELL_CONFIG"
            echo "# rote CLI" >> "$SHELL_CONFIG"
            echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$SHELL_CONFIG"
        fi
        export PATH="$INSTALL_DIR:$PATH"
        progress_ok "path" "$INSTALL_DIR added to PATH (restart shell or: source $SHELL_CONFIG)"
    fi

    if step_done "verify"; then
        : # already verified in a prior run — binary is present
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
    # Strategy A: collect user answers upfront (done in collect_preferences),
    # then fire all independent jobs together. The visible spinner covers
    # whichever job takes longest. Background jobs log to $LOG_FILE.
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

        # deno: only if user said yes — skip if done
        if [ "$WANT_DENO" = "Y" ] || [ "$WANT_DENO" = "y" ]; then
            if step_done "deno"; then
                COMPLETED_STEPS+=("deno"); STEP_COUNT=$((STEP_COUNT + 1))
                log "· [deno] already done, skipping"
            else
                bg_start "deno" "Installing Deno runtime..." \
                    rote deno install
            fi
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
                local pid_file="/tmp/rote_bg_${phase}.pid"
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

        # ── playwright: skipped by default; use --full to install ───────────
        if step_done "browser"; then
            COMPLETED_STEPS+=("browser"); STEP_COUNT=$((STEP_COUNT + 1))
            log "· [browser] already done, skipping"
        elif [ -z "$FULL_INSTALL" ] && [ -z "$ROTE_SKIP_BROWSER" ]; then
            STEP_COUNT=$((STEP_COUNT + 1))
            COMPLETED_STEPS+=("browser")
            mark_done "browser_skipped"
            log "· [browser] skipped (no --full)"
            printf "\r  ${GREEN}●${NC} ${DIM}%s${NC}  %-10s %s\033[K\n" \
                "$(elapsed)" "browser" "Skipped (run: rote setup --full to install)" >&2
        elif [ -n "$ROTE_SKIP_BROWSER" ]; then
            STEP_COUNT=$((STEP_COUNT + 1))
            COMPLETED_STEPS+=("browser")
            mark_done "browser_skipped"
            log "· [browser] skipped (ROTE_SKIP_BROWSER set)"
            printf "\r  ${GREEN}●${NC} ${DIM}%s${NC}  %-10s %s\033[K\n" \
                "$(elapsed)" "browser" "Skipped (ROTE_SKIP_BROWSER set)" >&2
        elif command -v npx >/dev/null 2>&1; then
            if [ "$OS" = "linux" ] && [ "$ARCH" = "aarch64" ]; then
                progress "browser" "Installing Playwright Chromium (arm64)..." \
                    npx -y @playwright/test install --with-deps chromium || true
            else
                PW_BROWSER=$(detect_playwright_browser)
                if [ "$PW_BROWSER" = "firefox" ]; then
                    progress "browser" "Installing Playwright Firefox..." \
                        npx -y @playwright/test install --with-deps firefox || true
                else
                    progress "browser" "Installing Playwright Chrome..." \
                        npx -y @playwright/test install --with-deps chrome || true
                fi
            fi
        fi

        # ── deno: collect + sdk (sdk depends on deno being done) ──────────
        if [ "$WANT_DENO" = "Y" ] || [ "$WANT_DENO" = "y" ]; then
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
        else
            STEP_COUNT=$((STEP_COUNT + 1))
            COMPLETED_STEPS+=("deno")
            log "· [deno] Skipped by user"
        fi

    fi

    # ── shell setup (serial, fast, writes config files) ───────────────────
    if [ -z "$BARE_INSTALL" ] && command -v rote >/dev/null 2>&1; then
        if [ "$WANT_SHELL" = "Y" ] || [ "$WANT_SHELL" = "y" ]; then
            if step_done "shell"; then
                COMPLETED_STEPS+=("shell"); STEP_COUNT=$((STEP_COUNT + 1))
                log "· [shell] already done, skipping"
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
        else
            STEP_COUNT=$((STEP_COUNT + 1))
            COMPLETED_STEPS+=("shell")
            log "· [shell] Skipped by user"
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
        printf "  ${GREEN}●${NC} rote v%s · %s · %d/%d steps\n" \
            "$VERSION" "$PLATFORM_LABEL" "$success_count" "$STEP_COUNT" >&2
    else
        printf "  ${GREEN}●${NC} rote v%s · %s · %d steps\n" \
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
    printf "  Then run:  ${GREEN}rote setup${NC}\n" >&2
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
    printf "  ${BOLD}rote installer${NC} ${DIM}· Execution Context Engineering${NC}\n" >&2
    echo "" >&2

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
    # Runs unconditionally so --bare / WANT_SHELL=N upgrades also get cleaned.
    clean_legacy_completion

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

    # Collect user preferences upfront — before any downloads start.
    # Interactive: asks two Y/n questions then begins parallel phase.
    # Non-interactive (ROTE_YES=1): skips questions, defaults all to Y.
    # Bare (ROTE_BARE=1 / --bare): runtime + shell blocks are skipped, so
    # asking would just collect ignored answers.
    if [ -n "$BARE_INSTALL" ]; then
        WANT_DENO="N"
        WANT_SHELL="N"
    else
        collect_preferences
    fi

    # Install binary + run parallel phase
    install_rote

    # Finale
    show_finale

    log "=== rote installation complete ==="
}

main
