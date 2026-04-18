# orc

A Claude Code skill that orchestrates the full product delivery pipeline — from an idea to merged PRs — by chaining [specter](https://github.com/dev-adelacruz/specter) and [dev-agent](https://github.com/dev-adelacruz/dev-agent) together.

Orc does **not** do any product or engineering work itself. It manages the handoffs, approval gates, and state between the two skills.

---

## Pipeline

```
/orc "your product idea"
       │
       ▼
  Phase 0 — Scaffold         (conditional — skipped if repo already exists)
  Create GitHub repo from template, apply branch protection
       │
       ▼
  Phase 1 — PRD              specter prd
  Generate a full Product Requirements Document
       │
       ▼
  ⏸ Approval gate — review .orc/prd.md and type "approve" to continue
       │
       ▼
  Phase 2 — Tickets          specter pm
  Scan codebase, create ordered Jira tickets, notify Slack
       │
       ▼
  Phase 3 — Sweep            dev-agent sweep
  Implement tickets in priority order, open PRs, post to Slack
```

Every phase writes its output to `.orc/` in the project root, so the pipeline is auditable and fully resumable from any point.

---

## Commands

| Command | What it does |
|---|---|
| `/orc [prompt]` | Start the pipeline (or resume from the current phase) |
| `/orc --from prd` | Re-run from Phase 1 — re-generate the PRD |
| `/orc --from tickets` | Re-run from Phase 2 — re-generate tickets from the existing PRD |
| `/orc --from sweep` | Re-run from Phase 3 — re-trigger sweep from existing tickets |
| `/orc status` | Show current pipeline state across all phases |

---

## Phase Details

### Phase 0 — Scaffold _(conditional)_

Skipped if `.orc/` already exists or if you provide a repo URL in your prompt.

When it runs:
- Creates a public GitHub repo from your template using `gh repo create --template`
- Ensures the default branch is `main`
- Applies branch protection to `main`: PR review required, no force pushes, enforces status checks if CI is present
- Initializes `.orc/state.json` with repo metadata

### Phase 1 — PRD

Delegates to `/specter prd` with your original prompt. The output is saved to `.orc/prd.md`.

**Approval gate:** orc stops here and asks you to review the PRD. You must type `approve` before the pipeline continues. You can also type `revise [feedback]` to regenerate it.

### Phase 2 — Tickets

Delegates to `/specter pm` with the approved PRD. Specter scans the codebase, creates ordered Jira tickets, and sends Slack notifications per ticket. A ticket manifest is saved to `.orc/tickets.md`.

### Phase 3 — Sweep

Delegates to `/dev-agent sweep`. Orc hands off entirely — all ticket routing, PR creation, and Slack posting is handled by dev-agent. Orc's role ends here.

---

## Resumability

Orc inspects `.orc/` state at startup to determine where to resume:

| State | Resumes at |
|---|---|
| `.orc/` missing | Phase 0 (Scaffold) |
| `.orc/prd.md` missing | Phase 1 (PRD) |
| `.orc/prd.md` exists, not approved | PRD approval gate |
| PRD approved, `.orc/tickets.md` missing | Phase 2 (Tickets) |
| `.orc/tickets.md` exists | Phase 3 (Sweep) |

Use `--from` flags to override and jump to any phase regardless of state.

---

## `.orc/` Directory

All pipeline state is written to `.orc/` in the project root. Commit this directory — it's shared state, not local tooling.

| File | Written by | Contents |
|---|---|---|
| `.orc/state.json` | Phase 0 | Repo slug, pipeline creation timestamp |
| `.orc/prd.md` | Phase 1 | Full PRD with frontmatter (`approved`, `approved_at`) |
| `.orc/tickets.md` | Phase 2 | Ticket manifest: keys, execution order, dependencies |

---

## Requirements

- [Claude Code](https://claude.ai/code) installed and authenticated
- **[specter](https://github.com/dev-adelacruz/specter)** installed (required for Phases 1 and 2)
- **[dev-agent](https://github.com/dev-adelacruz/dev-agent)** installed (required for Phase 3)
- `gh` CLI authenticated (`gh auth status`) — required for Phase 0
- Atlassian MCP configured — required for Phase 2 (Jira ticket creation)
- Slack MCP configured — required for Phase 2 notifications and Phase 3 sweep

Orc checks for specter and dev-agent at startup and will warn if either is missing before the phase that requires it.

---

## Install

### Option 1 — Script (recommended)

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/dev-adelacruz/orc/main/install.sh)
```

Or if you've already cloned the repo:

```sh
bash ~/.claude/skills/orc/install.sh
```

The script prompts you to choose between a global install (available in all projects) or a project-local install (this project only).

### Option 2 — Manual

**Global** (available in all Claude Code projects):

```sh
git clone https://github.com/dev-adelacruz/orc.git ~/.claude/skills/orc
```

**Project-local** (this project only — run from the project root):

```sh
git clone https://github.com/dev-adelacruz/orc.git .claude/skills/orc
# Optionally exclude from git:
echo '.claude/skills/' >> .gitignore
```

Restart Claude Code after installing. The skill is picked up automatically on next launch.

### Installing dependencies

Orc requires specter and dev-agent. Install both:

```sh
# specter
git clone https://github.com/dev-adelacruz/specter.git ~/.claude/skills/specter

# dev-agent
bash <(curl -fsSL https://raw.githubusercontent.com/dev-adelacruz/dev-agent/main/install.sh)
```

---

## Update

```sh
git -C ~/.claude/skills/orc pull
```

---

## Quick Start

```sh
# 1. Install orc (and its dependencies)
bash <(curl -fsSL https://raw.githubusercontent.com/dev-adelacruz/orc/main/install.sh)

# 2. In Claude Code, start a pipeline
/orc "Build a SaaS platform for managing software licenses across teams"

# 3. Review the PRD at .orc/prd.md, then approve
approve

# 4. Orc generates tickets and kicks off dev-agent sweep automatically
```

---

## Uninstall

```sh
rm -rf ~/.claude/skills/orc
```

This does not remove specter or dev-agent. Uninstall those separately if needed.
