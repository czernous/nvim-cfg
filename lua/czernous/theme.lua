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
--   3. "The selected item" looks the same everywhere. Any group that marks a
--      selection (its name ends in Sel, Selection or Selected: completion menu,
--      picker, wildmenu, any plugin) gets the theme's own selection colour.
--   4. The result is cached, so a start costs ~0.6 ms instead of ~3 ms and the
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
local restyle_pending = false

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
  if palette.variant ~= 'dark' and palette.variant ~= 'light' then
    -- not stated: a palette whose background (base00) is bright is a light one
    local n = tonumber(palette.base00:sub(2), 16) or 0
    local r, g, b = math.floor(n / 65536), math.floor(n / 256) % 256, n % 256
    palette.variant = (0.299 * r + 0.587 * g + 0.114 * b) > 128 and 'light' or 'dark'
  end
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
local accent_names = nil
local function accent_set()
  if not accent_names then
    accent_names = {}
    for _, name in ipairs(M.accents) do accent_names[name] = true end
  end
  return accent_names
end

--- Does this group mark "the selected item"? Recognised by name, so the
--- completion menu, the picker and any plugin added later are covered.
function M.is_selection(name)
  return name:find('Selection$') ~= nil or name:find('Selected$') ~= nil or name:find('Sel$') ~= nil
    or name == 'WildMenu' or name == 'QuickFixLine'
end

--- Groups that keep a background: the listed accents and every selection group.
function M.is_accent(name) return accent_set()[name] == true or M.is_selection(name) end

--- Rules 2 and 3, applied to every highlight group that exists right now. Also
--- run for groups that plugins define later.
function M.restyle()
  local shades = M.shades
  local selection = vim.api.nvim_get_hl(0, { name = 'Visual', link = false }).bg
  local popup = vim.api.nvim_get_hl(0, { name = 'NormalFloat', link = false }).bg
  for name, def in pairs(vim.api.nvim_get_hl(0, {})) do
    -- All-or-nothing, in both directions: with transparency OFF a popup's border
    -- must be as solid as the popup. Themes often give borders no background
    -- (they rely on the editor's), which would leave a see-through frame.
    if not M.opts.transparent and popup and not def.bg and not def.link and name:find('Border$') then
      def.bg = popup
      vim.api.nvim_set_hl(0, name, def)
    end
    if def.bg and M.is_selection(name) and name ~= 'Visual' and name ~= 'VisualNOS' then
      -- one selection colour everywhere (only groups that paint a background:
      -- parts like PmenuKindSel just colour text on top of it)
      if selection and def.bg ~= selection then
        def.bg, def.ctermbg = selection, nil
        vim.api.nvim_set_hl(0, name, def)
      end
    elseif M.opts.transparent and def.bg and shades[def.bg] and not M.is_accent(name) then
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
  -- Borders separate a popup from the code behind it: quiet, never loud. (Only
  -- the colour of the line is set here; whether a border has a background is
  -- decided by the transparency rule.)
  local comment = vim.api.nvim_get_hl(0, { name = 'Comment', link = false }).fg
  for _, name in ipairs({ 'FloatBorder', 'WinSeparator' }) do
    local def = vim.api.nvim_get_hl(0, { name = name, link = false })
    def.fg = comment
    vim.api.nvim_set_hl(0, name, def)
  end
  M.restyle()
end

--------------------------------------------------------------------------------
-- Cache: working out ~950 highlight groups costs ~3 ms on every start, whatever
-- the theme (measured); replaying a saved copy costs ~0.6 ms and needs no plugin.
-- Written only from a clean start (before other plugins add their groups),
-- thrown away whenever plugins are updated. Bump CACHE_VERSION when the rules
-- above change. The key is compared as plain text (hashing it cost 3.9 ms).
--------------------------------------------------------------------------------
local CACHE_VERSION = 6
local cache_dir = vim.fn.stdpath('cache') .. '/czernous-theme'

local function cache_key(theme)
  -- Everything the saved result depends on, as cheap strings: this file's rules
  -- (version), the theme, the setting, the Neovim build (its runtime folder and
  -- when that last changed), and the installed plugins (where they come from and
  -- when the lockfile last changed).
  local runtime = vim.env.VIMRUNTIME or ''
  local runtime_stat = vim.uv.fs_stat(runtime)
  local lock_stat = vim.uv.fs_stat(vim.fn.stdpath('config') .. '/lazy-lock.json')
  local parts = { tostring(CACHE_VERSION), theme.name, tostring(M.opts.transparent), runtime,
    tostring(runtime_stat and runtime_stat.mtime.sec or 0), vim.env.NVIM_PLUGIN_ROOT or '',
    tostring(lock_stat and lock_stat.mtime.sec or 0) }
  if theme.palette then
    for i = 0, 15 do parts[#parts + 1] = theme.palette[('base%02X'):format(i)] end
  end
  return table.concat(parts, '|')
end

local function cache_file(theme)
  return ('%s/%s-%s.mpack'):format(cache_dir, (theme.name:gsub('[^%w_-]', '_')), M.opts.transparent and 'transparent' or 'solid')
end

local function apply_cached(theme)
  local fd = io.open(cache_file(theme), 'rb')
  if not fd then return false end
  local data = fd:read('*a')
  fd:close()
  -- msgpack, Neovim's own binary format: decoding ~950 groups takes about a
  -- third of the time JSON did (measured: 0.7 ms -> see docs/perf).
  local ok, saved = pcall(vim.mpack.decode, data)
  if not ok or type(saved) ~= 'table' or saved.key ~= cache_key(theme) or type(saved.groups) ~= 'table' then return false end
  applying = true
  local set_hl = vim.api.nvim_set_hl
  for name, def in pairs(saved.groups) do set_hl(0, name, def) end
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
  local fd = io.open(cache_file(theme), 'wb')
  if not fd then return end
  local groups = vim.api.nvim_get_hl(0, {})
  for _, def in pairs(groups) do
    -- Without an explicit (empty) cterm table Neovim copies bold/italic into the
    -- 256-colour attributes when replaying, and the result would differ from a
    -- fresh start. Stored here so replaying is a plain loop.
    if def.cterm == nil then def.cterm = vim.empty_dict() end
  end
  fd:write(vim.mpack.encode({ key = cache_key(theme), shades = vim.tbl_keys(M.shades), groups = groups }))
  fd:close()
end

local function apply(theme)
  applying = true
  -- A theme that cannot load (its plugin missing after an offline first start,
  -- say) must not stop the rest of the config: keep Neovim's own colours, say so.
  local ok, err = pcall(theme.load)
  if not ok then
    applying = false
    vim.notify(('Theme %s could not be loaded; using Neovim\'s default colours.\n%s'):format(theme.name, tostring(err)), vim.log.levels.WARN)
    return false
  end
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
  return true
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
  if not apply_cached(theme) and apply(theme) then
    write_cache(theme) -- clean start: only Neovim's and the theme's groups exist
  end

  local group = vim.api.nvim_create_augroup('czernous_theme', { clear = true })
  -- Plugins that load later define their own groups; apply the same rule to them.
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'LazyLoad', 'VeryLazy' },
    -- several plugins often load in one burst (opening a file): restyle once after it
    callback = function()
      if restyle_pending or not M.current then return end
      restyle_pending = true
      vim.schedule(function()
        restyle_pending = false
        M.restyle()
      end)
    end,
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
