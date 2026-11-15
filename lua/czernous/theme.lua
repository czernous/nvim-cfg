-- The one place that decides how Neovim looks.
--
-- WHAT supplies the colours:
--   Always a 16-colour base16 PALETTE (plain data, a small JSON file), turned
--   into highlight groups by one renderer (mini.base16):
--   * the one Stylix writes on a machine it themes -- found by itself;
--   * or the file named by $NVIM_BASE16_PALETTE;
--   * or, with neither, the built-in palette for the terminal's polarity
--     (M.themes -> palettes/*.json).
--   One mechanism with or without Nix: what you see here is what Stylix gives.
--   (Measured: building the theme this way takes ~17 ms against ~26 ms for a
--   full colour-scheme plugin; normal starts replay a cache and cost the same.)
--
-- Whatever supplies them, the same rules give the UI one consistent structure:
--   1. Polarity follows the terminal. Neovim detects a dark or light terminal
--      ('background'); only a theme of that kind can be active.
--   2. Backgrounds are all-or-nothing. With `transparent = false` every surface
--      has the same background (the palette's), popups told apart by borders.
--      Transparency likewise: With `transparent = true`, the theme's
--      own background shades (whatever it paints the editor, popups, menus and
--      status areas with) are found, and EVERY highlight group using one of them
--      loses its background -- by scanning all groups, so pickers, completion,
--      hover and any future plugin follow without being named. Only the ACCENTS
--      keep a background: the things you must be able to see. Popups stay
--      readable through their border ('winborder').
--   3. "The selected item" looks the same everywhere. Any group that marks a
--      selection (its name ends in Sel, Selection or Selected: completion menu,
--      picker, wildmenu, any plugin) gets the theme's own selection colour.
--   5. Calm code: every text colour is softened a little (M.opts.soften),
--      names are plain text, punctuation is muted, all keywords share one
--      colour, strings / functions / types / constants keep theirs, comments
--      are muted but readable (3.5:1), the matching bracket is unmistakable.
--      The same for every palette (see calm()).
--   6. One border, one title: every popup border is the same quiet colour and
--      every popup title looks the same, whichever plugin draws it.
--   4. The result is cached, so a start costs ~0.6 ms instead of ~3 ms and the
--      theme plugin is not even loaded.
--
-- Toggle transparency at runtime: <leader>tT.

local M = {}

--- Where this config's files are: ~/.config/nvim, or the folder named by
--- $NVIM_CONFIG_ROOT (see lazy.lua).
local function config_root()
  local root = vim.env.NVIM_CONFIG_ROOT
  return (root and root ~= '') and root or vim.fn.stdpath('config')
end

M.opts = { transparent = true, soften = 0.2 }

--- The built-in palettes, one per terminal polarity: files in palettes/
--- (official base16 schemes). Used when nothing outside supplies a palette.
M.themes = { dark = 'catppuccin-mocha', light = 'catppuccin-latte' }

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
    local colour = palette[key]
    if type(colour) ~= 'string' then return nil, path .. ' has no ' .. key end
    -- Stylix writes colours without the leading '#'
    if colour:match('^%x%x%x%x%x%x$') then colour = '#' .. colour end
    if not colour:match('^#%x%x%x%x%x%x$') then return nil, ('%s: %s is not a colour (%s)'):format(path, key, colour) end
    palette[key] = colour:lower()
  end
  -- its name: ours, or the one Stylix / base16 scheme files give (slug)
  palette.name = palette.name or palette.slug or vim.fn.fnamemodify(path, ':t:r')
  if palette.variant ~= 'dark' and palette.variant ~= 'light' then
    -- not stated: a palette whose background (base00) is bright is a light one
    local n = tonumber(palette.base00:sub(2), 16) or 0
    local r, g, b = math.floor(n / 65536), math.floor(n / 256) % 256, n % 256
    palette.variant = (0.299 * r + 0.587 * g + 0.114 * b) > 128 and 'light' or 'dark'
  end
  return palette
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

--- Rules 2, 3 and 6, applied to every highlight group that exists right now. Also
--- run for groups that plugins define later.
function M.restyle()
  local shades = M.shades
  local selection = vim.api.nvim_get_hl(0, { name = 'Visual', link = false }).bg
  -- the one background of solid (non-transparent) mode: the editor's own
  local solid = M.current and M.current.colors and tonumber(M.current.colors.base00:sub(2), 16)
    or vim.api.nvim_get_hl(0, { name = 'Normal', link = false }).bg
  local border = vim.api.nvim_get_hl(0, { name = 'FloatBorder', link = false }).fg
  local title = vim.api.nvim_get_hl(0, { name = 'FloatTitle', link = false }).fg
  local function fg_of(name) return vim.api.nvim_get_hl(0, { name = name, link = false }).fg end
  for name, def in pairs(vim.api.nvim_get_hl(0, {})) do
    -- Rule 6: one border, one title. Every group named ...Border follows the
    -- popup border and every ...Title the popup title, whichever plugin defines
    -- it (renderers give some plugins' borders a palette colour of their own,
    -- which is a different, arbitrary colour in every palette).
    if name ~= 'FloatBorder' and name:find('Border$') and fg_of(name) ~= border then
      def = { link = 'FloatBorder' }
      vim.api.nvim_set_hl(0, name, def)
    elseif name ~= 'FloatTitle' and name ~= 'Title' and name:find('Title$') and fg_of(name) ~= title then
      def = { link = 'FloatTitle' }
      vim.api.nvim_set_hl(0, name, def)
    end
    -- All-or-nothing, in both directions: with transparency OFF a popup's border
    -- must be as solid as the popup. Themes often give borders no background
    -- (they rely on the editor's), which would leave a see-through frame.
    if not M.opts.transparent and solid and not def.bg and not def.link and name:find('Border$') then
      def.bg = solid
      vim.api.nvim_set_hl(0, name, def)
    end
    if def.bg and M.is_selection(name) and name ~= 'Visual' and name ~= 'VisualNOS' then
      -- one selection colour everywhere (only groups that paint a background:
      -- parts like PmenuKindSel just colour text on top of it)
      if selection and def.bg ~= selection then
        def.bg, def.ctermbg = selection, nil
        vim.api.nvim_set_hl(0, name, def)
      end
    elseif def.bg and shades[def.bg] and not def.link and not M.is_accent(name) then
      -- Rule 2. Transparent: no surface has a background. Solid: every surface
      -- has the SAME one (the editor's) -- not the renderer's patchwork of
      -- shades for gutter, popups, status line and pickers. Either way popups
      -- are told apart by their border, and only accents keep a background.
      local want = (not M.opts.transparent) and solid or nil
      if def.bg ~= want then
        def.bg, def.ctermbg = want, nil
        vim.api.nvim_set_hl(0, name, def)
      end
    end
  end
end

-- WCAG contrast between two '#rrggbb' colours (1 = identical, 21 = black on white).
local function luminance(colour)
  local n = tonumber(colour:sub(2), 16)
  local function channel(v)
    v = v / 255
    return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * channel(math.floor(n / 65536)) + 0.7152 * channel(math.floor(n / 256) % 256) + 0.0722 * channel(n % 256)
end
local function contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

--- `share` of colour a, the rest colour b.
local function mix(a, b, share)
  local x, y = tonumber(a:sub(2), 16), tonumber(b:sub(2), 16)
  local function part(shift)
    local u, v = math.floor(x / shift) % 256, math.floor(y / shift) % 256
    return math.floor(u * share + v * (1 - share) + 0.5)
  end
  return ('#%02x%02x%02x'):format(part(65536), part(256), part(1))
end

--- The muted colour for comments: the palette's own dim colours if one of them
--- can be read against the background (3.5:1), otherwise the text colour
--- faded towards the background just far enough to be.
local function muted(palette) -- (aims a little above 3.5: colours are whole numbers)
  -- "muted" also means clearly quieter than the text: some palettes keep a
  -- light colour in their dim slots
  local ceiling = 0.75 * contrast(palette.base05, palette.base00)
  for _, key in ipairs({ 'base03', 'base04' }) do
    local c = contrast(palette[key], palette.base00)
    if c >= 3.6 and c <= ceiling then return palette[key] end
  end
  for share = 0.35, 1, 0.05 do
    local colour = mix(palette.base05, palette.base00, share)
    local c = contrast(colour, palette.base00)
    if c >= 3.6 and c <= ceiling then return colour end
    if c > ceiling then break end
  end
  -- A palette whose text is itself dim (Tokyo Night Moon: 4.6:1) leaves only a
  -- narrow band between "readable" and "quieter than the text": look for it
  -- in finer steps, and let it reach up to 0.8 of the text's contrast.
  for share = 0.35, 1, 0.01 do
    local colour = mix(palette.base05, palette.base00, share)
    if contrast(colour, palette.base00) >= 3.6 then return colour end
  end
  return palette.base05
end

-- Rule 5 (see the top of the file): calm code. A plain base16 renderer gives
-- every kind of name its own accent (fields red, brackets pink, loops yellow...),
-- which is far busier than the themes these palettes come from (Catppuccin,
-- One Dark, Rosé Pine all keep names plain and punctuation muted). Here:
local plain = { -- names and operators: the text colour
  'Identifier', 'Operator', '@variable', '@variable.member', '@variable.parameter', '@property',
  '@lsp.type.variable', '@lsp.type.property', '@lsp.type.parameter',
}
-- brackets, commas, dots: muted like comments, so the code's words lead and the
-- one matching bracket (MatchParen) is the only bracket that stands out
local punctuation = { 'Delimiter', '@punctuation', '@punctuation.bracket', '@punctuation.delimiter' }
local keywords = { -- every kind of keyword: the one keyword colour
  'Statement', 'Keyword', 'Conditional', 'Repeat', 'Label', 'Exception', 'Include', 'Define', 'PreProc', 'PreCondit',
  'StorageClass', 'Structure', '@keyword.return',
}
local function calm(palette)
  local function number(colour) return tonumber(colour:sub(2), 16) end
  local function recolour(names, colour)
    for _, name in ipairs(names) do
      local def = vim.api.nvim_get_hl(0, { name = name, link = false })
      def.fg = number(colour)
      vim.api.nvim_set_hl(0, name, def)
    end
  end
  recolour(plain, palette.base05)
  recolour(keywords, palette.base0E)
  recolour({ 'Macro' }, palette.base0D)     -- macros read as the functions they are used like
  recolour({ 'Character' }, palette.base0B) -- a character is a short string
  recolour({ 'Comment' }, muted(palette))
  recolour(punctuation, muted(palette))
  -- the bracket matching the one under the cursor: unmistakable
  vim.api.nvim_set_hl(0, 'MatchParen', { fg = number(palette.base09), bg = number(palette.base02), bold = true })
end

local function style()
  if M.current and M.current.colors then calm(M.current.colors) end
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
local CACHE_VERSION = 14
local cache_dir = vim.fn.stdpath('cache') .. '/czernous-theme'

local function cache_key(theme)
  -- Everything the saved result depends on, as cheap strings: this file's rules
  -- (version), the theme, the setting, the Neovim build (its runtime folder and
  -- when that last changed), and the installed plugins (where they come from and
  -- when the lockfile last changed).
  local runtime = vim.env.VIMRUNTIME or ''
  local runtime_stat = vim.uv.fs_stat(runtime)
  local lock_stat = vim.uv.fs_stat(config_root() .. '/lazy-lock.json')
  local parts = { tostring(CACHE_VERSION), theme.name, tostring(M.opts.transparent), runtime,
    tostring(runtime_stat and runtime_stat.mtime.sec or 0), vim.env.NVIM_PLUGIN_ROOT or '',
    tostring(lock_stat and lock_stat.mtime.sec or 0) }
  if theme.palette then
    for i = 0, 15 do parts[#parts + 1] = theme.palette[('base%02X'):format(i)] end
    parts[#parts + 1] = tostring(theme.soften)
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

--- The palette file supplied from outside, if any, and who supplies it:
---   1. $NVIM_BASE16_PALETTE (a path) -- explicit, for any setup
---      (the word `builtin` instead of a path: always the built-in palette);
---   2. the file Stylix writes on a machine it themes: stylix/palette.json in
---      the user's config folder (home-manager) or in /etc (NixOS).
--- So with Stylix nothing has to be configured: Neovim follows the system palette.
local function palette_source()
  local explicit = vim.env.NVIM_BASE16_PALETTE
  if explicit == 'builtin' then return nil end -- "ignore Stylix, use the built-in palette" (the checks do)
  if explicit and explicit ~= '' then return explicit, '$NVIM_BASE16_PALETTE' end
  local config_home = vim.env.XDG_CONFIG_HOME
  if not config_home or config_home == '' then config_home = (vim.env.HOME or '') .. '/.config' end
  for _, path in ipairs({ config_home .. '/stylix/palette.json', '/etc/stylix/palette.json' }) do
    if vim.uv.fs_stat(path) then return path, 'Stylix' end
  end
end

--- Where the colours come from, for :checkhealth (set by pick()).
M.source = nil
--- True when a palette is supplied from outside (then there is nothing to choose).
M.external = false

-- The palette picked with <leader>tp, per polarity: { dark = name, light = name }.
local choice_file = vim.fn.stdpath('state') .. '/czernous-palettes.json'
local function chosen()
  local fd = io.open(choice_file, 'r')
  if not fd then return {} end
  local text = fd:read('*a')
  fd:close()
  local ok, choice = pcall(vim.json.decode, text)
  return ok and type(choice) == 'table' and choice or {}
end

--- How much every text colour is faded towards the background (0 = the
--- palette as it is, 0.3 = much softer). Lowers contrast without changing a
--- single hue; applies to whatever palette is in use, as far as its text stays
--- comfortably readable (TEXT_FLOOR). <leader>ts steps through the levels and
--- the choice is remembered.
M.soften_levels = { 0, 0.1, 0.2, 0.3 }
local function soften_level()
  local level = chosen().soften
  return type(level) == 'number' and level or M.opts.soften
end

--- Softening never takes ordinary text below this contrast with the background
--- (a palette that is already soft is softened less, or not at all).
local TEXT_FLOOR = 6

local function palette_theme(palette)
  local soften = soften_level()
  while soften > 0 and contrast(mix(palette.base05, palette.base00, 1 - soften), palette.base00) < TEXT_FLOOR do
    soften = math.max(0, soften - 0.02)
  end
  local colors = {}
  for i = 0, 15 do
    local key = ('base%02X'):format(i)
    -- base00-04 are the background shades; 05-0F are what text is written in
    colors[key] = (i >= 5 and soften > 0) and mix(palette[key], palette.base00, 1 - soften) or palette[key]
  end
  return {
    name = 'base16-' .. palette.name,
    variant = palette.variant,
    palette = palette, -- as supplied
    colors = colors,   -- as used (softened)
    soften = soften,
    load = function()
      -- Colours for the plugins this config has, not for the ~30 others the
      -- renderer knows (fewer groups to replay on every start). Taken from the
      -- plugin specs, so adding or removing a plugin needs nothing here.
      local plugins = { default = false, ['williamboman/mason.nvim'] = true } -- mason's former address
      for _, plugin in pairs(require('lazy.core.config').plugins) do
        if plugin[1] then plugins[plugin[1]] = true end
      end
      require('mini.base16').setup({ palette = colors, use_cterm = false, plugins = plugins })
    end,
  }
end

--- Theme for the current terminal polarity (or the palette supplied from outside).
local function pick()
  local path, who = palette_source()
  if path then
    local palette, err = M.load_file(path)
    if palette then
      M.source = ('%s: %s'):format(who, path)
      M.external = true
      return palette_theme(palette)
    end
    vim.notify(('%s palette: %s; using the built-in palette'):format(who, err), vim.log.levels.WARN)
  end
  local variant = vim.o.background == 'light' and 'light' or 'dark'
  local name = chosen()[variant] or M.themes[variant]
  local builtin = ('%s/palettes/%s.json'):format(config_root(), name)
  if not vim.uv.fs_stat(builtin) then -- a remembered palette that is gone
    builtin = ('%s/palettes/%s.json'):format(config_root(), M.themes[variant])
  end
  M.source = 'built-in palette: ' .. builtin
  local palette, err = M.load_file(builtin)
  if not palette then
    -- apply() reports this and keeps Neovim's own colours
    return { name = 'none', variant = variant, load = function() error(err, 0) end }
  end
  palette.variant = variant -- only a palette of the terminal's polarity is ever active
  return palette_theme(palette)
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
--- Step through the built-in palettes of the terminal's polarity (step = 1 or
--- -1) and remember the choice. Returns false when the colours come from
--- outside (Stylix, $NVIM_BASE16_PALETTE): there is nothing to choose then.
function M.next_palette(step)
  if M.external then
    vim.notify(('The colours come from %s -- the built-in palettes are not in use.'):format(M.source))
    return false
  end
  local variant = vim.o.background == 'light' and 'light' or 'dark'
  local names = {}
  for _, file in ipairs(vim.fn.globpath(config_root() .. '/palettes', '*.json', false, true)) do
    local palette = M.load_file(file)
    if palette and palette.variant == variant then names[#names + 1] = vim.fn.fnamemodify(file, ':t:r') end
  end
  table.sort(names)
  if #names == 0 then return false end
  local at = 1
  for i, name in ipairs(names) do
    if M.current and M.current.palette and M.current.palette.name == name then at = i end
  end
  at = (at - 1 + step) % #names + 1
  local choice = chosen()
  choice[variant] = names[at]
  -- A palette can name its counterpart of the other polarity ("pair": Rosé
  -- Pine -> Rosé Pine Dawn). Choosing one chooses both, so the same theme
  -- follows the terminal from dark to light and back.
  local other = variant == 'dark' and 'light' or 'dark'
  local picked = M.load_file(('%s/palettes/%s.json'):format(config_root(), names[at]))
  local pair = picked and type(picked.pair) == 'string' and picked.pair or nil
  local counterpart = pair and M.load_file(('%s/palettes/%s.json'):format(config_root(), pair))
  if counterpart and counterpart.variant == other then choice[other] = pair else pair = nil end
  vim.fn.mkdir(vim.fn.fnamemodify(choice_file, ':h'), 'p')
  vim.fn.writefile({ vim.json.encode(choice) }, choice_file)
  apply(pick())
  vim.notify(('Palette: %s (%d of %d)%s'):format(names[at], at, #names,
    pair and (' -- on a %s terminal: %s'):format(other, pair) or ''))
  return true
end

--- Step to the next softness level (see M.soften_levels) and remember it.
function M.next_soften()
  local current, at = soften_level(), 1
  for i, level in ipairs(M.soften_levels) do
    if math.abs(level - current) < 0.001 then at = i end
  end
  local level = M.soften_levels[at % #M.soften_levels + 1]
  local choice = chosen()
  choice.soften = level
  vim.fn.mkdir(vim.fn.fnamemodify(choice_file, ':h'), 'p')
  vim.fn.writefile({ vim.json.encode(choice) }, choice_file)
  apply(pick())
  vim.notify(('Colours softened by %d%%'):format(level * 100 + 0.5))
  return level
end

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
