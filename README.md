# Utilified — org `.github` repo

Shared GitHub Actions reusable workflows and org-level defaults for Utilified repositories.

## Reusable workflows

| Workflow | Purpose | Used by |
|---|---|---|
| `reusable-claude.yml` | `@claude` bot — responds to mentions in issues/comments | All repos |
| `reusable-dependabot-auto-merge.yml` | Auto-approve+merge Dependabot patch/minor/security PRs | All repos |
| `reusable-lock-file-npm.yml` | Weekly `npm install` + commit `package-lock.json` | Node repos |
| `reusable-lock-file-poetry.yml` | Weekly `poetry lock` + commit `poetry.lock` | Python repos |

## How to call from a service repo

Each service repo's `.github/workflows/` should contain thin caller files:

```yaml
# .github/workflows/claude.yml
name: Claude Code
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]
  pull_request_review:
    types: [submitted]
jobs:
  claude:
    uses: Utilified/.github/.github/workflows/reusable-claude.yml@main
    secrets:
      claude-code-oauth-token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

```yaml
# .github/workflows/dependabot-auto-merge.yml
name: Dependabot Auto Merge
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
jobs:
  auto-merge:
    uses: Utilified/.github/.github/workflows/reusable-dependabot-auto-merge.yml@main
```

```yaml
# .github/workflows/lock-file-maintenance.yml  (npm)
name: Lock File Maintenance
on:
  schedule:
    - cron: "30 10 * * 5"  # Fri 21:30 AEST / 10:30 UTC
  workflow_dispatch:
jobs:
  update:
    uses: Utilified/.github/.github/workflows/reusable-lock-file-npm.yml@main
```

```yaml
# .github/workflows/lock-file-maintenance.yml  (Poetry)
name: Lock File Maintenance
on:
  schedule:
    - cron: "30 10 * * 5"
  workflow_dispatch:
jobs:
  update:
    uses: Utilified/.github/.github/workflows/reusable-lock-file-poetry.yml@main
    with:
      python-version: "3.12"
```

## Not in this repo

Two workflows stay per-repo because their content is project-specific:

- `claude-code-review.yml` — `direct_prompt` differs meaningfully per codebase (Django, Next.js main, Next.js portal, CDK, MCP).
- `security.yml` — uses pip-audit (Python) or ecosystem-specific equivalents; content diverges.

## Setup

1. Create this repo on GitHub as `Utilified/.github` (the special org-level `.github` repo).
2. Copy the contents of this directory into it (including the hidden `.github/workflows/` subdirectory).
3. Push to `main`. Reusable workflows are immediately callable from any Utilified repo.
