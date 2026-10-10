# Dependency-update standard

Org reference for how every Utilified repo keeps dependencies current.

## Dependabot (`.github/dependabot.yml`)

One entry per ecosystem present:

- Schedule (05:00 Australia/Melbourne, so PRs and CI settle before the 08:30 daily PR sweep): language ecosystems weekly on Saturday; github-actions, docker and gitsubmodule monthly. Actions and base-image bumps land in every repo at once, so monthly cuts the cross-repo PR churn without delaying security fixes (those bypass the schedule).
- Cooldown: default 5 days; npm/pip entries also semver-major 7, semver-minor 5, semver-patch 3 (Dependabot rejects the semver-* keys for github-actions, docker and gitsubmodule).
- `open-pull-requests-limit`: 5 for language ecosystems (npm/pip/poetry), 3 for github-actions/docker/gitsubmodule.
- `assignees: [cohenrobinson]`, `labels: [dependencies, <ecosystem>]`, `target-branch: main`.
- Language ecosystems: group minor/patch (npm: `production-minor-patch` plus `development-deps` by dependency type; pip: `minor-patch-updates` on `*`). Also a `security-updates` group (`applies-to: security-updates`, `*`, minor/patch) so advisory fixes arrive as one PR. Majors stay ungrouped. Keep existing repo-specific groups and ignores (e.g. the aws-cdk lockstep group, react group, eslint ignore) and their comments.
- github-actions: group `github-actions-all` on `*`.
- docker: one entry per directory containing a Dockerfile, group `docker-all` on `*`.
- gitsubmodule (parent monorepo only): group all.

## Auto-merge

`reusable-dependabot-auto-merge.yml` approves and auto-merges semver-patch and semver-minor updates, including security fixes. Majors always get a manual-review comment, flagged as a security update when they fix an advisory. Packages on the org-wide denylist (plus any caller `extra-denylist`) always need manual review.

## Workflows

- Pin every `uses:` that isn't a local `./` path to a full 40-char commit SHA with a trailing `# vX.Y.Z` comment. Use the major already referenced, resolved to its exact latest release tag; don't upgrade majors while pinning. Resolve with `gh api repos/OWNER/REPO/commits/TAG -q .sha` (for annotated tags, `git ls-remote https://github.com/OWNER/REPO refs/tags/TAG^{}`).
- Calls to `Utilified/.github/.github/workflows/*.yml@main` are pinned to a commit SHA with a `# main` comment; Dependabot's github-actions ecosystem bumps it.
- The first step of each job in CI/security workflows that run third-party code is `step-security/harden-runner` (pinned) with `egress-policy: audit`. Jobs that only call reusable workflows are exempt.
- Top-level `permissions:` is least-privilege (`contents: read` by default) where missing.
