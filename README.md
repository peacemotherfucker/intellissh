# IntelliSSH — AI-Augmented Blue Team Terminal

A real-time AI assistant that wraps your SSH/shell sessions during security defense training. It sees your commands and output across multiple sessions, builds situational awareness, auto-detects security events, and provides actionable suggestions — all powered by a local Ollama LLM.

**Everything runs locally. No data leaves your machine.**

---

## How It Works

IntelliSSH runs as two components: a **background daemon** (the brain) and **PTY wrappers** (the eyes). The daemon accumulates context from all your terminal sessions, so when you SSH into server A, find alerts, then SSH into server B to investigate — the AI remembers why you're there.

```
  Terminal 1                    Terminal 2                    Terminal 3
  intellissh wrap                   intellissh wrap                   intellissh wrap
  ssh ids-sensor                ssh web-server                ssh siem-server
       │                             │                             │
       │  commands + output           │  commands + output          │
       └──────────┬──────────────────┘──────────────────┘
                  │
                  ▼
       ┌─────────────────────────────────────┐
       │         intellissh daemon                │
       │                                      │
       │  Situation Awareness Engine           │
       │  ├─ Rolling transcript (all sessions)│
       │  ├─ Auto-detected IOCs               │
       │  ├─ Security event timeline          │
       │  └─ Context: direct file or RAG      │
       │                                      │
       │  Ollama (qwen3:14b)                  │
       └─────────────────────────────────────┘
```

**Press Ctrl+G** in any wrapped session to summon the AI. It sees everything you've done across all sessions and gives you context-aware suggestions.

---

## Quick Start

```bash
# 1. Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# 2. Install IntelliSSH
chmod +x install.sh
./install.sh

# 3. Add your context files (convert PDFs first — see Converting PDF Manuals below)
ls ~/.intellissh/contexts/playbooks/

# 4a. Start a focused daemon for a specific system (recommended):
intellissh --context powergrid daemon
intellissh --context powergrid wrap ssh analyst@10.0.17.1

# 4b. Or start with full RAG (searches all docs):
ollama pull nomic-embed-text    # embedding model required for RAG
intellissh index                # build vector store
intellissh daemon
intellissh wrap ssh analyst@10.0.1.20
```

---

## Usage

### Starting Up

```bash
intellissh daemon              # Start the AI brain (background)
intellissh daemon -f           # Start in foreground (see logs)
intellissh daemon stop         # Stop the daemon
intellissh status              # Check daemon + active sessions
intellissh contexts            # List all contexts with status and dashboard URLs
```

### Wrapping Sessions

```bash
intellissh wrap ssh analyst@ids-sensor        # Wrap SSH
intellissh wrap ssh root@10.0.3.10            # Wrap SSH with IP
intellissh wrap bash                           # Wrap local shell
intellissh wrap docker exec -it siem bash      # Wrap docker
intellissh wrap kubectl exec -it pod -- bash   # Wrap kubernetes
```

Your session works exactly like normal — all input/output passes through transparently. The AI observes silently in the background.

### Summoning the AI (Ctrl+G)

Press **Ctrl+G** at any time inside a wrapped session:

```
analyst@ids-sensor:~$ tail -20 /var/log/suricata/fast.log
03/20 14:32:01 [**] ET MALWARE Reverse Shell [**] 10.0.2.100 -> 10.0.3.10:4444
03/20 14:32:05 [**] ET MALWARE Reverse Shell [**] 10.0.2.100 -> 10.0.3.10:4444

[Ctrl+G]

┌─ IntelliSSH Query ──────────────────────────────────────────┐
│ Ask a question (or Enter for auto-analysis):            │
└─────────────────────────────────────────────────────────┘
intellissh> _
```

- **Press Enter** with no question → auto-analyzes the latest output
- **Type a question** → context-aware answer using all session history

Example responses:

```
┌─ 💡 IntelliSSH ─────────────────────────────────────────────┐
│ Repeated reverse shell alerts from 10.0.2.100 to       │
│ web-server (10.0.3.10) on port 4444. The web server     │
│ appears compromised.                                     │
│                                                          │
│ [1] Check active connections on web-server:              │
│     ssh web-server 'ss -tunapl | grep 4444'             │
│ [2] Block attacker IP at firewall:                       │
│     sudo iptables -A INPUT -s 10.0.2.100 -j DROP        │
│ [3] Check for persistence mechanisms:                    │
│     ssh web-server 'crontab -l; ls -la /tmp /dev/shm'   │
└──────────────────────────────────────────────────────────┘
```

### Auto-Detection

The AI automatically watches for security-relevant patterns in command output:

- IDS/IPS alerts
- Authentication failures
- Suspicious port connections (4444, 1337, etc.)
- Hidden files in /tmp, /dev/shm
- Reverse shell indicators
- Code execution patterns

When detected, an alert panel appears automatically — no Ctrl+G needed.

### IOC Extraction

Every command output is scanned for indicators of compromise. The following are extracted automatically and tracked with hit counts across all sessions:

| Type | Examples |
|------|---------|
| `ip` | `10.0.2.100` |
| `ip:port` | `10.0.2.100:4444` |
| `domain` | `evil.example.com` |
| `url` | `http://c2.attacker.io/payload` |
| `username` | extracted from auth logs (`Failed password for alice`) |
| `sha256` / `sha1` / `md5` | file hashes from AV/scanner output |
| `cve` | `CVE-2021-44228` |

IOCs are visible in the dashboard with type badges and frequency counts. The AI is automatically aware of all collected IOCs when you press Ctrl+G.

### Persistent Memory & Flushing

The daemon saves its full state (transcript, sessions, IOCs, events, AI analyses) to `~/.intellissh/state.json` every 30 seconds. If the daemon crashes or the machine reboots, state is automatically restored on next start — the AI picks up where it left off.

```bash
intellissh flush              # Wipe all state and start a clean sheet
```

Use `flush` at the start of a new exercise or when you want the AI to forget everything it has seen.

### Context-Based Isolation (Multiple Independent Environments)

Use `--context <name>` to run focused, isolated IntelliSSH instances per system. Each context provides:

1. **Focused knowledge** — the daemon loads only the matching `.md` file(s) at startup, injecting them directly into every LLM prompt. No vector search, no retrieval gaps — the model sees the exact document for that system.
2. **Isolated state** — separate transcript, IOCs, AI analyses, and dashboard per context. Nothing leaks between them.

**Typical workflow — one terminal window per system:**

```bash
# Terminal window for system_1
export INTELLISSH_CONTEXT=system_1
intellissh daemon              # loads *system_1*.md into memory at startup
intellissh wrap ssh analyst@10.0.17.1
intellissh wrap ssh analyst@10.0.17.2

# Terminal window for Satellite
export INTELLISSH_CONTEXT=system_2
intellissh daemon              # loads *system_2*.md into memory at startup
intellissh wrap ssh analyst@10.0.25.1
```

**Or with explicit flags:**

```bash
intellissh --context system_1 daemon
intellissh --context system_1 wrap ssh analyst@10.0.17.1
intellissh --context system_2 daemon
intellissh --context system_2 wrap ssh analyst@10.0.25.1
```

The flag always takes precedence over the env var.

**Checking what's running:**

```bash
intellissh contexts
# IntelliSSH Contexts
# ──────────────────────────────────────────────────
#   default        stopped
#   system_1      running  ← active   http://127.0.0.1:8033
#   system_2      running             http://127.0.0.1:8034
```

**How context files are matched:**

The context name is matched as a glob pattern `*<name>*` against all `.md` files in `~/.intellissh/contexts/`. For example `--context system_1` loads any file whose name contains `system_1`:

```
~/.intellissh/contexts/playbooks/system_1-manual.md     ← loaded
~/.intellissh/contexts/playbooks/six_seven_67.md   	← NOT loaded
~/.intellissh/contexts/playbooks/chaos_as_a_service.md 	← NOT loaded
```

Context files are a **shared library** — all contexts read from `~/.intellissh/contexts/`. Profiles only isolate runtime state (transcript, IOCs, analyses).

**What each context gets:**

- Dashboard titled `System_1 — SITUATION DASHBOARD` on an auto-assigned port
- Isolated state: `~/.intellissh/profiles/system_1/state.json`
- Daemon log: `~/.intellissh/profiles/system_1/daemon.log`
- Optional per-context config: `~/.intellissh/profiles/system_1/config.json`

**`--profile` is a legacy alias** for `--context` — it provides isolation without loading context files. Existing `--profile` workflows continue to work unchanged.

### Continuous Analysis

Each Ctrl+G analysis builds on the previous ones rather than starting from scratch. The AI is shown its last 5 analyses as conversation history, so it can:

- Reference conclusions it already reached
- Note when its assessment changes based on new evidence
- Skip re-explaining things already covered

### Quick Questions (No Session)

```bash
intellissh ask "what port is the service dashboard on?"
intellissh ask "write a suricata rule for DNS tunneling"

# With focused context — loads the matching file directly, no vector search:
intellissh ask --context system_1 "which service runs admin dashboard ?"
intellissh ask --context system_2 "what ports should be listening ?"
```

---

## Situation Dashboard

The daemon serves a live web dashboard at **http://127.0.0.1:8033** — open it in a browser on a second monitor while you work in the terminals.

The dashboard auto-refreshes every 2 seconds and shows:

- **Threat Level** — auto-assessed from detected events (LOW → CRITICAL)
- **Active Sessions** — all connected terminals with command counts
- **IOCs** — auto-extracted indicators ranked by frequency: IPs, IP:port pairs, domains, URLs, usernames, file hashes (MD5/SHA1/SHA256), CVE IDs — each labeled by type with color coding
- **AI Analysis Log** — every AI response (auto-detect alerts + Ctrl+G queries) with full reasoning and suggestions
- **Event Timeline** — security events in chronological order
- **Recent Commands** — what you've been running across all sessions

No JavaScript frameworks, no build step — it's a single self-contained HTML page served directly by the daemon. The page uses `<meta http-equiv="refresh">` for live updates.

---

## Context Files

All context files live in the shared library at `~/.intellissh/contexts/`. They are used two ways:

- **`--context <name>` (direct load)** — the daemon or `ask` command loads any file whose name contains `<name>`. No vector search needed.
- **RAG (full corpus)** — `intellissh index` chunks all files into a vector store; queries retrieve the most relevant chunks across all files.

```
~/.intellissh/contexts/
├── environment.md                      # General network topology
├── tools/
│   ├── suricata.md                     # IDS reference
│   ├── wazuh.md                        # SIEM reference
│   └── network-forensics.md
└── playbooks/
    ├── system_1-manual.md        	# intellissh --context system_1 daemon
    ├── system_2-manual.md 		# intellissh --context system_2 daemon
    ├── six-seven-control.md    	# intellissh --context six-seven daemon
    └── incident-response.md
```

**Naming tip:** Give each system's file a clear, unique keyword in its filename. The `--context` flag matches on that keyword — `--context system_1` matches `*system_1*`, `--context system_2` matches `*system_2*`.

The more specific your context files, the better the AI's suggestions. Include actual IPs, hostnames, credentials, tool paths, and procedures from your training range.

### Converting PDF Manuals to Context Files

System manuals (architecture docs, user guides, troubleshooting references) are valuable context but need to be converted from PDF to IntelliSSH-digestible markdown first. Use a multimodal frontier model (Claude or GPT-4o — both handle PDFs with images natively) with the following prompt:

---

> You are converting a technical system manual PDF into a structured markdown document optimized for RAG (Retrieval-Augmented Generation) ingestion. The output will be chunked into ~800-character segments and used as real-time context by an AI security assistant during live terminal sessions.
>
> **Your conversion rules:**
>
> **Structure**
> - Use `##` headings for major topics and `###` for subtopics — headings are included in every chunk and are the primary retrieval signal, so make them specific and descriptive (e.g. `### Health Check Endpoints` not `### Endpoints`)
> - Keep each section short and self-contained — a chunk must make sense without reading surrounding sections
> - Every section that mentions a component, service, or host must name it explicitly — do not use pronouns or references like "it" or "the above service"
>
> **Content to extract and preserve**
> - All hostnames, IP addresses, FQDNs, ports, protocols, URLs, and API endpoints — format as inline code
> - All CLI commands, config file paths, and environment variables — format as fenced code blocks with the shell/language tagged
> - Connection types, authentication methods, TLS requirements
> - Health check URLs, expected responses, and timeout values
> - Troubleshooting steps as numbered lists with exact error messages quoted
> - Service dependencies and startup/shutdown order
> - User roles, permissions, and access levels
>
> **Images and diagrams**
> - Architecture diagrams: extract every component, every arrow/connection, and every label into a bullet list of the form `ComponentA → ComponentB (protocol, port)`
> - Tables and matrices: convert to markdown tables exactly, preserving all values
> - Screenshots of UIs: describe only the operationally relevant fields, buttons, and values — skip decorative elements
> - Flow diagrams: convert to numbered steps
>
> **Content to discard**
> - Cover pages, table of contents, legal notices, marketing copy, revision history
> - Redundant introductory paragraphs that restate the section heading
> - Generic advice not specific to this system (e.g. "always follow security best practices")
>
> **Output format**
> ```markdown
> # [System Name] — [Document Type]
>
> ## Overview
> [2-4 bullet points: what the system is, primary role, key dependencies]
>
> ## Architecture
> [extracted from diagrams]
>
> ## Hosts and Endpoints
> [table or list of all hosts, IPs, ports, URLs]
>
> ## Connection Types
> ...
>
> ## Health Checks
> ...
>
> ## Troubleshooting
> ...
>
> ## [other sections as needed]
> ```
>
> Be dense. Prefer a bullet list of 10 facts over a paragraph of 3 sentences. Every specific value (port, path, timeout, version) that appears in the PDF must appear in the markdown.
>
> **Output file**
> - Format: a single `.md` file containing the full RAG-optimized handbook — do not pre-chunk, do not split into multiple files.
> - Filename: use a descriptive, lowercase, hyphenated name that identifies the system and document type — e.g. `firewall-palo-alto-pa3200.md`, `siem-wazuh-4.7.md`, `vpn-fortigate-60f.md`. The filename is attached as metadata to every chunk and helps the AI understand what it is retrieving.
> - First line of the file must be an HTML comment with the source document name and conversion date:
>   ```markdown
>   <!-- Source: Palo Alto PA-3200 Admin Guide v11.1, converted 2026-03-22 -->
>   ```

---

Once converted, drop the file into `~/.intellissh/contexts/` and rebuild the index:

```bash
# Example layout for converted manuals
~/.intellissh/contexts/
├── environment.md
├── manuals/
│   ├── firewall.md
│   ├── siem-platform.md
│   └── vpn-gateway.md
└── playbooks/
    └── incident-response.md

# Rebuild after adding files
intellissh index --force
```

**Tips:**
- Process one PDF per conversation turn if the document is large
- If a PDF covers multiple systems, ask the model to split the output into one file per system — chunks stay more focused that way
- If a document is updated, just overwrite the file and run `intellissh index --force` — the old index is replaced automatically

---

## Command Reference

### Daemon

```bash
intellissh daemon                    # Start daemon in background
intellissh daemon -f                 # Start in foreground (shows logs in terminal)
intellissh daemon stop               # Stop the daemon (saves state to disk)
intellissh status                    # Show daemon PID, dashboard URL, active sessions
intellissh flush                     # Wipe all session state and start clean
```

### Contexts

```bash
intellissh contexts                              # List all contexts with status + dashboard URLs
intellissh --context NAME daemon                 # Start daemon for a named context
intellissh --context NAME daemon stop            # Stop that context's daemon
intellissh --context NAME status                 # Status for that context
intellissh --context NAME flush                  # Flush that context's state only
export INTELLISSH_CONTEXT=NAME                  # Set context for the whole shell session
```

### Wrapped Sessions

```bash
intellissh wrap ssh user@host                    # AI-augmented SSH session
intellissh wrap ssh -p 2222 user@host            # SSH on custom port
intellissh wrap bash                             # AI-augmented local shell
intellissh wrap docker exec -it c bash           # Wrap docker container
intellissh wrap kubectl exec -it pod -- bash     # Wrap k8s pod
# With a context (or set INTELLISSH_CONTEXT in the shell instead):
intellissh --context powergrid wrap ssh analyst@10.0.17.1
```

### Ctrl+G (Inside a Wrapped Session)

```
Ctrl+G                           # Open AI prompt
  → Enter                        # Auto-analyze last output
  → type a question + Enter      # Ask a specific question
  → Escape or Ctrl+C             # Cancel
```

### RAG Index

```bash
intellissh index                     # Build index (skips if up to date)
intellissh index --force             # Force rebuild (after editing context files)
intellissh index -f                  # Same as --force
```

### Context Files

```bash
intellissh init                      # Create example context files in ~/.intellissh/contexts/
intellissh init                      # Run again to reset (asks for confirmation)
```

After editing context files, always rebuild the index:
```bash
nano ~/.intellissh/contexts/environment.md
intellissh index --force
```

### Quick Questions (No Wrapping Needed)

```bash
# Without context — uses RAG (vector search across all indexed files):
intellissh ask "what port is the SIEM dashboard on?"
intellissh ask "write a suricata rule for DNS tunneling"
intellissh ask "how do I check for persistence on a Linux host?"

# With context — loads matching file directly, no vector search (faster, more accurate):
intellissh ask --context system_1 "which service runs admin dashboard ?"
intellissh ask --context system_2 "what ports should be listening ?"
intellissh ask --context system_3 --debug "show me what was loaded"
```

### Dashboard

```
http://127.0.0.1:8033            # Open in browser (auto-refreshes every 2s)
http://127.0.0.1:8033/api/state  # Raw JSON API (for scripting)
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
  "rag_chunk_size": 800,
  "rag_chunk_overlap": 100,
  "rag_min_similarity": 0.25,
  "temperature": 0.3,
  "thinking_mode": "auto",
  "auto_detect": true,
  "auto_detect_debounce_secs": 5,
  "max_transcript_entries": 200,
  "web_port": 8033,
  "log_sessions": true,
  "log_dir": "~/.intellissh/logs"
}
```

| Setting | What it does | Default |
|---------|-------------|---------|
| `model` | Ollama chat model | `qwen3:14b` |
| `embed_model` | Ollama embedding model for RAG | `nomic-embed-text` |
| `rag_top_k` | Number of context chunks retrieved per query | `6` |
| `rag_min_similarity` | Minimum relevance threshold (0–1) | `0.25` |
| `thinking_mode` | Qwen3 thinking: `on`, `off`, or `auto` | `auto` |
| `auto_detect` | Auto-detect security events in output | `true` |
| `auto_detect_debounce_secs` | Minimum seconds between auto-detections per session | `5` |
| `max_transcript_entries` | Rolling transcript buffer size (shared across sessions) | `200` |
| `web_port` | Dashboard HTTP port | `8033` |

### Tuning RAG

- Increase `rag_top_k` (8–10) if AI answers seem to miss relevant context
- Decrease `rag_top_k` (3–4) if answers include irrelevant information
- Lower `rag_min_similarity` (0.15) for more permissive retrieval
- Raise `rag_min_similarity` (0.4) for only highly relevant chunks

---

## File Layout

```
~/.intellissh/                         # Default (no context/profile)
├── config.json                    # Settings (edit this)
├── daemon.sock                    # UNIX socket (daemon ↔ wrappers)
├── daemon.pid                     # Daemon PID file
├── daemon.log                     # Daemon stdout/stderr log
├── dashboard.port                 # Actual dashboard port (auto-managed)
├── state.json                     # Persisted engine state (survives restarts)
├── .index_hash                    # RAG index checksum (auto-managed)
├── contexts/                      # Shared context library (all contexts read from here)
│   ├── environment.md             # General network topology
│   ├── tools/
│   │   ├── suricata.md
│   │   └── wazuh.md
│   └── playbooks/
│       ├── system_1-manual.md     # --context system_1 loads this
│       ├── system_2-manual.md     # --context system_2 loads this
│       └── incident-response.md
├── vectordb/                      # RAG vector store (built by intellissh index)
├── logs/                          # Session transcript logs
│   └── session_20260320_1430.md
└── profiles/                      # Per-context isolated state (auto-created)
    ├── powergrid/                 # INTELLISSH_CONTEXT=powergrid
    │   ├── config.json            # Optional per-context settings
    │   ├── daemon.sock
    │   ├── daemon.pid
    │   ├── daemon.log
    │   ├── dashboard.port         # Auto-assigned port (e.g. 8034)
    │   ├── state.json             # Isolated transcript, IOCs, analyses
    │   └── logs/
    └── satellite/                 # INTELLISSH_CONTEXT=satellite
        ├── ...                    # Same structure, fully isolated
        └── dashboard.port         # Auto-assigned port (e.g. 8035)
```

---

## Tips for Training

1. **Prepare context files BEFORE the exercise.** Convert system manuals to `.md` and drop them in `~/.intellissh/contexts/playbooks/`. Use `--context <system>` to load the right doc for each session. A vague context gives vague answers — specific IPs, hostnames, ports, and procedures make all the difference.

2. **Rebuild the index after ANY context file change:**
   ```bash
   intellissh index --force
   ```

3. **Add context mid-exercise.** Learned something new? Drop a quick `.md` file:
   ```bash
   echo "# New Finding\nAttacker uses port 8443 for C2" > ~/.intellissh/contexts/custom/findings.md
   intellissh index --force
   ```

4. **Use the dashboard on a second monitor.** It gives you a birds-eye view of all sessions, detected IOCs, and the full AI analysis log — without cluttering your terminals.

5. **Press Ctrl+G often.** Even a quick Enter (auto-analyze) after running a command can surface connections you'd miss. The AI sees all sessions and remembers its prior analyses — you only see one terminal at a time.

6. **Flush between exercises.** Each exercise is its own scenario — carry-over IOCs and transcript from a previous run will confuse the AI:
   ```bash
   intellissh flush
   ```

7. **Use `--context` for focused one-shot questions** — loads the relevant document directly without vector search, giving fast and accurate answers:
   ```bash
   intellissh ask --context system_1 "what are the login credentials?"
   intellissh ask --context system_2 "which services run on port 8443?"
   ```

8. **Check daemon logs if something isn't working:**
   ```bash
   cat ~/.intellissh/daemon.log
   intellissh daemon -f          # restart in foreground to see live output
   ```

---

## Uninstall

**1. Stop any running daemons first:**

```bash
intellissh daemon stop

# If using contexts, stop each one:
intellissh --context system_1 daemon stop
intellissh --context system_2 daemon stop
```

**2. Remove the binaries:**

```bash
rm ~/.local/bin/intellissh
rm ~/.local/bin/intellissh-daemon
rm ~/.local/bin/intellissh-wrap
```

**3. Remove all data (config, state, logs, RAG index, context files):**

```bash
rm -rf ~/.intellissh/
```

This removes everything: config, session state, IOC history, AI analysis logs, context files, vector database, and session transcript logs. There is no way to recover this data afterwards.

**4. (Optional) Remove the PATH entry added by install.sh:**

Open your shell rc file (`~/.zshrc`, `~/.bashrc`, or `~/.profile`) and delete the two lines that were added:

```
# IntelliSSH
export PATH="$HOME/.local/bin:$PATH"
```

**5. (Optional) Remove Ollama models if no longer needed:**

```bash
ollama rm qwen3:14b
ollama rm nomic-embed-text
```

---

## Dependencies

- Python 3.9+ (macOS: `brew install python3`)
- `requests`, `chromadb` (installed by install.sh)
- Ollama with `qwen3:14b` + `nomic-embed-text`
- Linux or macOS (PTY support required)
