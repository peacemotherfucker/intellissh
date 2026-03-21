#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║    IntelliSSH — AI-Augmented Blue Team Terminal       ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Python 3 ──
echo -e "${BOLD}[1/5] Checking Python 3...${NC}"
if command -v python3 &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $(python3 --version 2>&1)"
else
    echo -e "  ${RED}✗ Python 3 not found.${NC}"
    exit 1
fi

# ── Dependencies ──
echo -e "${BOLD}[2/5] Installing Python dependencies...${NC}"
PIP="pip3 install --quiet --break-system-packages"
PIP_FALLBACK="pip3 install --quiet"

for pkg in requests chromadb; do
    if python3 -c "import $pkg" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $pkg"
    else
        echo -e "  ${YELLOW}Installing $pkg...${NC}"
        $PIP "$pkg" 2>/dev/null || $PIP_FALLBACK "$pkg"
        echo -e "  ${GREEN}✓${NC} $pkg installed"
    fi
done

# ── Ollama ──
echo -e "${BOLD}[3/5] Checking Ollama...${NC}"
if command -v ollama &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Ollama found"
else
    echo -e "  ${YELLOW}⚠ Ollama not found.${NC}"
    echo -e "  ${DIM}Install: curl -fsSL https://ollama.ai/install.sh | sh${NC}"
    read -p "  Continue without Ollama? [y/N] " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# ── Install binaries ──
echo -e "${BOLD}[4/5] Installing intellissh...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "$INSTALL_DIR"

for f in intellissh intellissh-daemon intellissh-wrap; do
    cp "${SCRIPT_DIR}/${f}" "$INSTALL_DIR/${f}"
    chmod +x "$INSTALL_DIR/${f}"
    echo -e "  ${GREEN}✓${NC} ${f} → ${INSTALL_DIR}/${f}"
done

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    SHELL_NAME=$(basename "$SHELL")
    case "$SHELL_NAME" in
        bash) RC="$HOME/.bashrc" ;; zsh) RC="$HOME/.zshrc" ;; *) RC="$HOME/.profile" ;;
    esac
    echo '' >> "$RC"
    echo '# IntelliSSH' >> "$RC"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$RC"
    echo -e "  ${YELLOW}PATH updated in ${RC} — run: source ${RC}${NC}"
fi

# ── Init contexts ──
echo -e "${BOLD}[5/5] Initializing...${NC}"
if [ ! -d "$HOME/.intellissh/contexts" ] || [ -z "$(ls -A "$HOME/.intellissh/contexts" 2>/dev/null)" ]; then
    "$INSTALL_DIR/intellissh" init
else
    echo -e "  ${DIM}Contexts exist. Run 'intellissh init' to reset.${NC}"
fi

# ── Models ──
if command -v ollama &>/dev/null; then
    echo ""
    echo -e "${BOLD}Ollama models:${NC}"

    if ollama list 2>/dev/null | grep -q "nomic-embed-text"; then
        echo -e "  ${GREEN}✓${NC} nomic-embed-text already present"
    else
        read -p "  Pull nomic-embed-text (for RAG)? [Y/n] " -n 1 -r; echo
        [[ ! $REPLY =~ ^[Nn]$ ]] && ollama pull nomic-embed-text
    fi

    if ollama list 2>/dev/null | grep -q "qwen3:14b"; then
        echo -e "  ${GREEN}✓${NC} qwen3:14b already present"
    else
        read -p "  Pull qwen3:14b (~9GB)? [y/N] " -n 1 -r; echo
        [[ $REPLY =~ ^[Yy]$ ]] && ollama pull qwen3:14b
    fi
fi

echo ""
echo -e "${BOLD}${GREEN}Installation complete!${NC}"
echo ""
echo -e "${BOLD}Quick start:${NC}"
echo -e "  ${CYAN}1.${NC} Edit context files:  ${DIM}nano ~/.intellissh/contexts/environment.md${NC}"
echo -e "  ${CYAN}2.${NC} Build RAG index:     ${DIM}intellissh index${NC}"
echo -e "  ${CYAN}3.${NC} Start the AI daemon: ${DIM}intellissh daemon${NC}"
echo -e "  ${CYAN}4.${NC} Wrap your SSH:       ${DIM}intellissh wrap ssh analyst@10.0.1.20${NC}"
echo -e "  ${CYAN}5.${NC} Press ${BOLD}Ctrl+G${NC} inside the session to summon the AI"
echo ""
echo -e "${BOLD}Commands:${NC}"
echo -e "  ${DIM}intellissh daemon${NC}                      Start AI daemon"
echo -e "  ${DIM}intellissh wrap ssh user@host${NC}           AI-augmented SSH"
echo -e "  ${DIM}intellissh wrap bash${NC}                    AI-augmented local shell"
echo -e "  ${DIM}intellissh status${NC}                       Show active sessions"
echo -e "  ${DIM}intellissh ask \"what port is SIEM on?\"${NC}  Quick question"
echo ""
