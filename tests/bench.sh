#!/usr/bin/env sh
# Benchmarks for this Neovim config (startup, file open, completion, allocations).
#   ./tests/bench.sh --label mychange          run twice, write tests/bench/mychange.json
#   ./tests/bench.sh --runs 20 --label x       more samples per measure (default 10)
#   ./tests/bench.sh --config DIR --label x    benchmark another config; DIR holds
#                                              config/nvim, data/, state/, cache/
# Uses your real $PATH on purpose: that is what you experience.
cd "$(dirname "$0")/.." || exit 1
exec nvim --headless -u NONE -l tests/bench.lua "$@"
