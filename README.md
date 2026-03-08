# rote - Execution Context Engineering

> **A substrate between agents and APIs**

Deterministic agent-tool orchestration through embedded guidance and self-reflective languages.

---

## What is rote?

rote sits **between your AI agent and APIs**, transforming exploration into reusable, deterministic workflows with 90%+ token savings on repeat tasks.

```
┌─────────────────────────────────┐
│ AI Agent (Cursor, Claude, etc.) │
└────────────┬────────────────────┘
             │ natural language
             ▼
┌─────────────────────────────────────────────┐
│ rote (learning substrate)                     │
│  • Records action sequences                 │
│  • Provides real-time correction hints      │
│  • Stores successful sequences for replay   │
│  • Caches responses for instant re-query    │
└────────────┬────────────────────────────────┘
             │ structured API calls
             ▼
┌─────────────────────────────────┐
│ APIs (GitHub, Gmail, Stripe...) │
└─────────────────────────────────┘
```

**Key Insight:** First exploration takes 30 seconds and 8,400 tokens. Subsequent runs take 2 seconds and 250 tokens.

---

## Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/modiqo/rote-releases/main/install.sh | bash
```

### Non-Interactive Install (CI / VM / Agent Swarming)

For automated deployments where no human is at the terminal, set `ROTE_YES=1` to skip all interactive prompts (Deno runtime, shell integration):

```bash
curl -fsSL https://raw.githubusercontent.com/modiqo/rote-releases/main/install.sh | ROTE_YES=1 bash
```

Or using `export`:

```bash
export ROTE_YES=1 && curl -fsSL https://raw.githubusercontent.com/modiqo/rote-releases/main/install.sh | bash
```

This is the recommended approach for provisioning cloud VMs, Docker containers, and CI pipelines.

### Platform-Specific

<details>
<summary><b>macOS (Apple Silicon)</b></summary>

```bash
curl -L https://github.com/modiqo/rote-releases/raw/main/releases/latest/rote-macos-aarch64.tar.gz | tar xz
sudo mv rote /usr/local/bin/
rote --version
```
</details>

<details>
<summary><b>macOS (Intel)</b></summary>

```bash
curl -L https://github.com/modiqo/rote-releases/raw/main/releases/latest/rote-macos-x86_64.tar.gz | tar xz
sudo mv rote /usr/local/bin/
rote --version
```
</details>

<details>
<summary><b>Linux (x86_64)</b></summary>

```bash
curl -L https://github.com/modiqo/rote-releases/raw/main/releases/latest/rote-linux-x86_64.tar.gz | tar xz
sudo mv rote /usr/local/bin/
rote --version
```
</details>

---

## Getting Started

### First-Time Setup

After installing, run the interactive setup wizard:

```bash
rote setup
```

The wizard walks you through four screens in under 60 seconds:

1. **Login** — Sign in to the community registry via GitHub or Google OAuth
2. **Adapter Selection** — Pick adapters for the services you use (GitHub, Gmail, Calendar, Stripe, etc.). Associated skills are pulled automatically
3. **Credentials** — Configure API tokens via OAuth flows or paste API keys. Each adapter runs a proof-of-life check against live data to confirm it works
4. **Wire** — Connect rote to your AI coding tool (Claude Code, Cursor, or both) by generating adapter agents

`rote setup` is state-aware and idempotent — run it again any time to add more adapters or reconfigure.

### Headless Setup (Non-Interactive)

For automated provisioning of remote nodes (VMs, containers, agent swarms), use `--headless` to run setup without any interactive prompts:

```bash
rote setup --headless \
  --claim-token rtp_<TOKEN> \
  --adapters github,gmail,sheets \
  --provider claude \
  --verify
```

**Flags:**

| Flag | Description |
|---|---|
| `--headless` | Run in non-interactive mode (required) |
| `--claim-token <TOKEN>` | Device claim token (or set `ROTE_CLAIM_TOKEN` env var) |
| `--adapters <LIST>` | Comma-separated adapter IDs to install from registry |
| `--provider <NAME>` | Wire to AI tool: `claude`, `cursor`, `codex`, `agents-md`, or `all` |
| `--verify` | Run proof-of-life checks after setup |
| `--skip-wire` | Skip skill/agent wiring step |

**Environment variables:**

| Variable | Description |
|---|---|
| `ROTE_CLAIM_TOKEN` | Claim token (alternative to `--claim-token` flag) |
| `ROTE_VAULT_PASSPHRASE` | Vault passphrase for pulling encrypted credentials |

**Finding adapter IDs:**

```bash
rote adapter list                              # Show installed adapters
rote registry adapter list --community <slug>  # Browse available adapters in registry
```

**Full automated deployment (install + setup):**

```bash
# 1. Install rote non-interactively
curl -fsSL https://raw.githubusercontent.com/modiqo/rote-releases/main/install.sh | ROTE_YES=1 bash

# 2. Source shell to get rote on PATH
source ~/.bashrc  # or ~/.zshrc

# 3. Run headless setup with env vars
export ROTE_CLAIM_TOKEN=rtp_<TOKEN>
export ROTE_VAULT_PASSPHRASE=<passphrase>
rote setup --headless --adapters github,gmail --provider claude --verify
```

For full help: `rote setup --help`

### Your First Workflow

```bash
# Start interactive onboarding
rote how

# Initialize a workspace
rote init my-first-workflow --seq

# Make an API call (example with GitHub adapter)
rote POST adapter/github-api '{
  "method": "tools/call",
  "params": {
    "name": "github_api_probe",
    "arguments": {"query": "list repositories", "limit": 5}
  }
}' -s

# Query the cached response
rote @1 '.result.tools[].name' -r

# Export as reusable flow
rote export ~/.rote/flows/github/my-workflow.sh
```

---

## Core Capabilities

### 1. MCP Workflow Automation

Execute sequences of MCP calls with state management:

```bash
# Initialize session
rote init-session /github

# Make calls with session state
rote POST /github '{"method":"tools/call",...}' -s

# Query responses without re-executing
rote @1 '.result.data' -r
rote @1 '.result.items | length' -r
rote @1 '.result.items[] | select(.active)' -r
```

**Result:** <100 microseconds per query vs 500ms for HTTP re-execution.

### 2. Adapter Framework: Any REST API → MCP

Transform any REST API into searchable MCP capabilities:

```bash
# Create adapter from OpenAPI spec
rote adapter new github-api https://api.github.com/openapi.json --yes

# Now you have 2 virtual MCP tools:
# 1. github_api_probe - Search 1,111 operations semantically
# 2. github_api_call - Execute discovered operations

# Search for capability
rote github_api_probe "create repository" --limit 5 -s

# Execute discovered tool
rote github_api_call repos/create '{"name": "my-project", "owner": "myorg"}' -s
```

**Supported:** OpenAPI 3.x, Google Discovery, GraphQL SDL, gRPC

**Value:** No custom MCP server needed. Any API becomes MCP-compatible in seconds.

### 3. Skills: Reusable Workflows

Skills are parameterized workflows that can depend on adapters:

```bash
# Pull a skill from registry
rote registry skill pull github-issue-creator

# Skill declares dependencies:
# - Requires: github_api adapter (fingerprint: mcp_abc123...)
# - Auto-installs missing dependencies

# Run the skill
~/.rote/skills/github-issue-creator.sh "Bug in login" "Steps to reproduce..."

# Skills compose:
# - Skill A uses Adapter X
# - Skill B uses Adapter Y + Skill A
# - Exponential value through composition
```

### 4. Flow Export: Exploration → Automation

Convert successful explorations into reusable scripts:

```bash
# After exploring a workflow
rote export ~/.rote/flows/my-workflow.sh \
  --params owner,repo,state \
  --description "Fetch GitHub issues" \
  --composable

# Reuse instantly
~/.rote/flows/my-workflow.sh facebook react open

# Fork with new parameters (~3 seconds vs 30s from scratch)
rote flow fork ~/.rote/flows/my-workflow.sh \
  --as my-variant \
  --params owner=google,repo=chrome \
  --replay
```

**Result:** 95%+ token savings on repeat tasks.

### 5. Flow Templates: Scaffold New Flows

Generate new flows with best-practice structure:

```bash
# Create a TypeScript flow
rote flow template create --name my-flow --adapter github --type ts

# Create a Python flow
rote flow template create --name my-flow --adapter gmail --type py
```

Scaffolded flows include frontmatter metadata, SDK imports, fingerprint validation, auth checks, auto-tracking, and error handling — ready to customize.

### 6. Trace: Execution Visualization

Visualize workspace execution timelines as terminal Gantt charts:

```bash
# View execution timeline for current workspace
rote trace

# Export as interactive HTML
rote trace --html report.html

# View trace from archived workspace
rote trace --archive path/to/archive.parquet
```

Shows latency bars, token heatmaps, and dependency flows across all requests in a workspace.

### 7. Archive: Workspace Export to Parquet

Capture workspace state as columnar Parquet files for offline analysis:

```bash
# Archive current workspace
rote archive

# Archive with body redaction (privacy-safe)
rote archive --no-bodies

# Archive all workspaces
rote archive --all

# Analyze with DuckDB, Polars, or Pandas
duckdb -c "SELECT * FROM 'workspace.parquet'"
```

### 8. Browser Automation

Automate web interactions via Playwright:

```bash
# Navigate and snapshot (CRITICAL: snapshot first!)
rote browse --headed https://example.com

# Query efficiently (95-99% token savings)
rote browser-extract @1 button
rote browser-find @1 --text "search"

# Interact using discovered refs
rote browse click <ref>

# Export workflow
rote export ~/.rote/flows/web/my-automation.sh
```

**Pattern:** Navigate → Snapshot → Understand → Interact

---

## SDKs

### TypeScript SDK

The TypeScript SDK ships with rote and runs via the embedded Deno runtime:

```typescript
import { Rote, FlowOutput, runPreflight } from "rote-sdk";

const rote = new Rote();
const out = new FlowOutput();  // Supports human, summary, and json output modes

await runPreflight(rote, { adapters: ["github"] });

out.human("Searching repositories...");
out.summary("Found 10 repositories");
```

### Python SDK

Full Pydantic-native Python SDK with feature parity:

```python
from rote_sdk import Rote, FlowOutput, run_preflight

rote = Rote()
out = FlowOutput()

await run_preflight(rote, adapters=["github"])

out.human("Searching repositories...")
out.summary("Found 10 repositories")
```

Both SDKs include: workspace management, token management, HTTP execution, adapter interaction, flow search, browser automation, background tasks, and structured output modes.

---

## The Power of Composition

### Adapters + Skills = Exponential Value

**Level 1: Adapters**
- GitHub API → `github_api` adapter
- Stripe API → `stripe_api` adapter
- Twilio API → `twilio_api` adapter

**Level 2: Skills (Using Adapters)**
- `github-issue-creator` (uses github_api)
- `payment-processor` (uses stripe_api)
- `sms-notifier` (uses twilio_api)

**Level 3: Composite Skills (Using Skills + Adapters)**
- `bug-to-payment` (uses github-issue-creator + payment-processor)
- `deploy-and-notify` (uses multiple skills + adapters)

**Result:** Each layer multiplies value. 3 adapters x 10 skills = 30 capabilities. Add 5 composite skills = 150+ workflows.

---

## Key Features

### Embedded Guidance

Self-contained documentation, no external lookups:

```bash
rote how                          # Interactive onboarding
rote guidance agent essential     # 700-line agent guide
rote guidance adapters essential  # Adapter framework guide
rote guidance browser essential   # Browser automation guide
rote grammar query                # Query syntax examples
rote machine workspace            # Architecture deep-dive
```

### 98% jq Compatibility

No external tools needed:

```bash
# Extract
rote @1 '.items[].name' -r

# Filter
rote @1 '.items[] | select(.active)' -r

# Transform
rote @1 '.items | map(.name)' -r
rote @1 '.items | sort_by(.score)' -r
rote @1 '.items | group_by(.type)' -r

# Aggregate
rote @1 '.scores | sum' -r
rote @1 '.prices | min' -r
rote @1 '.ratings | avg' -r

# Multi-response
rote aggregate @2..@50 '$.contact' --filter 'status == active'
```

### TypeScript Transformations (90/8/2 Rule)

- **90%** of tasks: Use native rote (~5ms)
- **8%** of tasks: Inline TypeScript (~70-200ms)
- **2%** of tasks: External files (>20 lines, reusable)

```bash
# Native (fast)
rote @1 '.items[] | select(.active)' -r

# Inline TypeScript (when needed)
rote @1 '$' --transform-ts 'return response.filter(x => x.score > 0.8)'

# With curated packages
rote @1 '$' --transform-ts 'import { format } from "rote:date-fns"; return format(data.date, "yyyy-MM-dd")'
```

### Flow Search & Reuse

Don't rebuild existing workflows:

```bash
# Search before building
rote flow search "fetch github issues"

# Found? Run it
~/.rote/flows/github/fetch-issues.sh facebook react open

# Not found? Build, then export
rote init my-workflow --seq
# ... explore ...
rote export ~/.rote/flows/my-workflow.sh
```

### Structured Output Modes

Flows support three output modes via `--output=<mode>`:

```bash
# Human output (default) — verbose with formatting
rote deno run --allow-all ./flow.ts

# Summary output — compact, parseable lines
rote deno run --allow-all ./flow.ts --output=summary

# JSON output — machine-readable structured data
rote deno run --allow-all ./flow.ts --output=json
```

---

## Performance

```
┌──────────────────────────────────────────────────┐
│ METRICS                                          │
├──────────────────────────────────────────────────┤
│ First Exploration:  30 seconds · 8,400 tokens   │
│ Subsequent Runs:    2 seconds  · 250 tokens     │
│                                                  │
│ Cache Query Time:   <100 microseconds           │
│ Flow Export Size:   <500 bytes (binary)         │
│ Token Savings:      90-97% on repeat tasks      │
│ Setup Wizard:       <60 seconds (first run)     │
└──────────────────────────────────────────────────┘
```

---

## Use Cases

### For AI Agents

- **Workflow Automation:** Execute multi-step MCP sequences
- **Response Caching:** Query API responses without re-execution
- **Flow Reuse:** Search and reuse existing workflows
- **Error Recovery:** Real-time hints for common mistakes

### For Developers

- **API Integration:** Any REST API → MCP in seconds
- **Skill Distribution:** Share reusable workflows via registry
- **Browser Automation:** Playwright workflows with export
- **Testing:** Deterministic replay of API sequences
- **Observability:** Trace execution timelines and archive workspace data

### For Teams

- **Knowledge Sharing:** Export successful workflows as skills
- **Onboarding:** `rote setup` gets new team members productive in under a minute
- **Standardization:** Consistent API interaction patterns
- **Cost Reduction:** 90%+ token savings across team
- **Analytics:** Archive workspaces to Parquet for offline analysis

---

## Architecture

### Three-Layer System

**Layer 1: Adapters** (API → MCP)
- Transform REST APIs into MCP capabilities
- Semantic search across 1,000+ operations
- Production-ready middleware (rate limiting, retry, circuit breakers)

**Layer 2: Skills** (Workflows)
- Parameterized, reusable workflows
- Declare adapter dependencies (by fingerprint)
- Auto-install missing dependencies
- Compose with other skills

**Layer 3: Registry** (Distribution)
- Multi-tenant artifact registry (Supabase-based)
- Organizations (private) and Communities (public)
- Full-text search across adapters and skills
- Dependency resolution and version management

### Workspace Isolation

Each task gets its own isolated sandbox:
- Responses cached as `@1`, `@2`, `@3`...
- Variables stored as `$name=value`
- Independent MCP sessions
- Separate cache namespace

**No interference between tasks. Full isolation. Clean state.**

---

## Command Reference

### Essential Commands

```bash
# First-Time Setup
rote setup                        # Interactive wizard

# Onboarding
rote how                          # Interactive guide
rote start                        # Protocol checklist
rote guidance agent essential     # 700-line guide

# Workflow
rote init <name> --seq            # Create workspace
rote POST /endpoint '{}' -s       # Execute with session
rote @N '<query>' -r              # Query cached response
rote export <path> --params x,y   # Export as reusable flow

# Discovery
rote flow search "intent"         # Find existing flows
rote explore "intent"             # Cross-adapter tool search
rote inventory                    # List all endpoints

# Adapters
rote adapter new <id> <spec>      # Create from OpenAPI
rote adapter list                 # List installed adapters

# Skills
rote registry skill search "query" # Search registry
rote registry skill pull <name>    # Install skill
rote registry skill push <file>    # Publish skill

# Flow Templates
rote flow template create --name <name> --adapter <adapter> --type ts
rote flow template create --name <name> --adapter <adapter> --type py

# Observability
rote trace                        # Terminal Gantt chart
rote trace --html report.html     # Export as interactive HTML
rote archive                      # Export workspace to Parquet
rote archive --all                # Archive all workspaces
rote ps --detailed                # Endpoint health monitoring

# Tokens
rote token set <NAME> <VALUE>     # Store encrypted token
rote token list                   # List stored tokens
rote token-valid <ENDPOINT>       # Validate OAuth token

# Browser
rote browse --headed <url>        # Navigate and snapshot
rote browser-extract @N button    # Extract elements
rote browse click <ref>           # Interact

# Reference
rote grammar <topic>              # Command examples
rote machine <topic>              # Architecture guides
```

---

## Examples

### Example 1: GitHub Issues Workflow

```bash
# Initialize
rote init github-issues --seq
cd ~/.rote/workspaces/github-issues

# Set parameters
rote set owner=facebook repo=react state=open

# Search for capability
rote github_api_probe "list issues" --limit 5 -s

# Execute discovered tool
rote github_api_call issues/list '{"owner": "$owner", "repo": "$repo", "state": "$state"}' -t -s

# Query results
rote @2 '.items[].title' -r

# Export for reuse
rote export ~/.rote/flows/github/list-issues.sh \
  --params owner,repo,state \
  --description "Fetch GitHub issues"
```

**Reuse:**
```bash
cd /tmp
~/.rote/flows/github/list-issues.sh facebook react open
```

### Example 2: Skill Composition

```bash
# Install base adapter
rote adapter new github-api https://api.github.com/openapi.json --yes

# Install skill that uses adapter
rote registry skill pull github-issue-creator

# Skill automatically checks for github_api adapter
# If missing, prompts to install

# Use skill
~/.rote/skills/github-issue-creator.sh "Bug in login" "Steps: 1. Go to /login 2. Click submit"

# Install composite skill
rote registry skill pull bug-tracker

# This skill uses github-issue-creator internally
# Plus adds notification, assignment, labeling
~/.rote/skills/bug-tracker.sh "Critical bug" "Production down"
```

### Example 3: Setup and Proof-of-Life

```bash
# Run the setup wizard
rote setup

# The wizard will:
# 1. Authenticate you with the community registry
# 2. Let you pick adapters (e.g., GitHub + Gmail)
# 3. Walk you through OAuth flows and API key setup
# 4. Run proof-of-life: fetch real data from each adapter
# 5. Generate agents for your AI coding tool

# After setup, your agent can immediately use rote:
# "Search my GitHub repos" → works instantly
# "Check my recent emails" → works instantly
```

---

## Advanced Features

### Parallel Execution

```bash
# Execute multiple calls in parallel
rote for @1 '.items[]' --parallel POST /api '{"id": "$"}' -t -s

# 10 items = 10 parallel requests = 3-10x faster
```

### Dependency Tracking

```bash
# Track variable sources
rote @1 '.name' -s tool_name    # Tracks: tool_name <- @1.name

# Use in templates
rote POST /api '{"tool":"$tool_name"}' -t -s

# View dependency graph
rote ls --show-dependencies

# Export knows dependencies automatically
rote export flow.sh --params tool_name
```

### Anti-Pattern Detection

```bash
# Detect common mistakes
rote detect

# 16 patterns detected:
# - Using jq instead of native rote
# - Missing -s flag on POST
# - Hardcoded values (should be params)
# - Inefficient query patterns
```

### Background Tasks

```bash
# SDK support for long-running operations
# Progress mode (default) — animated display, blocks until done
# Background mode — returns handle for manual polling
```

---

## Registry System

### Multi-Tenant Architecture

**Organizations** (Private)
- Role-based access (owner/admin/developer/reader)
- Team isolation
- Private by default

**Communities** (Public)
- Anyone can join
- Subscription-based
- Public by default

### Publishing

```bash
# Create organization
rote registry org create my-company

# Push adapter
rote registry adapter push my-adapter.adapt my-company

# Push skill
rote registry skill push my-skill.sh my-company

# Or publish to community
rote registry community subscribe powerpack
rote registry skill push my-skill.sh powerpack
```

### Discovery

```bash
# Search adapters
rote registry adapter search "github api"

# Search skills
rote registry skill search "create issue"

# Pull and install
rote registry skill pull github-issue-creator
```

---

## Documentation

### Built-In Guides

```bash
rote how                          # Onboarding flow
rote start                        # Protocol checklist
rote guidance agent essential     # Essential agent guide (700 lines)
rote guidance adapters essential  # Adapter framework guide
rote guidance browser essential   # Browser automation guide
```

### Command Examples

```bash
rote grammar query                # Query syntax (jq-compatible)
rote grammar http                 # HTTP requests
rote grammar session              # Session management
rote grammar iteration            # Loops and parallel
rote grammar deno                 # TypeScript transformations
```

### Architecture

```bash
rote machine workspace            # How workspaces work
rote machine adapters             # Adapter architecture
rote machine typescript           # TypeScript integration
rote machine mcp                  # MCP session management
rote machine story                # Complete workflow story
```

---

## Platform Support

- **macOS** — Apple Silicon (M1/M2/M3/M4) and Intel
- **Linux** — x86_64 (Ubuntu, Debian, Fedora, RHEL, etc.)
- **Windows** — Coming soon

**Binary Size:** 8-15 MB (depending on features)
**Dependencies:** Zero runtime dependencies
**Language:** Pure Rust (no C bindings)

---

## Security

### Binary Verification

```bash
# Download with checksum
curl -LO https://github.com/modiqo/rote-releases/raw/main/releases/latest/rote-macos-aarch64.tar.gz
curl -LO https://github.com/modiqo/rote-releases/raw/main/releases/latest/rote-macos-aarch64.tar.gz.sha256

# Verify
sha256sum -c rote-macos-aarch64.tar.gz.sha256
```

### Token Storage

Tokens are stored in an encrypted vault at `~/.rote/secrets/tokens.json`. OAuth tokens are acquired via browser-based flows and stored securely — no credentials are passed through the command line.

---

## Updates

### Check Version

```bash
rote --version
```

### Update to Latest

```bash
curl -fsSL https://raw.githubusercontent.com/modiqo/rote-releases/main/install.sh | bash
```

---

## Community

- **Email:** ask@modiqo.ai
- **Issues:** Contact via email
- **Documentation:** Run `rote guidance` after installation

---

## FAQ

**Q: How do I get started?**
A: Install rote, then run `rote setup`. The interactive wizard handles everything — registry login, adapter selection, credential configuration, and AI tool integration — in under 60 seconds.

**Q: What makes rote different from other MCP tools?**
A: rote is a learning substrate. It doesn't just execute MCP calls — it learns from successful explorations and makes them reusable. Agents learn from each other.

**Q: Do I need to write MCP servers for my APIs?**
A: No. Use the adapter framework to transform any OpenAPI spec into MCP capabilities in seconds.

**Q: Can I share workflows with my team?**
A: Yes. Export flows as skills and publish to your organization or community in the registry.

**Q: How does the 90%+ token savings work?**
A: First exploration is cached. Subsequent runs query the cache (<100 microseconds) instead of re-executing HTTP calls (500ms). Plus, exported flows are parameterized and reusable.

**Q: What's the difference between adapters and skills?**
A: Adapters transform APIs into MCP. Skills are workflows that use adapters. Skills can depend on other skills, creating compounding value.

**Q: Can I write flows in Python?**
A: Yes. rote ships with both TypeScript and Python SDKs. Use `rote flow template create --type py` to scaffold a Python flow.

**Q: Is my data private?**
A: Yes. Workspaces are local. Registry is opt-in. Tokens are stored in an encrypted local vault. You control what you publish.

---

## License

See LICENSE file in this repository.

---

## About

rote is developed by Modiqo. It's designed to let agents learn from each other through embedded guidance and self-reflective languages.

**Website:** https://modiqo.ai
**Releases:** https://github.com/modiqo/rote-releases
**Source:** Private (this is a releases-only repository)

---

**Current Version:** v0.0.3
**Status:** Production Ready
**Platforms:** macOS (Intel + Apple Silicon), Linux (x86_64)
