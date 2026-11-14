-- The one place that decides how Neovim looks.
--
-- WHAT supplies the colours:
--   * by default a hand-tuned colour scheme, one per polarity (M.themes);
--   * or, if the environment provides one, a 16-colour base16 PALETTE file
--     ($NVIM_BASE16_PALETTE = path to JSON like palettes/*.json). That is how
--     Stylix themes Neovim on Nix; any other Neovim config can read the same file.
--
-- Whatever supplies them, the same rules give the UI one consistent structure:
--   1. Polarity follows the terminal. Neovim detects a dark or light terminal
--      ('background'); only a theme of that kind can be active.
--   2. Transparency is all-or-nothing. With `transparent = true`, the theme's
--      own background shades (whatever it paints the editor, popups, menus and
--      status areas with) are found, and EVERY highlight group using one of them
--      loses its background -- by scanning all groups, so pickers, completion,
--      hover and any future plugin follow without being named. Only the ACCENTS
--      keep a background: the things you must be able to see. Popups stay
--      readable through their border ('winborder').
--   3. The result is cached, so a start costs ~0.6 ms instead of ~3 ms and the
--      theme plugin is not even loaded.
--
-- Toggle transparency at runtime: <leader>tT.

local M = {}

M.opts = { transparent = true }

--- Hand-tuned colour schemes, one per terminal polarity. `plugin` is the
--- lazy.nvim name (loaded only when the cache has to be rebuilt).
M.themes = {
  dark = {
    name = 'catppuccin-mocha',
    plugin = 'catppuccin',
    load = function()
      require('catppuccin').setup({ flavour = 'mocha' })
      vim.cmd.colorscheme('catppuccin')
    end,
  },
  light = {
    name = 'catppuccin-latte',
    plugin = 'catppuccin',
    load = function()
      require('catppuccin').setup({ flavour = 'latte' })
      vim.cmd.colorscheme('catppuccin')
    end,
  },
}

--- Highlight groups that must stay visible (selection, search, current line, diffs).
M.accents = { 'Visual', 'VisualNOS', 'CursorLine', 'CursorColumn', 'PmenuSel', 'PmenuThumb', 'Search', 'CurSearch',
  'IncSearch', 'Substitute', 'DiffAdd', 'DiffChange', 'DiffDelete', 'DiffText', 'MatchParen', 'TelescopeSelection',
  'QuickFixLine', 'WildMenu', 'ColorColumn' }

-- Built-in groups a theme paints its surfaces with. Their background colours ARE
-- the theme's "background shades"; nothing else is named anywhere.
local surfaces = { 'Normal', 'NormalNC', 'NormalFloat', 'FloatBorder', 'FloatTitle', 'Pmenu', 'PmenuSbar',
  'StatusLine', 'StatusLineNC', 'TabLine', 'TabLineFill', 'WinBar', 'WinBarNC', 'SignColumn', 'FoldColumn',
  'LineNr', 'CursorLineNr', 'EndOfBuffer', 'WinSeparator', 'Folded' }

--- The active theme: { name, variant = 'dark'|'light', palette? (base16 table) }.
M.current = nil
--- Background colours (numbers) the active theme used for its surfaces.
M.shades = {}

local applying = false

--------------------------------------------------------------------------------
-- base16 palettes (environment-supplied)
--------------------------------------------------------------------------------
--- Read a palette file. Returns the palette or nil + reason.
function M.load_file(path)
  local fd = io.open(path, 'r')
  if not fd then return nil, 'cannot read ' .. path end
  local text = fd:read('*a')
  fd:close()
  local ok, palette = pcall(vim.json.decode, text)
  if not ok or type(palette) ~= 'table' then return nil, path .. ' is not valid JSON' end
  for i = 0, 15 do
    local key = ('base%02X'):format(i)
    if type(palette[key]) ~= 'string' then return nil, path .. ' has no ' .. key end
  end
  palette.name = palette.name or vim.fn.fnamemodify(path, ':t:r')
  palette.variant = palette.variant or 'dark'
  return palette
end

local function palette_theme(palette)
  local colors = {}
  for i = 0, 15 do
    local key = ('base%02X'):format(i)
    colors[key] = palette[key]
  end
  return {
    name = 'base16-' .. palette.name,
    variant = palette.variant,
    palette = palette,
    load = function() require('mini.base16').setup({ palette = colors, use_cterm = false }) end,
  }
end

--------------------------------------------------------------------------------
-- The rules
--------------------------------------------------------------------------------
local function accent_set()
  local set = {}
  for _, name in ipairs(M.accents) do set[name] = true end
  return set
end

--- Rule 2: no group but an accent may paint one of the theme's background shades.
--- Also used for groups that plugins define later.
function M.restyle()
  if not M.opts.transparent then return end
  local accent, shades = accent_set(), M.shades
  for name, def in pairs(vim.api.nvim_get_hl(0, {})) do
    if def.bg and shades[def.bg] and not accent[name] then
      def.bg, def.ctermbg = nil, nil
      vim.api.nvim_set_hl(0, name, def)
    end
  end
end

local function style()
  -- which colours does this theme use for its surfaces?
  local shades = {}
  for _, name in ipairs(surfaces) do
    local bg = vim.api.nvim_get_hl(0, { name = name, link = false }).bg
    if bg then shades[bg] = true end
  end
  M.shades = shades
  M.restyle()
  -- Borders separate a popup from the code behind it: quiet, never loud.
  local comment = vim.api.nvim_get_hl(0, { name = 'Comment', link = false }).fg
  vim.api.nvim_set_hl(0, 'FloatBorder', { fg = comment })
  vim.api.nvim_set_hl(0, 'WinSeparator', { fg = comment })
end

--------------------------------------------------------------------------------
-- Cache: working out ~950 highlight groups costs ~3 ms on every start, whatever
-- the theme (measured); replaying a saved copy costs ~0.6 ms and needs no plugin.
-- Written only from a clean start (before other plugins add their groups),
-- thrown away whenever plugins are updated. Bump CACHE_VERSION when the rules
-- above change. The key is compared as plain text (hashing it cost 3.9 ms).
--------------------------------------------------------------------------------
local CACHE_VERSION = 3
local cache_dir = vim.fn.stdpath('cache') .. '/czernous-theme'

local function cache_key(theme)
  local parts = { tostring(CACHE_VERSION), theme.name, tostring(M.opts.transparent), vim.env.VIMRUNTIME or '' }
  if theme.palette then
    for i = 0, 15 do parts[#parts + 1] = theme.palette[('base%02X'):format(i)] end
  end
  return table.concat(parts, '|')
end

local function cache_file(theme)
  return ('%s/%s-%s.json'):format(cache_dir, (theme.name:gsub('[^%w_-]', '_')), M.opts.transparent and 'transparent' or 'solid')
end

local function apply_cached(theme)
  local fd = io.open(cache_file(theme), 'r')
  if not fd then return false end
  local text = fd:read('*a')
  fd:close()
  local ok, saved = pcall(vim.json.decode, text)
  if not ok or type(saved) ~= 'table' or saved.key ~= cache_key(theme) or type(saved.groups) ~= 'table' then return false end
  applying = true
  for name, def in pairs(saved.groups) do
    -- Without an explicit (empty) cterm table Neovim copies bold/italic into the
    -- 256-colour attributes too, and the result would differ from a fresh start.
    if def.cterm == nil then def.cterm = {} end
    vim.api.nvim_set_hl(0, name, def)
  end
  local shades = {}
  for _, bg in ipairs(saved.shades or {}) do shades[bg] = true end
  M.shades = shades
  vim.o.background = theme.variant
  M.current = theme
  applying = false
  return true
end

local function write_cache(theme)
  vim.fn.mkdir(cache_dir, 'p')
  local fd = io.open(cache_file(theme), 'w')
  if not fd then return end
  fd:write(vim.json.encode({ key = cache_key(theme), shades = vim.tbl_keys(M.shades), groups = vim.api.nvim_get_hl(0, {}) }))
  fd:close()
end

local function apply(theme)
  applying = true
  theme.load()
  -- Colour-scheme plugins register themselves as the active scheme; Neovim would
  -- then reload them (without our rules) whenever 'background' changes. We
  -- follow 'background' ourselves instead.
  vim.g.colors_name = nil
  vim.o.background = theme.variant
  M.current = theme
  style()
  applying = false
  -- Let other parts of the UI (the statusline) pick up the new colours.
  vim.api.nvim_exec_autocmds('User', { pattern = 'CzernousTheme', modeline = false })
end

--- Theme for the current terminal polarity (or the palette supplied from outside).
local function pick()
  local external = vim.env.NVIM_BASE16_PALETTE
  if external and external ~= '' then
    local palette, err = M.load_file(external)
    if palette then return palette_theme(palette) end
    vim.notify('NVIM_BASE16_PALETTE: ' .. err .. '; using the built-in theme', vim.log.levels.WARN)
  end
  local variant = vim.o.background == 'light' and 'light' or 'dark'
  local theme = M.themes[variant]
  theme.variant = variant
  return theme
end

function M.setup()
  local theme = pick()
  if not apply_cached(theme) then
    apply(theme)
    write_cache(theme) -- clean start: only Neovim's and the theme's groups exist
  end

  local group = vim.api.nvim_create_augroup('czernous_theme', { clear = true })
  -- Plugins that load later define their own groups; apply the same rule to them.
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'LazyLoad', 'VeryLazy' },
    callback = function() if M.current then M.restyle() end end,
  })
  -- Plugin updates can change what a theme produces: start the cache afresh.
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'LazyUpdate', 'LazySync', 'LazyInstall', 'LazyRestore' },
    callback = function() vim.fs.rm(cache_dir, { recursive = true, force = true }) end,
  })
  -- The terminal switched between dark and light: follow it.
  vim.api.nvim_create_autocmd('OptionSet', {
    group = group,
    pattern = 'background',
    callback = function()
      if applying then return end
      apply(pick())
    end,
  })
end

--- Ask for the dark or light theme explicitly. Refused if it doesn't match the
--- terminal: a light theme on a dark terminal (or the reverse) is never applied.
function M.use(variant)
  if variant ~= vim.o.background then
    vim.notify(('Theme: the terminal is %s; the %s theme is not applied'):format(vim.o.background, variant), vim.log.levels.WARN)
    return false
  end
  apply(pick())
  return true
end

function M.toggle_transparency()
  M.opts.transparent = not M.opts.transparent
  if M.current then apply(M.current) end
end

return M
