# SecDef — AI-Augmented Blue Team Terminal

A real-time AI assistant that wraps your SSH/shell sessions during security defense training. It sees your commands and output across multiple sessions, builds situational awareness, auto-detects security events, and provides actionable suggestions — all powered by a local Ollama LLM with RAG.

**Everything runs locally. No data leaves your machine.**

---

## How It Works

SecDef runs as two components: a **background daemon** (the brain) and **PTY wrappers** (the eyes). The daemon accumulates context from all your terminal sessions, so when you SSH into server A, find alerts, then SSH into server B to investigate — the AI remembers why you're there.

```
  Terminal 1                    Terminal 2                    Terminal 3
  secdef wrap                   secdef wrap                   secdef wrap
  ssh ids-sensor                ssh web-server                ssh siem-server
       │                             │                             │
       │  commands + output           │  commands + output          │
       └──────────┬──────────────────┘──────────────────┘
                  │
                  ▼
       ┌─────────────────────────────────────┐
       │         secdef daemon                │
       │                                      │
       │  Situation Awareness Engine           │
       │  ├─ Rolling transcript (all sessions)│
       │  ├─ Auto-detected IOCs               │
       │  ├─ Security event timeline          │
       │  └─ RAG context from your docs       │
       │                                      │
       │  Ollama (qwen3:14b + nomic-embed)    │
       └─────────────────────────────────────┘
```

**Press Ctrl+G** in any wrapped session to summon the AI. It sees everything you've done across all sessions and gives you context-aware suggestions.

---

## Quick Start

```bash
# 1. Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# 2. Install SecDef
chmod +x install.sh
./install.sh

# 3. Pull models
ollama pull qwen3:14b
ollama pull nomic-embed-text

# 4. Edit context files for YOUR environment
nano ~/.secdef/contexts/environment.md

# 5. Build RAG index
secdef index

# 6. Start the AI daemon
secdef daemon

# 7. Wrap your SSH sessions
secdef wrap ssh analyst@10.0.1.20
```

---

## Usage

### Starting Up

```bash
secdef daemon              # Start the AI brain (background)
secdef daemon -f           # Start in foreground (see logs)
secdef daemon stop         # Stop the daemon
secdef status              # Check daemon + active sessions
secdef profiles            # List all profiles with status and dashboard URLs
```

### Wrapping Sessions

```bash
secdef wrap ssh analyst@ids-sensor        # Wrap SSH
secdef wrap ssh root@10.0.3.10            # Wrap SSH with IP
secdef wrap bash                           # Wrap local shell
secdef wrap docker exec -it siem bash      # Wrap docker
secdef wrap kubectl exec -it pod -- bash   # Wrap kubernetes
```

Your session works exactly like normal — all input/output passes through transparently. The AI observes silently in the background.

### Summoning the AI (Ctrl+G)

Press **Ctrl+G** at any time inside a wrapped session:

```
analyst@ids-sensor:~$ tail -20 /var/log/suricata/fast.log
03/20 14:32:01 [**] ET MALWARE Reverse Shell [**] 10.0.2.100 -> 10.0.3.10:4444
03/20 14:32:05 [**] ET MALWARE Reverse Shell [**] 10.0.2.100 -> 10.0.3.10:4444

[Ctrl+G]

┌─ SecDef Query ──────────────────────────────────────────┐
│ Ask a question (or Enter for auto-analysis):            │
└─────────────────────────────────────────────────────────┘
secdef> _
```

- **Press Enter** with no question → auto-analyzes the latest output
- **Type a question** → context-aware answer using all session history

Example responses:

```
┌─ 💡 SecDef ─────────────────────────────────────────────┐
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

The daemon saves its full state (transcript, sessions, IOCs, events, AI analyses) to `~/.secdef/state.json` every 30 seconds. If the daemon crashes or the machine reboots, state is automatically restored on next start — the AI picks up where it left off.

```bash
secdef flush              # Wipe all state and start a clean sheet
```

Use `flush` at the start of a new exercise or when you want the AI to forget everything it has seen.

### Parallel Profiles (Multiple Independent Environments)

Run two completely isolated SecDef instances in parallel — separate state, separate IOCs, separate AI analyses, separate dashboards. Nothing leaks between them.

**Option A — env var (recommended for shell sessions):**

Open a dedicated terminal window for each environment and set the profile once:

```bash
# Terminal window for Network 1
export SECDEF_PROFILE=net1
secdef daemon
secdef wrap ssh analyst@10.0.1.20
secdef wrap ssh analyst@10.0.1.30

# Terminal window for Network 2
export SECDEF_PROFILE=net2
secdef daemon
secdef wrap ssh analyst@192.168.2.10
secdef wrap ssh analyst@192.168.2.20
```

**Option B — `--profile` flag (explicit per-command):**

```bash
secdef --profile net1 daemon
secdef --profile net1 wrap ssh analyst@10.0.1.20
secdef --profile net2 daemon
secdef --profile net2 wrap ssh analyst@192.168.2.10
```

Both options can be mixed — the flag always takes precedence over the env var.

**Checking what's running:**

```bash
secdef profiles
# SecDef Profiles
# ──────────────────────────────────────────────────
#   default        stopped
#   net1           running  ← active   http://127.0.0.1:8033
#   net2           running             http://127.0.0.1:8034
```

Each profile gets its own:
- State, transcript, IOCs, AI analyses (`~/.secdef/profiles/<name>/state.json`)
- Dashboard on an auto-assigned port (8033, 8034, …)
- Context files and RAG vector store (`~/.secdef/profiles/<name>/contexts/` and `vectordb/`)
- Config (`~/.secdef/profiles/<name>/config.json`) — copy from default and customise per environment
- Logs (`~/.secdef/profiles/<name>/logs/`)

The default profile (no `--profile` flag, no env var) continues to use `~/.secdef/` as before.

**Per-profile context files:**

Each profile has its own context directory, so you can describe each network separately:

```bash
export SECDEF_PROFILE=net1
secdef init               # creates ~/.secdef/profiles/net1/contexts/
nano ~/.secdef/profiles/net1/contexts/environment.md   # describe Network 1
secdef index

export SECDEF_PROFILE=net2
secdef init               # creates ~/.secdef/profiles/net2/contexts/
nano ~/.secdef/profiles/net2/contexts/environment.md   # describe Network 2
secdef index
```

### Continuous Analysis

Each Ctrl+G analysis builds on the previous ones rather than starting from scratch. The AI is shown its last 5 analyses as conversation history, so it can:

- Reference conclusions it already reached
- Note when its assessment changes based on new evidence
- Skip re-explaining things already covered

### Quick Questions (No Session)

```bash
secdef ask "what port is the SIEM dashboard on?"
secdef ask "write a suricata rule for DNS tunneling"
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

Edit `~/.secdef/contexts/` to match your training environment, then run `secdef index`.

```
~/.secdef/contexts/
├── environment.md              # Network topology, hosts, IPs
├── tools/
│   ├── suricata.md             # IDS reference
│   ├── wazuh.md                # SIEM reference
│   └── network-forensics.md    # tcpdump, zeek
└── playbooks/
    └── incident-response.md    # IR procedures
```

The more specific your context files, the better the AI's suggestions. Include actual IPs, hostnames, credentials, tool paths, and procedures from your training range.

---

## Command Reference

### Daemon

```bash
secdef daemon                    # Start daemon in background
secdef daemon -f                 # Start in foreground (shows logs in terminal)
secdef daemon stop               # Stop the daemon (saves state to disk)
secdef status                    # Show daemon PID, dashboard URL, active sessions
secdef flush                     # Wipe all session state and start clean
```

### Profiles

```bash
secdef profiles                          # List all profiles with status + dashboard URLs
secdef --profile NAME daemon             # Start daemon for a named profile
secdef --profile NAME daemon stop        # Stop that profile's daemon
secdef --profile NAME status             # Status for that profile
secdef --profile NAME flush              # Flush that profile's state only
export SECDEF_PROFILE=NAME              # Set profile for the whole shell session
```

### Wrapped Sessions

```bash
secdef wrap ssh user@host                    # AI-augmented SSH session
secdef wrap ssh -p 2222 user@host            # SSH on custom port
secdef wrap bash                             # AI-augmented local shell
secdef wrap docker exec -it c bash           # Wrap docker container
secdef wrap kubectl exec -it pod -- bash     # Wrap k8s pod
# With a profile (or set SECDEF_PROFILE in the shell instead):
secdef --profile net1 wrap ssh user@host
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
secdef index                     # Build index (skips if up to date)
secdef index --force             # Force rebuild (after editing context files)
secdef index -f                  # Same as --force
```

### Context Files

```bash
secdef init                      # Create example context files in ~/.secdef/contexts/
secdef init                      # Run again to reset (asks for confirmation)
```

After editing context files, always rebuild the index:
```bash
nano ~/.secdef/contexts/environment.md
secdef index --force
```

### Quick Questions (No Wrapping Needed)

```bash
secdef ask "what port is the SIEM dashboard on?"
secdef ask "write a suricata rule for DNS tunneling"
secdef ask "how do I check for persistence on a Linux host?"
```

### Dashboard

```
http://127.0.0.1:8033            # Open in browser (auto-refreshes every 2s)
http://127.0.0.1:8033/api/state  # Raw JSON API (for scripting)
```

---

## Configuration

`~/.secdef/config.json`:

```json
{
  "ollama_url": "http://localhost:11434",
  "model": "qwen3:14b",
  "embed_model": "nomic-embed-text",
  "context_dir": "~/.secdef/contexts",
  "db_dir": "~/.secdef/vectordb",
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
  "log_dir": "~/.secdef/logs"
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
~/.secdef/                         # Default profile
├── config.json                    # Settings (edit this)
├── daemon.sock                    # UNIX socket (daemon ↔ wrappers)
├── daemon.pid                     # Daemon PID file
├── daemon.log                     # Daemon stdout/stderr log
├── dashboard.port                 # Actual dashboard port (auto-managed)
├── state.json                     # Persisted engine state (survives restarts)
├── .index_hash                    # RAG index checksum (auto-managed)
├── chat_history                   # Readline history
├── contexts/                      # YOUR environment docs (edit these)
│   ├── environment.md             # Network topology, hosts, IPs
│   ├── tools/
│   │   ├── suricata.md            # IDS reference
│   │   ├── wazuh.md               # SIEM reference
│   │   └── network-forensics.md
│   └── playbooks/
│       └── incident-response.md
├── vectordb/                      # ChromaDB store (built by secdef index)
├── logs/                          # Session transcript logs
│   └── session_20260320_1430.md
└── profiles/                      # Named profiles (one dir per profile)
    ├── net1/                      # SECDEF_PROFILE=net1
    │   ├── config.json            # Profile-specific settings (optional)
    │   ├── daemon.sock
    │   ├── daemon.pid
    │   ├── daemon.log
    │   ├── dashboard.port         # Auto-assigned port (e.g. 8034)
    │   ├── state.json
    │   ├── .index_hash
    │   ├── contexts/              # Network 1 environment docs
    │   ├── vectordb/              # Network 1 RAG index
    │   └── logs/
    └── net2/                      # SECDEF_PROFILE=net2
        ├── ...                    # Same structure, fully isolated
        └── dashboard.port         # Auto-assigned port (e.g. 8035)
```

---

## Tips for Training

1. **Edit context files BEFORE the exercise.** The more specific your `environment.md` is (real IPs, real hostnames, real credentials), the more useful the AI becomes. A vague context gives vague answers.

2. **Rebuild the index after ANY context file change:**
   ```bash
   secdef index --force
   ```

3. **Add context mid-exercise.** Learned something new? Drop a quick `.md` file:
   ```bash
   echo "# New Finding\nAttacker uses port 8443 for C2" > ~/.secdef/contexts/custom/findings.md
   secdef index --force
   ```

4. **Use the dashboard on a second monitor.** It gives you a birds-eye view of all sessions, detected IOCs, and the full AI analysis log — without cluttering your terminals.

5. **Press Ctrl+G often.** Even a quick Enter (auto-analyze) after running a command can surface connections you'd miss. The AI sees all sessions and remembers its prior analyses — you only see one terminal at a time.

6. **Flush between exercises.** Each exercise is its own scenario — carry-over IOCs and transcript from a previous run will confuse the AI:
   ```bash
   secdef flush
   ```

7. **Pipe-friendly `secdef ask`** for quick lookups without wrapping:
   ```bash
   secdef ask "iptables rule to block 10.0.2.0/24"
   secdef ask "suricata rule syntax for detecting DNS tunneling"
   ```

8. **Check daemon logs if something isn't working:**
   ```bash
   cat ~/.secdef/daemon.log
   secdef daemon -f          # restart in foreground to see live output
   ```

---

## Dependencies

- Python 3.9+ (macOS: `brew install python3`)
- `requests`, `chromadb` (installed by install.sh)
- Ollama with `qwen3:14b` + `nomic-embed-text`
- Linux or macOS (PTY support required)
