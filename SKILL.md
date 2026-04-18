---
name: orc
description: >
  Orc is a pipeline orchestrator that chains specter and dev-agent together into a full
  product delivery workflow. Trigger this skill whenever the user invokes "/orc" or asks to
  run the full pipeline from idea → PRD → tickets → implementation.

  Orc does NOT do any dev or product work itself. It coordinates handoffs between specter
  (product) and dev-agent (engineering) and manages approval gates between phases.

  Phases:
    Phase 0 — Scaffold (conditional): Create GitHub repo from template if no repo exists.
    Phase 1 — PRD: Run specter prd mode. Approval gate before continuing.
    Phase 2 — Tickets: Run specter pm mode using the approved PRD.
    Phase 3 — Sweep: Run dev-agent sweep using the generated tickets.

  Invocations:
    /orc [prompt]              — start pipeline from the beginning (or resume from current phase)
    /orc --from prd            — re-run from Phase 1 (re-generate PRD)
    /orc --from tickets        — re-run from Phase 2 (re-generate tickets from existing PRD)
    /orc --from sweep          — re-run from Phase 3 (re-run sweep from existing tickets)
    /orc status                — show current pipeline state
---

# Orc — Pipeline Orchestrator

Orc chains specter and dev-agent into a linear four-phase pipeline. It writes all intermediate
outputs to `.orc/` so the pipeline is resumable and auditable. It does **not** implement any
product or engineering logic itself — it delegates entirely to the appropriate skill for each phase.

---

## Phase Detection (always run first)

Before doing anything else, determine which phase to start from.

### 1. Check for `--from` flag
If the user invoked with `--from prd`, `--from tickets`, or `--from sweep`: jump directly to that
phase. Skip all earlier phases unconditionally.

### 2. Otherwise: inspect `.orc/` state

| Condition | Action |
|---|---|
| `.orc/` does not exist | Start at Phase 0 (Scaffold) |
| `.orc/prd.md` does not exist | Start at Phase 1 (PRD) |
| `.orc/prd.md` exists, no `approved: true` in frontmatter | Resume at PRD approval gate |
| `.orc/prd.md` approved but `.orc/tickets.md` does not exist | Start at Phase 2 (Tickets) |
| `.orc/tickets.md` exists | Start at Phase 3 (Sweep) |

Print a one-line status before proceeding:
```
[orc] Resuming from Phase N — [phase name]
```
or for a fresh start:
```
[orc] Starting pipeline from Phase 0
```

---

## Phase 0 — Scaffold (Conditional)

**Skip this phase entirely** if either:
- `.orc/` already exists (project was previously initialized), OR
- The user provided a repo URL in their prompt (e.g. `https://github.com/org/repo`)

If skipping, print:
```
[orc] Phase 0 skipped — repo already configured
```
Then proceed to Phase 1.

### Step 0.1 — Collect repo details

Ask the user:
1. GitHub organization or username (e.g. `myorg`)
2. New repo name (e.g. `myapp`)
3. Template repo to use (URL or `owner/repo` slug)

Confirm before creating:
```
Creating GitHub repo: myorg/myapp
  Template: [TEMPLATE_REPO]
  Visibility: public
  Default branch: main

Proceed? (yes / no)
```

Wait for confirmation before running any `gh` commands.

### Step 0.2 — Create repo from template

```bash
gh repo create myorg/myapp \
  --template [TEMPLATE_REPO] \
  --public \
  --clone
```

After creation, verify the default branch is `main`:
```bash
gh api repos/myorg/myapp --jq '.default_branch'
```
If not `main`, rename it:
```bash
gh api repos/myorg/myapp -X PATCH -f default_branch=main
```

### Step 0.3 — Apply branch protection to `main`

```bash
gh api repos/myorg/myapp/branches/main/protection \
  -X PUT \
  --input - <<'EOF'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1
  },
  "restrictions": null
}
EOF
```

If the repo has CI configured (`.github/workflows/` exists), set `required_status_checks`:
```bash
gh api repos/myorg/myapp/branches/main/protection \
  -X PUT \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": []
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1
  },
  "restrictions": null
}
EOF
```

### Step 0.4 — Initialize `.orc/`

```bash
mkdir -p .orc
```

Create `.orc/state.json`:
```json
{
  "repo": "myorg/myapp",
  "created_at": "<ISO8601>",
  "current_phase": 0
}
```

Print:
```
[orc] Phase 0 complete — repo myorg/myapp created and protected
```

---

## Phase 1 — PRD

### Step 1.1 — Resume check

If `.orc/prd.md` exists and has `approved: true` in its frontmatter:
```
[orc] PRD already approved — skipping Phase 1
```
Jump to Phase 2.

If `.orc/prd.md` exists but is **not** approved, print:
```
[orc] Found existing PRD draft. Resuming approval gate.
```
Skip to Step 1.3 (Approval Gate).

### Step 1.2 — Invoke specter prd

Pass the user's original prompt to specter's PRD mode. Do not rewrite, summarize, or modify the
prompt — hand it through as-is.

Instruct specter to write its PRD output to `.orc/prd.md` instead of Google Drive or a docx.
The file must include this frontmatter block at the top:
```markdown
---
approved: false
approved_at:
orc_phase: 1
---
```

After specter completes, confirm the file was written:
```
[orc] PRD written to .orc/prd.md
```

### Step 1.3 — Approval Gate

**STOP HERE.** Do not proceed to Phase 2 without explicit user approval.

Print:
```
[orc] ⏸  Approval required

The PRD has been written to .orc/prd.md. Review it before continuing.

When you're ready:
  • Type "approve" to proceed to ticket generation
  • Type "revise [feedback]" to regenerate the PRD with your notes
  • Type "orc status" to review the current pipeline state
```

Wait for the user's response.

**If "approve":** update `.orc/prd.md` frontmatter:
```markdown
---
approved: true
approved_at: <ISO8601>
orc_phase: 1
---
```
Print:
```
[orc] PRD approved — proceeding to Phase 2 (Tickets)
```
Then continue to Phase 2.

**If "revise [feedback]":** re-run Step 1.2, appending the user's feedback to the prompt:
```
[original prompt]

Revision notes: [feedback]
```
Then return to Step 1.3.

---

## Phase 2 — Tickets

### Step 2.1 — Resume check

If `.orc/tickets.md` exists, print:
```
[orc] Tickets already generated — skipping Phase 2
```
Jump to Phase 3.

### Step 2.2 — Invoke specter pm

Pass the content of `.orc/prd.md` to specter's PM mode. Instruct specter to:
1. Use the PRD as its source
2. Create Jira tickets as normal (specter pm mode handles all Jira/Slack logic)
3. Write a ticket manifest to `.orc/tickets.md` after all tickets are created

The `.orc/tickets.md` manifest format:
```markdown
# Ticket Manifest
Generated: <ISO8601>

## Epics
- [PROJ-1] Epic Name
- [PROJ-2] Epic Name

## Stories (by execution order)
1. [PROJ-3] Story Name — Status: To Do — Depends on: none
2. [PROJ-4] Story Name — Status: To Do — Depends on: PROJ-3
...
```

After specter completes, confirm:
```
[orc] Tickets created and manifest written to .orc/tickets.md
[orc] Proceeding to Phase 3 (Sweep)
```

---

## Phase 3 — Sweep

### Step 3.1 — Invoke dev-agent sweep

Trigger dev-agent sweep mode. Orc does not pass ticket keys manually — sweep reads from Jira
directly using the project config in `.claude/dev-agent.json`. This is the same sweep mode
behavior as running `/dev-agent sweep` directly.

Print before delegating:
```
[orc] Phase 3 — Handing off to dev-agent sweep
```

Dev-agent sweep takes over from here. Orc's role ends when sweep begins. All sweep output,
PR creation, and Slack notifications are handled by dev-agent sweep.

---

## Command: `/orc status`

Print a summary of the current pipeline state:

```
[orc] Pipeline Status
─────────────────────────────────────────────────────
Phase 0 — Scaffold:  ✅ complete  (repo: myorg/myapp)
Phase 1 — PRD:       ✅ approved  (.orc/prd.md, approved 2h ago)
Phase 2 — Tickets:   ✅ complete  (.orc/tickets.md, 12 tickets)
Phase 3 — Sweep:     🔄 in progress (check /dev-agent sweep output)
─────────────────────────────────────────────────────
```

Derive status from:
- `.orc/state.json` — repo and creation timestamp
- `.orc/prd.md` frontmatter — `approved` flag and `approved_at`
- `.orc/tickets.md` — presence and ticket count (count lines starting with `- [`)
- `.claude/sweep-checkpoint.json` — sweep progress (read-only, do not modify)

If `.orc/` doesn't exist: "No pipeline found in this project. Run /orc [prompt] to start."

---

## `.orc/` Directory Reference

| File | Written by | Purpose |
|---|---|---|
| `.orc/state.json` | Phase 0 | Repo metadata, pipeline creation timestamp |
| `.orc/prd.md` | Phase 1 | Full PRD output from specter; frontmatter tracks approval |
| `.orc/tickets.md` | Phase 2 | Ticket manifest (keys, order, dependencies) |

All `.orc/` files should be committed to the repo so the pipeline state is shared across machines.
Add `.orc/` to the repo (do **not** gitignore it).

---

## Error Handling

- **Phase 0 fails** (repo creation error): print the `gh` error output, stop, and ask the user to resolve manually. Do not retry automatically.
- **specter fails or produces no output**: print the error, stop, and prompt the user to re-run with `/orc --from prd` or `/orc --from tickets`.
- **dev-agent sweep fails**: orc defers entirely to dev-agent's own error handling. Do not wrap or suppress sweep errors.
- **`.orc/prd.md` is malformed** (missing frontmatter): treat as unapproved and resume at the approval gate.

---

## Design Constraints

- Orc is a coordinator only. It does not write code, create Jira tickets, generate PRDs, or post to Slack. It delegates all of that to specter and dev-agent.
- Do not duplicate any logic from specter or dev-agent. If a behavior belongs to those skills, invoke them — don't reimplement.
- Each phase writes to `.orc/` before handing off, so any phase can be re-run in isolation with `--from`.
- The approval gate in Phase 1 is mandatory and cannot be skipped (except with `--from tickets` or `--from sweep`, which imply the PRD was already approved).
