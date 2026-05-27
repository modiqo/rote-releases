# rote

> Agents reach tools directly. What worked becomes memory. Recall it. Share it.

No MCP servers to host. No connector tax. Your agent calls the API, the run becomes a memory, and the next time — yours or your teammate's — it just remembers.

---

## the six-step tour

You can do everything below in about a coffee break.

### 1. Get in

rote is invite-only right now. Two paths:

```bash
rote waitlist you@company.com    # Ask to be let in
rote join <invite-code>          # You got an invite — use it
```

If a teammate is already on rote, ask them to send you one with `rote invites send you@company.com`.

### 2. Set up

One command sets the whole thing up — registry login, adapter picks, OAuth flows, agent wiring. Under 60 seconds the first time, idempotent every time after.

```bash
rote setup
```

The wizard walks four screens: sign in, pick adapters (GitHub, Gmail, Stripe, Linear, …), wire credentials (OAuth or paste a key), and connect rote to your AI coding tool. Each adapter runs a live proof-of-life check before it's marked ready.

Re-run any time to add more adapters or swap providers.

### 3. Wire your agent

rote installs a skill into your AI tool of choice during setup. Use it like this:

| Tool | Invocation |
|---|---|
| Claude Code | type `/rote` |
| Codex / OpenCode | type `@rote` |
| Cursor / Windsurf / anything that reads `AGENTS.md` | already wired |

Then ask in plain English: *"fetch open PRs in the modiqo/rote repo"*, *"send a thank-you email to everyone who replied last week"*, *"what should I work on next?"* The skill activates, rote reaches your adapters, and the run is saved as a memory.

### 4. Create an adapter from any API

Have a REST API or MCP endpoint? Wrap it in seconds.

```bash
# From an OpenAPI / Swagger spec
rote adapter new linear https://api.linear.app/openapi.json

# From an MCP endpoint
rote adapter new-from-mcp posthog https://app.posthog.com/mcp
```

You now have two virtual MCP tools per adapter — one to search the API surface semantically, one to call any operation you find. No custom MCP server to build, no manifest to author.

### 5. Open the Canvas

The Canvas is the visual side of rote — install the VS Code extension, click the rote icon in the sidebar, and you'll see every adapter, flow, workspace, and recent agent run as a card. It's where you watch what the agent just did, replay it, fork it, and decide whether it deserves to become a saved memory.

```bash
# Install the VS Code extension
code --install-extension modiqo.rote
```

Then open any workspace. Catalog, Adapters, Vault, Explore, Agent, Canvas, Flow, Hub — each panel is a step in the journey. The breadcrumb says "Canvas" because that's the substrate the next step builds on.

### 6. Share via the Hub

What worked for you almost certainly works for the next person. The Hub is the public + private registry for adapters and flows.

```bash
rote registry adapter search "linear"      # Browse what's there
rote registry adapter pull modiqo/linear   # Install someone else's adapter
rote registry adapter push ./my-adapter modiqo  # Publish your own
```

Same shape for flows (`rote registry flow ...`). Push to a private org, push to a community, your call.

---

## the cheat sheet

Twelve commands cover ~90% of what people actually do.

| I want to... | Run |
|---|---|
| Request an invite | `rote waitlist you@company.com` |
| Join with an invite code | `rote join <code>` |
| Set everything up | `rote setup` |
| Create an adapter from OpenAPI | `rote adapter new <id> <spec-url>` |
| Create an adapter from MCP | `rote adapter new-from-mcp <id> <url>` |
| List what I have installed | `rote adapter list` |
| Browse the Hub | `rote registry adapter search <query>` |
| Pull from the Hub | `rote registry adapter pull <org/name>` |
| Find a saved flow | `rote flow search "<intent>"` |
| Run a saved flow | `rote flow run <name>` |
| Re-authorize an adapter | `rote adapter reauth <id>` |
| Learn rote | `rote start` |

That's it. The rest is `rote how` away.

---

## learning rote

Three commands, increasing depth:

```bash
rote start        # Where to begin — protocol checklist
rote how          # Full command index, navigable
rote guidance     # Deep-dive topics: agent, adapters, browser, registry, ...
```

`rote guidance agent essential` is a 700-line guide your AI can read. Run it once and your agent gets dramatically better at using rote.

---

## install

### One-liner (macOS, Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/modiqo/rote-releases/main/install.sh | bash
```

### Non-interactive (CI, VMs, agent swarms)

```bash
curl -fsSL https://raw.githubusercontent.com/modiqo/rote-releases/main/install.sh | ROTE_YES=1 bash
```

Combined with headless setup for fully unattended provisioning:

```bash
rote setup --headless \
  --claim-token rtp_<TOKEN> \
  --adapters github,gmail \
  --provider claude \
  --verify
```

<details>
<summary><b>Platform-specific downloads</b></summary>

**macOS (Apple Silicon)**
```bash
curl -L https://github.com/modiqo/rote-releases/raw/main/releases/latest/rote-macos-aarch64.tar.gz | tar xz
sudo mv rote /usr/local/bin/
```

**macOS (Intel)**
```bash
curl -L https://github.com/modiqo/rote-releases/raw/main/releases/latest/rote-macos-x86_64.tar.gz | tar xz
sudo mv rote /usr/local/bin/
```

**Linux (x86_64)**
```bash
curl -L https://github.com/modiqo/rote-releases/raw/main/releases/latest/rote-linux-x86_64.tar.gz | tar xz
sudo mv rote /usr/local/bin/
```

Windows: coming soon.

</details>

---

## power user

<details>
<summary><b>Workspaces, flows, and the Hub</b></summary>

### Workspaces — every task is isolated

```bash
rote init my-task              # Create a workspace
rote workspace ls              # Recent workspaces
rote workspace inspect <name>  # State + variables + step history
```

Each workspace is a sandbox: cached responses, variables, MCP sessions, and dependency tracking — all separate. Nothing leaks across tasks.

### Flows — turning a run into a memory

```bash
rote flow search "<intent>"             # Find an existing flow first
rote flow template create -n my-flow -a github -t ts   # Scaffold a new one
rote flow run my-flow owner=facebook repo=react        # Run with params
rote flow fork my-flow --as my-variant --params x=y    # Fork with overrides
rote flow release my-flow                              # Promote draft → released
rote flow bless my-flow                                # Approve write permissions
rote flow analytics                                    # Usage stats
```

Flows are versioned, parameterized, lint-checked, and survive the next rote release.

### Hub — share what works

```bash
rote registry adapter push  <path> <slug>       # Publish an adapter
rote registry flow push     <path> <slug>       # Publish a flow
rote registry org create    --slug my-org       # Private namespace
rote registry org invite my-org user@x.com      # Invite a teammate
rote registry org list                          # See orgs you belong to
rote invites list                               # See pending invites you sent
```

Adapters and flows both have fingerprints — when someone pulls a flow that depends on adapter `foo`, rote checks they have a compatible `foo` and offers to install it if not. Composition just works.

### Observability — what did the agent actually do?

```bash
rote trace                          # Terminal Gantt chart
rote trace --html report.html       # Interactive HTML export
rote archive                        # Workspace → Parquet (DuckDB / Polars / Pandas ready)
rote chronicle                      # Product journey timeline
rote ps --detailed                  # Endpoint health
rote stats                          # Token + latency rollups
```

### Browser — when the API doesn't exist

```bash
rote browse --headed https://example.com   # Navigate + snapshot
rote browser extract @1 button             # Pull elements from the snapshot
rote browse click <ref>                    # Interact using discovered refs
```

Pattern: navigate → snapshot → understand → interact. 95–99% token savings vs raw page text.

### SDKs — flows in TypeScript or Python

```typescript
import { Rote, FlowOutput, runPreflight } from "rote-sdk";
const rote = new Rote();
const out = new FlowOutput();
await runPreflight(rote, { adapters: ["github"] });
```

```python
from rote_sdk import Rote, FlowOutput, run_preflight
rote = Rote()
out = FlowOutput()
await run_preflight(rote, adapters=["github"])
```

Both SDKs ship with rote, run via the embedded Deno / Python runtime, and support `--output=human|summary|json` for human, AI, and pipeline consumers respectively.

</details>

---

## what makes rote different

- **No middleware.** No MCP server to host, no connector to subscribe to, no per-call fee.
- **Memory, not workflow.** Successful runs become memories your agent recalls without re-exploring.
- **Composable.** Adapters wrap APIs. Flows use adapters. Flows can use other flows. Each layer multiplies value.
- **Auditable.** Every run leaves a trace. The Canvas shows you exactly what happened. The Hub shows you what survived.
- **Local-first.** Your workspaces, tokens, and flows live on your machine in an encrypted vault. The Hub is opt-in.

---

## platforms

- **macOS** — Apple Silicon and Intel
- **Linux** — x86_64
- **Windows** — coming soon

Pure Rust, no C bindings, ~10 MB binary, zero runtime dependencies.

---

## community

- **Website:** https://modiqo.ai
- **Email:** ask@modiqo.ai
- **Built-in docs:** `rote start`, `rote how`, `rote guidance`

---

**Releases:** https://github.com/modiqo/rote-releases
**Source:** private (this is a releases-only repository)
