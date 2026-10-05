#!/usr/bin/env bash
# Plants each form of the org token in a temp tree and checks the leak gate's
# pattern (tools/org-token.pattern) matches the leaks and spares the look-alikes.
# The token is built with printf so this file never spells it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pattern="$root/tools/org-token.pattern"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
t() { printf 'e%s' 98; }

hits() { grep -rniEf "$pattern" "$tmp" >/dev/null 2>&1; }

expect() { # expect match|clear <label> <line>
  local want="$1" label="$2" line="$3"
  rm -f "$tmp"/*
  printf '%s\n' "$line" >"$tmp/case.txt"
  if hits; then got=match; else got=clear; fi
  if [[ "$got" != "$want" ]]; then
    echo "FAIL $label: wanted $want, got $got"
    fail=1
  else
    echo "ok   $label"
  fi
}

expect match "env letter d" "see $(t)d here"
expect match "env letter s" "see $(t)s here"
expect match "env letter p" "see $(t)p here"
expect match "bare prefix with hyphen" "the $(t)-architect said"
expect match "bare token alone" "team $(t) and arcaven"
expect match "bare token at line end" "on the $(t)"
expect match "bare token upper case" "the $(printf 'E%s' 98)-builder"
expect match "bare token before punctuation" "($(t)), then"
expect clear "short sha before comma" "marvel c99c$(t), and"
expect clear "css hex color" "--mark:#fd$(t)b; --mark-ink:#1c1e20;"
expect clear "token inside a longer word" "ide$(t)x"
expect clear "plain prose" "a client team's architect"

exit "$fail"
