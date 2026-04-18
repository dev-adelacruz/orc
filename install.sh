#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/dev-adelacruz/orc.git"
GLOBAL_DIR="$HOME/.claude/skills/orc"
PROJECT_DIR="$(pwd)/.claude/skills/orc"

echo "Where do you want to install orc?"
echo "  1) Global  — $GLOBAL_DIR (available in all projects)"
echo "  2) Project — $PROJECT_DIR (this project only)"
echo ""
read -rp "Choice [1/2]: " choice

case "$choice" in
  2)
    SKILL_DIR="$PROJECT_DIR"
    SCOPE="project"
    ;;
  *)
    SKILL_DIR="$GLOBAL_DIR"
    SCOPE="global"
    ;;
esac

if [ -d "$SKILL_DIR/.git" ]; then
  echo "orc is already installed at $SKILL_DIR. Updating..."
  git -C "$SKILL_DIR" pull
  echo "✅ Updated to latest version."
else
  echo "Installing orc ($SCOPE)..."
  mkdir -p "$(dirname "$SKILL_DIR")"
  git clone "$REPO_URL" "$SKILL_DIR"
  echo "✅ Installed to $SKILL_DIR"
fi

echo ""

# Check dependencies
SKILLS_ROOT="$(dirname "$SKILL_DIR")"
MISSING=()

if [ ! -d "$SKILLS_ROOT/specter" ]; then
  MISSING+=("specter")
fi

if [ ! -d "$SKILLS_ROOT/dev-agent" ]; then
  MISSING+=("dev-agent")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "⚠️  Missing dependencies: ${MISSING[*]}"
  echo ""
  read -rp "Install missing dependencies now? [y/N]: " install_deps
  if [[ "$install_deps" =~ ^[Yy]$ ]]; then
    for dep in "${MISSING[@]}"; do
      case "$dep" in
        specter)
          echo "Installing specter..."
          git clone "https://github.com/dev-adelacruz/specter.git" "$SKILLS_ROOT/specter"
          echo "✅ specter installed"
          ;;
        dev-agent)
          echo "Installing dev-agent..."
          git clone "https://github.com/dev-adelacruz/dev-agent.git" "$SKILLS_ROOT/dev-agent"
          echo "✅ dev-agent installed"
          ;;
      esac
    done
  else
    echo "Skipping. Install them manually before using Phases 1–3:"
    for dep in "${MISSING[@]}"; do
      case "$dep" in
        specter)
          echo "  git clone https://github.com/dev-adelacruz/specter.git $SKILLS_ROOT/specter"
          ;;
        dev-agent)
          echo "  git clone https://github.com/dev-adelacruz/dev-agent.git $SKILLS_ROOT/dev-agent"
          ;;
      esac
    done
  fi
else
  echo "✅ Dependencies OK (specter and dev-agent are installed)"
fi

echo ""
if [ "$SCOPE" = "project" ]; then
  echo "Tip: add .claude/skills/ to your .gitignore if you don't want to commit this."
fi
echo "Restart Claude Code, then run /orc \"your product idea\" to start the pipeline."
