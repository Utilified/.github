#!/usr/bin/env bash
# Exercises the "Refuse a refresh that drops libc discriminators" guard in
# .github/workflows/reusable-lock-file-npm.yml.
#
# The guard has to live inline in the workflow: a reusable workflow's steps run
# against the *caller's* checkout, so a script file in this repo is not on disk
# at runtime. To avoid a second copy drifting from the real one, this harness
# extracts the step's `run:` block straight out of the YAML and executes that.
#
# Usage: tests/lock-file-libc-guard.test.sh
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workflow="$repo_root/.github/workflows/reusable-lock-file-npm.yml"
step_name="Refuse a refresh that drops libc discriminators"

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

guard="$sandbox/guard.sh"

# Pull the step's shell body out of the YAML, dedented. Deliberately dependency
# free (no PyYAML, no yq) so this runs anywhere bash and jq do.
awk -v want="      - name: $step_name" '
  !in_step { if ($0 == want) in_step = 1; next }
  !in_run  {
    if ($0 == "        run: |") { in_run = 1; next }
    if ($0 ~ /^      - /) exit 1
    next
  }
  {
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    if ($0 !~ /^          /) exit 0
    print substr($0, 11)
  }
' "$workflow" > "$guard" || { echo "FATAL: no 'run:' block for step \"$step_name\" in $workflow"; exit 1; }

[ -s "$guard" ] || { echo "FATAL: could not extract the guard from $workflow"; exit 1; }
chmod +x "$guard"

failures=0

# make_lock <path> <json>
make_lock() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

# scratch <name> — a git repo whose HEAD holds the "before" lock file
scratch() {
  local dir="$sandbox/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name Test
  printf '%s\n' "$dir"
}

commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

# expect <case> <expected-exit: pass|fail> <dir>
expect() {
  local name="$1" want="$2" dir="$3" out status
  out=$(cd "$dir" && bash "$guard" 2>&1); status=$?
  local got=pass; [ "$status" -ne 0 ] && got=fail
  printf '%s\n' "--- $name"
  printf '%s\n' "$out" | sed 's/^/    /'
  if [ "$got" = "$want" ]; then
    printf '    => %s (exit=%d)  OK\n\n' "$got" "$status"
  else
    printf '    => %s (exit=%d)  EXPECTED %s  ** FAILURE **\n\n' "$got" "$status" "$want"
    failures=$((failures + 1))
  fi
}

# A lock file entry helper: with and without the libc discriminator.
NATIVE_WITH='{"lockfileVersion":3,"packages":{"":{"name":"app"},
 "node_modules/@img/sharp-linux-x64":{"version":"0.33.0","os":["linux"],"cpu":["x64"],"libc":["glibc"]},
 "node_modules/@img/sharp-linuxmusl-x64":{"version":"0.33.0","os":["linux"],"cpu":["x64"],"libc":["musl"]},
 "node_modules/lodash":{"version":"4.17.21"}}}'
NATIVE_LOST_ONE='{"lockfileVersion":3,"packages":{"":{"name":"app"},
 "node_modules/@img/sharp-linux-x64":{"version":"0.33.0","os":["linux"],"cpu":["x64"]},
 "node_modules/@img/sharp-linuxmusl-x64":{"version":"0.33.0","os":["linux"],"cpu":["x64"],"libc":["musl"]},
 "node_modules/lodash":{"version":"4.17.21"}}}'
NATIVE_LOST_ONE_GAINED_ONE='{"lockfileVersion":3,"packages":{"":{"name":"app"},
 "node_modules/@img/sharp-linux-x64":{"version":"0.33.0","os":["linux"],"cpu":["x64"]},
 "node_modules/@img/sharp-linuxmusl-x64":{"version":"0.33.0","os":["linux"],"cpu":["x64"],"libc":["musl"]},
 "node_modules/@rollup/rollup-linux-x64-gnu":{"version":"4.9.0","os":["linux"],"cpu":["x64"],"libc":["glibc"]},
 "node_modules/lodash":{"version":"4.17.21"}}}'
NATIVE_BUMPED='{"lockfileVersion":3,"packages":{"":{"name":"app"},
 "node_modules/@img/sharp-linux-x64":{"version":"0.33.5","os":["linux"],"cpu":["x64"],"libc":["glibc"]},
 "node_modules/@img/sharp-linuxmusl-x64":{"version":"0.33.5","os":["linux"],"cpu":["x64"],"libc":["musl"]},
 "node_modules/lodash":{"version":"4.17.21"}}}'
NATIVE_DROPPED_DEP='{"lockfileVersion":3,"packages":{"":{"name":"app"},
 "node_modules/@img/sharp-linuxmusl-x64":{"version":"0.33.0","os":["linux"],"cpu":["x64"],"libc":["musl"]},
 "node_modules/lodash":{"version":"4.17.21"}}}'

# ---------------------------------------------------------------- CASE A
# The case the guard was written for: an entry loses its libc key outright.
d=$(scratch case-a)
make_lock "$d/package-lock.json" "$NATIVE_WITH"; commit_all "$d" before
make_lock "$d/package-lock.json" "$NATIVE_LOST_ONE"
expect "CASE A: existing entry loses libc, nothing gains one" fail "$d"

# ---------------------------------------------------------------- CASE B
# Churn: one entry loses its key while a newly added native package brings its
# own. A net count of removed-vs-added lines cancels to zero here.
d=$(scratch case-b)
make_lock "$d/package-lock.json" "$NATIVE_WITH"; commit_all "$d" before
make_lock "$d/package-lock.json" "$NATIVE_LOST_ONE_GAINED_ONE"
expect "CASE B: entry loses libc (-1) while a new native pkg gains one (+1)" fail "$d"

# ---------------------------------------------------------------- CASE C
# Nothing to inspect: no lock file at the repository root. A guard that
# inspected nothing must not report success.
d=$(scratch case-c)
make_lock "$d/apps/web/package-lock.json" "$NATIVE_WITH"; commit_all "$d" before
make_lock "$d/apps/web/package-lock.json" "$NATIVE_LOST_ONE"
expect "CASE C: no package-lock.json at the repo root (inspects nothing)" fail "$d"

# ---------------------------------------------------------------- CASE D
# Control: a clean refresh that bumps versions and keeps every libc key.
d=$(scratch case-d)
make_lock "$d/package-lock.json" "$NATIVE_WITH"; commit_all "$d" before
make_lock "$d/package-lock.json" "$NATIVE_BUMPED"
expect "CASE D: version bump, every libc key retained" pass "$d"

# ---------------------------------------------------------------- CASE E
# Control: the dependency is genuinely gone, key and entry together. Removing a
# package must not be mistaken for stripping its discriminator.
d=$(scratch case-e)
make_lock "$d/package-lock.json" "$NATIVE_WITH"; commit_all "$d" before
make_lock "$d/package-lock.json" "$NATIVE_DROPPED_DEP"
expect "CASE E: native dependency removed entirely (entry and key)" pass "$d"

# ---------------------------------------------------------------- CASE F
# Control: the refresh was a no-op. Must be reported as unchanged, not as
# verified-clean.
d=$(scratch case-f)
make_lock "$d/package-lock.json" "$NATIVE_WITH"; commit_all "$d" before
expect "CASE F: refresh left the lock file untouched" pass "$d"

if [ "$failures" -ne 0 ]; then
  echo "$failures case(s) behaved incorrectly."
  exit 1
fi
echo "All cases behaved as expected."
