-- Update the plugins when Nix manages them: the counterpart of `:Lazy update`.
--
--   nix run .#update-plugins            (or: nvim -l nix/update-plugins.lua)
--   nvim -l nix/update-plugins.lua --check     only show what would change
--
-- Run it in your clone of this repository. For every plugin in lazy-lock.json
-- it asks the plugin's repository for the newest commit of its branch (or its
-- newest release tag, for plugins that follow releases), rewrites
-- lazy-lock.json, and prints what moved. Then rebuild (home-manager switch /
-- nix build): the build fetches exactly those commits. Nothing is downloaded
-- here except the answers to "what is the newest commit?".
--
-- Undo: `git checkout lazy-lock.json`.

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0], ':p'))))
local check_only = vim.tbl_contains(arg, '--check')

local function read_json(path)
  local fd = assert(io.open(path, 'r'), 'cannot read ' .. path)
  local text = fd:read('*a')
  fd:close()
  return vim.json.decode(text)
end

local lock = read_json(root .. '/lazy-lock.json')
local sources = read_json(root .. '/nix/plugin-sources.json')

--- "v1.2.3" / "1.2.3" -> { 1, 2, 3 }; nil for anything else (pre-releases too).
local function version(tag)
  local major, minor, patch = tag:match('^v?(%d+)%.(%d+)%.(%d+)$')
  if major then return { tonumber(major), tonumber(minor), tonumber(patch) } end
end
local function newer(a, b)
  for i = 1, 3 do
    if a[i] ~= b[i] then return a[i] > b[i] end
  end
  return false
end

--- The commit to use from `git ls-remote` output, and a label for it.
local function newest(source, branch, output)
  if source.follow == 'tags' then
    local best, best_commit, best_tag
    -- annotated tags are listed twice; the line ending in ^{} is the commit
    local commits = {}
    for commit, ref in output:gmatch('(%x+)\trefs/tags/([^\n]+)') do
      local tag, peeled = ref:gsub('%^{}$', '')
      if peeled > 0 or not commits[tag] then commits[tag] = commit end
    end
    for tag, commit in pairs(commits) do
      local v = version(tag)
      if v and (not best or newer(v, best)) then best, best_commit, best_tag = v, commit, tag end
    end
    return best_commit, best_tag
  end
  return output:match('(%x+)\trefs/heads/' .. vim.pesc(branch) .. '\n'), branch
end

local names = vim.tbl_keys(lock)
table.sort(names)
local jobs = {}
for _, name in ipairs(names) do
  local source = sources[name]
  if source then
    local refs = source.follow == 'tags' and 'refs/tags/*' or ('refs/heads/' .. lock[name].branch)
    jobs[name] = vim.system({ 'git', 'ls-remote', source.url, refs }, { text = true })
  end
end

local changed, failed = 0, 0
for _, name in ipairs(names) do
  local source, entry = sources[name], lock[name]
  if not source then
    print(('  ?  %-28s not in nix/plugin-sources.json'):format(name))
    failed = failed + 1
  else
    local result = jobs[name]:wait(60000)
    local commit, label = newest(source, entry.branch, (result.stdout or '') .. '\n')
    if result.code ~= 0 or not commit then
      print(('  !  %-28s could not ask %s'):format(name, source.url))
      failed = failed + 1
    elseif commit ~= entry.commit then
      print(('  ^  %-28s %s -> %s  (%s)'):format(name, entry.commit:sub(1, 7), commit:sub(1, 7), label))
      -- where to read what changed (GitHub's address for "everything between two commits")
      if source.url:find('^https://github%.com/') then
        print(('     %s/compare/%s...%s'):format(source.url:gsub('%.git$', ''), entry.commit:sub(1, 12), commit:sub(1, 12)))
      end
      entry.commit = commit
      changed = changed + 1
    end
  end
end

if changed == 0 then
  print(failed == 0 and 'All plugins are up to date.' or 'Nothing updated.')
elseif check_only then
  print(('%d plugin(s) can be updated (nothing written: --check).'):format(changed))
else
  -- the same layout lazy.nvim writes, so the file diffs cleanly either way
  local lines = { '{' }
  for i, name in ipairs(names) do
    lines[#lines + 1] = ('  %s: { "branch": %s, "commit": %s }%s'):format(vim.json.encode(name),
      vim.json.encode(lock[name].branch), vim.json.encode(lock[name].commit), i < #names and ',' or '')
  end
  lines[#lines + 1] = '}'
  local fd = assert(io.open(root .. '/lazy-lock.json', 'w'))
  fd:write(table.concat(lines, '\n') .. '\n')
  fd:close()
  print(('%d plugin(s) updated in lazy-lock.json. Rebuild to get them; `git checkout lazy-lock.json` undoes this.'):format(changed))
end
os.exit(failed == 0 and 0 or 1)
