-- The one place that decides how Neovim looks.
--
-- transparent = true: Neovim doesn't paint the editor background, so your
-- terminal's background (and its transparency/blur) shows through. Works with
-- any colorscheme -- it's re-applied every time a colorscheme loads. Popups
-- (completion, hover, Telescope, which-key) keep a solid background so they
-- stay readable.  Toggle at runtime: <leader>tT.
--
-- Later (Nix/Stylix) these options will be set from outside.

local M = {}

M.opts = {
  colorscheme = 'onedark',
  transparent = true,
}

-- Editor-area groups whose background is removed.
local editor_groups = {
  'Normal', 'NormalNC', 'SignColumn', 'EndOfBuffer', 'LineNr', 'LineNrAbove',
  'LineNrBelow', 'CursorLineNr', 'FoldColumn', 'WinSeparator', 'VertSplit',
  'GitSignsAdd', 'GitSignsChange', 'GitSignsDelete',
}

-- Popup groups that must keep a background even if the theme links them to Normal.
local float_groups = {
  'NormalFloat', 'FloatBorder', 'FloatTitle', 'Pmenu', 'PmenuSel',
  'TelescopeNormal', 'TelescopeBorder', 'WhichKeyNormal', 'TreesitterContext',
}

local function apply_transparency()
  if not M.opts.transparent then return end
  -- Pin popups to their current resolved colours (breaks any link to Normal).
  for _, name in ipairs(float_groups) do
    local resolved = vim.api.nvim_get_hl(0, { name = name, link = false })
    if resolved.bg then vim.api.nvim_set_hl(0, name, resolved) end
  end
  for _, name in ipairs(editor_groups) do
    local attrs = vim.api.nvim_get_hl(0, { name = name, link = false })
    attrs.bg, attrs.ctermbg = nil, nil
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('czernous_theme', { clear = true }),
    desc = 'Apply transparent background',
    callback = apply_transparency,
  })
  vim.cmd.colorscheme(M.opts.colorscheme)
end

function M.toggle_transparency()
  M.opts.transparent = not M.opts.transparent
  vim.cmd.colorscheme(vim.g.colors_name or M.opts.colorscheme)
end

return M
