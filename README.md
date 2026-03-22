# IntelliSSH — AI-Augmented Terminal Assistant

IntelliSSH wraps your SSH and shell sessions with a local AI assistant. It observes commands and output across all connected terminals, builds cross-session situational awareness, auto-detects security-relevant events, and answers questions grounded in your own system documentation — all powered by a local Ollama LLM.

**Everything runs locally. No data leaves your machine.**

---

## How It Works

Two components: a **background daemon** that accumulates context, and **PTY wrappers** that capture I/O from each terminal. Sessions share a single situation engine, so the AI tracks what you've seen across all of them simultaneously.

```
  Terminal 1              Terminal 2              Terminal 3
  intellissh wrap         intellissh wrap         intellissh wrap
  ssh user@host-a         ssh user@host-b         ssh user@host-c
       │                       │                       │
       └───────────────────────┴───────────────────────┘
                               │
                               ▼
                  ┌────────────────────────────┐
                  │      intellissh daemon     │
                  │                            │
                  │  ├─ Rolling transcript     │
                  │  ├─ IOC extraction         │
                  │  ├─ Event timeline         │
                  │  └─ System context (docs)  │
                  │                            │
                  │  Ollama (qwen3:14b)        │
                  └────────────────────────────┘
```

Press **Ctrl+G** in any wrapped session to query the AI. It has full visibility into everything you've done across all sessions.

---

## Installation

```bash
# 1. Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# 2. Install IntelliSSH
chmod +x install.sh
./install.sh

# 3. Pull the chat model
ollama pull qwen3:14b
```

---

## Quick Start

The recommended workflow is one context per system — the daemon loads the matching documentation at startup and uses it for every analysis, with no vector search required.

```bash
# Open a terminal window for each system you're working on
export INTELLISSH_CONTEXT=system_1
intellissh daemon
intellissh wrap ssh user@10.0.1.10
intellissh wrap ssh user@10.0.1.11

# In another terminal window
export INTELLISSH_CONTEXT=system_2
intellissh daemon
intellissh wrap ssh user@10.0.2.10
```

---

## Usage

### Starting the Daemon

```bash
intellissh daemon                    # Start in background
intellissh daemon -f                 # Start in foreground (live logs)
intellissh daemon stop               # Stop and save state
intellissh status                    # Show PID, dashboard URL, active sessions
intellissh flush                     # Wipe all session state and start clean
intellissh contexts                  # List all running contexts with dashboard URLs
```

### Wrapping Sessions

```bash
intellissh wrap ssh user@host
intellissh wrap ssh -p 2222 user@host
intellissh wrap bash
intellissh wrap docker exec -it container bash
intellissh wrap kubectl exec -it pod -- bash
```

All I/O passes through transparently. The AI observes silently and builds context in the background.

### Ctrl+G — In-Session AI

Press **Ctrl+G** at any point inside a wrapped session:

- **Enter** with no input → auto-analyzes the most recent command output
- **Type a question + Enter** → answers using full session history and loaded documentation
- **Escape / Ctrl+C** → cancel

### Auto-Detection

The daemon continuously scans command output for security-relevant patterns:

- Authentication failures and invalid login attempts
- IDS/IPS alert signatures
- Suspicious outbound connections and port activity
- Hidden files in temporary directories
- Reverse shell and code execution indicators
- Scheduled task modifications

When a pattern matches, an alert is queued to the AI for analysis and surfaced on the dashboard — no Ctrl+G needed.

### IOC Extraction

Every command output is scanned and the following are extracted, tracked by frequency across all sessions, and shown on the dashboard:

| Type | Example |
|------|---------|
| `ip` | `10.0.1.50` |
| `ip:port` | `10.0.1.50:4444` |
| `domain` | `host.example.com` |
| `url` | `https://host.example.com/path` |
| `username` | from auth log patterns |
| `sha256` / `sha1` / `md5` | file hashes |
| `cve` | `CVE-2021-44228` |

### Persistent State

The daemon persists its full state (transcript, sessions, IOCs, events, AI analyses) to `~/.intellissh/state.json` every 30 seconds. State is restored automatically on restart — the AI continues from where it left off.

```bash
intellissh flush    # Wipe all state and start clean
```

### Continuous Analysis

Each Ctrl+G analysis builds on the previous ones. The AI is injected with its last 5 analyses as conversation history, so it references earlier conclusions, notes when its assessment changes, and skips repeating things already covered.

---

## Context Files

Context files are markdown documents describing your systems: hosts, IPs, ports, credentials, services, architecture, procedures. They live in a shared library at `~/.intellissh/contexts/` and are used two ways:

**Direct load (`--context <name>`)** — the daemon loads all files whose filename contains `<name>` at startup and injects the full text into every LLM prompt. Fast and accurate; no vector search required.

**RAG (full corpus)** — `intellissh index` embeds all files into a vector store. Queries retrieve the most relevant chunks across all documents. Useful when you want to search across all systems at once.

```
~/.intellissh/contexts/
├── environment.md              # General topology, shared infrastructure
├── tools/
│   ├── ids-reference.md
│   └── network-forensics.md
└── playbooks/
    ├── system_1-manual.md      # --context system_1
    ├── system_2-manual.md      # --context system_2
    └── incident-response.md
```

**Naming:** put a unique keyword in each file's name. `--context system_1` matches any file containing `system_1` in its name.

### Quick One-Shot Questions

```bash
# RAG — searches across all indexed files:
intellissh ask "how do I check open ports?"

# Direct — loads matching file, no vector search:
intellissh ask --context system_1 "what credentials does the admin interface use?"
intellissh ask --context system_2 "which services should be listening on port 443?"
intellissh ask --context system_1 --debug "show loaded chunks"
```

### Converting PDF Manuals to Context Files

Use a multimodal frontier model (Claude, GPT-4o) to convert system PDFs to IntelliSSH-digestible markdown. Prompt:

---

> You are converting a technical system manual PDF into a structured markdown document optimized for RAG ingestion. The output will be chunked into ~800-character segments and used as real-time context by an AI assistant during live terminal sessions.
>
> **Structure**
> - Use `##` for major topics and `###` for subtopics — make headings specific and descriptive (e.g. `### Health Check Endpoints`, not `### Endpoints`)
> - Keep each section short and self-contained — a chunk must make sense without surrounding context
> - Every section mentioning a component or service must name it explicitly — no pronouns or back-references
>
> **Extract and preserve**
> - All hostnames, IPs, FQDNs, ports, protocols, URLs, API endpoints — as inline code
> - All CLI commands, config paths, environment variables — as fenced code blocks
> - Connection types, authentication methods, TLS requirements
> - Health check URLs, expected responses, timeouts
> - Troubleshooting steps with exact error messages quoted
> - Service dependencies and startup/shutdown order
> - User roles and access levels
>
> **Images and diagrams**
> - Architecture diagrams → bullet list: `ComponentA → ComponentB (protocol, port)`
> - Tables → preserve as markdown tables
> - UI screenshots → extract only operationally relevant fields and values
> - Flow diagrams → numbered steps
>
> **Discard**
> - Cover pages, TOC, legal notices, marketing copy, revision history
> - Introductory paragraphs that restate the section heading
> - Generic advice not specific to this system
>
> **Output**
> - Format: a single `.md` file — full RAG-optimized handbook, do not pre-chunk or split
> - Filename: lowercase, hyphenated, identifies system and doc type — e.g. `firewall-palo-alto-pa3200.md`
> - First line: HTML comment with source and date:
>   ```
>   <!-- Source: <document name>, converted <date> -->
>   ```
>
> Be dense. Prefer 10 specific facts over 3 general sentences. Every value (port, path, timeout, version) in the PDF must appear in the output.

---

Drop the converted file into `~/.intellissh/contexts/` and rebuild the RAG index if needed:

```bash
intellissh index --force
```

---

## Context Isolation

`--context <name>` gives each system its own isolated daemon instance: separate transcript, IOCs, AI analyses, and dashboard. Nothing leaks between contexts.

```bash
# Set once per shell session (recommended):
export INTELLISSH_CONTEXT=system_1
intellissh daemon
intellissh wrap ssh user@10.0.1.10

# Or pass explicitly per command:
intellissh --context system_1 daemon
intellissh --context system_1 wrap ssh user@10.0.1.10
```

```bash
intellissh contexts
# IntelliSSH Contexts
# ──────────────────────────────────────────────────
#   default     stopped
#   system_1    running  ← active   http://127.0.0.1:8033
#   system_2    running             http://127.0.0.1:8034
```

Each context gets:
- Isolated state at `~/.intellissh/profiles/<name>/state.json`
- Dashboard on an auto-assigned port, titled `SYSTEM_1 — SITUATION DASHBOARD`
- Optional per-context config at `~/.intellissh/profiles/<name>/config.json`

Context files are a **shared library** — all contexts read from `~/.intellissh/contexts/`. Only runtime state is isolated.

`--profile` is a legacy alias for `--context`.

---

## Situation Dashboard

The daemon serves a live web dashboard — open it in a browser alongside your terminals.

```
http://127.0.0.1:8033            # Dashboard (auto-refreshes every 2s)
http://127.0.0.1:8033/api/state  # Raw JSON API
```

Panels:
- **Threat Level** — LOW / MEDIUM / HIGH / CRITICAL, assessed from detected events
- **Active Sessions** — connected terminals with command counts and last-active time
- **IOCs** — extracted indicators ranked by frequency, color-coded by type
- **AI Analysis Log** — every AI response: auto-detect alerts and Ctrl+G queries
- **Event Timeline** — security events in chronological order
- **Recent Commands** — last 20 commands across all sessions

No external dependencies — single self-contained HTML page served by the daemon.

---

## Command Reference

```bash
# Daemon
intellissh daemon                         # Start in background
intellissh daemon -f                      # Start in foreground
intellissh daemon stop                    # Stop
intellissh status                         # Status + active sessions
intellissh flush                          # Wipe session state

# Contexts
intellissh contexts                       # List all contexts
intellissh --context NAME daemon          # Start context daemon
intellissh --context NAME daemon stop     # Stop context daemon
intellissh --context NAME flush           # Flush that context only
export INTELLISSH_CONTEXT=NAME           # Set for whole shell session

# Wrapping
intellissh wrap ssh user@host
intellissh wrap ssh -p 2222 user@host
intellissh wrap bash
intellissh wrap docker exec -it c bash
intellissh wrap kubectl exec -it pod -- bash

# Asking
intellissh ask "question"                              # RAG search
intellissh ask --context NAME "question"              # Direct file load
intellissh ask --context NAME --debug "question"      # Show loaded files

# RAG index (required only for full-corpus RAG mode)
intellissh index                          # Build (skips if up to date)
intellissh index --force                  # Force rebuild
```

---

## Configuration

`~/.intellissh/config.json`:

```json
{
  "ollama_url": "http://localhost:11434",
  "model": "qwen3:14b",
  "embed_model": "nomic-embed-text",
  "context_dir": "~/.intellissh/contexts",
  "db_dir": "~/.intellissh/vectordb",
  "rag_top_k": 6,
  "rag_min_similarity": 0.25,
  "temperature": 0.3,
  "thinking_mode": "auto",
  "auto_detect": true,
  "auto_detect_debounce_secs": 5,
  "max_transcript_entries": 200,
  "web_port": 8033
}
```

| Setting | Description | Default |
|---------|-------------|---------|
| `model` | Ollama chat model | `qwen3:14b` |
| `embed_model` | Embedding model for RAG | `nomic-embed-text` |
| `rag_top_k` | Chunks retrieved per RAG query | `6` |
| `rag_min_similarity` | Minimum similarity threshold (0–1) | `0.25` |
| `thinking_mode` | `on`, `off`, or `auto` (Qwen3 extended reasoning) | `auto` |
| `auto_detect` | Auto-scan output for security events | `true` |
| `auto_detect_debounce_secs` | Min seconds between auto-detections per session | `5` |
| `max_transcript_entries` | Rolling transcript buffer depth | `200` |
| `web_port` | Dashboard HTTP port (auto-increments if taken) | `8033` |

---

## File Layout

```
~/.intellissh/
├── config.json
├── daemon.sock / daemon.pid / daemon.log
├── dashboard.port
├── state.json                     # Persisted transcript, IOCs, analyses
├── .index_hash                    # RAG index checksum
├── contexts/                      # Shared documentation library
│   ├── environment.md
│   ├── tools/
│   └── playbooks/
│       ├── system_1-manual.md
│       └── system_2-manual.md
├── vectordb/                      # RAG vector store
├── logs/
└── profiles/                      # Per-context isolated state
    ├── system_1/
    │   ├── config.json
    │   ├── daemon.sock / daemon.pid / daemon.log
    │   ├── dashboard.port
    │   ├── state.json
    │   └── logs/
    └── system_2/
        └── ...
```

---

## Uninstall

```bash
# 1. Stop all daemons
intellissh daemon stop
intellissh --context system_1 daemon stop

# 2. Remove binaries
rm ~/.local/bin/intellissh ~/.local/bin/intellissh-daemon ~/.local/bin/intellissh-wrap

# 3. Remove all data
rm -rf ~/.intellissh/

# 4. Remove PATH entry from ~/.zshrc / ~/.bashrc (the two IntelliSSH lines)

# 5. Optional: remove Ollama models
ollama rm qwen3:14b
ollama rm nomic-embed-text
```

---

## Dependencies

- Python 3.9+ · Linux or macOS (PTY required)
- `requests`, `chromadb` — installed by `install.sh`
- Ollama — `qwen3:14b` required; `nomic-embed-text` required only for RAG index mode
