-- Exceptions to the engineering-standards checks. Every entry needs a reason;
-- an entry without one is a bug. Prefer fixing the code to adding a line here.
return {
  -- { file = <path fragment>, call = <call fragment>, reason = <why it is acceptable> }
  blocking = {
    -- First run on a new machine only: fetch the plugin manager itself. Nothing
    -- else can run before it exists, so blocking is correct here.
    { file = 'lua/czernous/lazy.lua', call = 'vim.fn.system', reason = 'one-time plugin manager bootstrap' },
    -- Asked once per $PATH value, the first time a file needs a parser that isn't
    -- installed; the answer is cached. Not at startup, not per keystroke.
    { file = 'lua/czernous/treesitter.lua', call = 'vim.fn.executable', reason = 'tree-sitter CLI lookup, cached per $PATH' },
    -- Evaluated once, when rust-analyzer's settings are first resolved.
    { file = 'after/lsp/rust_analyzer.lua', call = 'vim.fn.executable', reason = 'leptosfmt lookup, once per session' },
  },
}
