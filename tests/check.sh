#!/usr/bin/env sh
# Headless health check for this Neovim config.
#   ./tests/check.sh                      run all checks (exit code = failures)
#   CHECK_JAVA_PROJECT=~/dev/proj ./tests/check.sh   also open a real Java project
cd "$(dirname "$0")/.." || exit 1
exec nvim --headless --cmd "luafile tests/check.lua"
