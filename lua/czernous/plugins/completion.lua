-- Autocompletion: blink.cmp. Loads just after startup (LSP setup asks it what
-- it supports) and is ready before you first type.
--
-- Keys while the menu is open:
--   <C-n>/<C-p> or <Tab>/<S-Tab>  next / previous item
--   <CR>                          accept the selected item
--   <C-Space>                     open the menu (or toggle its documentation)
--   <C-b>/<C-f>                   scroll the documentation
--   <C-e>                         close the menu
--   <Tab>/<S-Tab> also jump between the placeholders of an expanded snippet.
return {
  {
    'saghen/blink.cmp',
    version = '*', -- tagged releases only
    event = 'InsertEnter',
    dependencies = { 'rafamadriz/friendly-snippets' }, -- snippet collection (data only)
    opts = {
      keymap = {
        preset = 'enter',
        ['<Tab>'] = { 'select_next', 'snippet_forward', 'fallback' },
        ['<S-Tab>'] = { 'select_prev', 'snippet_backward', 'fallback' },
      },
      -- Pure-Lua matcher: nothing is downloaded or compiled. (The optional
      -- native matcher is faster on huge lists; not worth a binary here.)
      fuzzy = { implementation = 'lua' },
      sources = {
        default = { 'lsp', 'path', 'snippets' },
        providers = {
          -- Snippets are matched loosely by default ("Pr" finds "coPyRight"), which
          -- is noise. Offer one only when what you typed is the START of its name,
          -- never right after a `.` or other trigger character, and rank them
          -- below real code suggestions so Enter never picks one by surprise.
          snippets = {
            score_offset = -20,
            min_keyword_length = 2,
            should_show_items = function(ctx) return ctx.trigger.initial_kind ~= 'trigger_character' end,
            transform_items = function(ctx, items)
              local typed = (ctx.line:sub(1, ctx.cursor[2]):match('[%w_]+$') or ''):lower()
              if typed == '' then return {} end
              return vim.tbl_filter(function(item)
                return (item.filterText or item.label or ''):lower():sub(1, #typed) == typed
              end, items)
            end,
          },
        },
      },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 150 },
      },
      signature = { enabled = true }, -- argument hints while typing a call
    },
  },
}
