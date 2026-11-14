#!/usr/bin/env sh
# Headless health check for this Neovim config.
#   ./tests/check.sh                      run all checks (exit code = failures)
#   ./tests/check.sh --tripwires          prove the standards checks can fail: load each
#                                         deliberate violation and insist its check FAILS
#   CHECK_ONLY=<lua pattern> ./tests/check.sh        run only matching checks (no languages)
#   CHECK_JAVA_PROJECT=~/dev/proj ./tests/check.sh   also open a real Java project
#   CHECK_CANARY=1 ./tests/check.sh       inject an error to prove errors are caught
cd "$(dirname "$0")/.." || exit 1

if [ "$1" = "--tripwires" ]; then
  failed=0
  for pair in blocking:no_blocking_calls global:no_global_writes reflection:no_reflection \
              deprecated:no_deprecated_api leak:no_buffer_state_leaks \
              whichkey:which_key_groups_used blocking_late:no_blocking_calls \
              blocking_static:no_blocking_calls leak_weak:no_buffer_state_leaks \
              eager:only_theme_loads_at_startup opaque:ui_is_transparent \
              statusline:statusline_is_cheap; do
    wire=${pair%%:*}; target=${pair##*:}
    out=$(CHECK_TRIPWIRE=$wire CHECK_ONLY="^$target\$" nvim --headless --cmd "luafile tests/check.lua" 2>&1)
    # The check must fail BECAUSE of the tripwire: its message has to name the
    # tripwire's own file or table. A check that merely crashed also prints FAIL.
    if printf '%s\n' "$out" | grep "^FAIL $target" | grep -qi "tripwire"; then
      echo "TRIPPED  $wire -> $target fails as it should"
    else
      echo "NOT TRIPPED  $wire -> $target did not fail: this check cannot be trusted"
      failed=$((failed + 1))
    fi
  done
  exit $failed
fi

exec nvim --headless --cmd "luafile tests/check.lua"
