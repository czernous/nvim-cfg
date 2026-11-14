-- Merged on top of nvim-lspconfig's jdtls defaults.
-- No JDK paths or versions here: jdtls runs with JAVA_HOME / the `java` on
-- $PATH, and the project's target JDK comes from its build (Gradle toolchains,
-- Maven) or JAVA_HOME -- set by your devshell / sdkman / .envrc.

-- One jdtls workspace per project, keyed by the FULL project path (lspconfig's
-- default uses only the folder name, so two projects called `api` would clash).
local function data_dir(root)
  local base = vim.fn.stdpath('cache') .. '/jdtls/workspace/'
  if not root then return base .. 'default' end
  return base .. (root:gsub('[/\\:]', '%%'))
end

local config = {
  cmd = function(dispatchers, cfg)
    local cmd = { 'jdtls', '-data', data_dir(cfg.root_dir) }
    for arg in (vim.env.JDTLS_JVM_ARGS or ''):gmatch('%S+') do
      cmd[#cmd + 1] = '--jvm-arg=' .. arg
    end
    return vim.lsp.rpc.start(cmd, dispatchers, { cwd = cfg.cmd_cwd, env = cfg.cmd_env, detached = cfg.detached })
  end,
}

-- If the environment sets JAVA_HOME, tell jdtls about that JDK as the default
-- runtime for projects (major version read from $JAVA_HOME/release).
local java_home = vim.env.JAVA_HOME
if java_home and java_home ~= '' then
  local f = io.open(java_home .. '/release')
  local version = f and f:read('*a'):match('JAVA_VERSION="([%d%.]+)"')
  if f then f:close() end
  if version then
    local major = version:match('^1%.(%d+)') or version:match('^(%d+)')
    config.settings = {
      java = {
        configuration = {
          runtimes = { { name = 'JavaSE-' .. (major == '8' and '1.8' or major), path = java_home, default = true } },
        },
      },
    }
  end
end

return config
