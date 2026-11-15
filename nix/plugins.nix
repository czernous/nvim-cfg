# The plugins, at exactly the commits recorded in lazy-lock.json: one folder
# holding a sub-folder per plugin, named as lazy.nvim names them. The config
# reads it through $NVIM_PLUGIN_ROOT (lua/czernous/lazy.lua) and then installs
# and updates nothing itself.
#
# lazy-lock.json is the single source of truth for versions, on Nix and off it.
# It records commits but not where each plugin lives; that is
# plugin-sources.json (a check in tests/check.lua keeps it equal to the plugin
# specs, so it cannot drift). `nix run .#update-plugins` moves the lockfile to
# the newest commits: the counterpart of `:Lazy update`.
#
# Each plugin must be a real folder here, not a link: lazy.nvim only counts real
# folders as installed (a check in tests/check.lua runs the config from such a
# folder, without .git folders, as in the Nix store).
{ lib, runCommand }:
let
  lock = lib.importJSON ../lazy-lock.json;
  sources = lib.importJSON ./plugin-sources.json;
  fetch =
    name: locked:
    builtins.fetchGit {
      url = sources.${name}.url;
      rev = locked.commit;
      # a release commit is not always on the branch: look among all refs
      allRefs = true;
    };
in
runCommand "czernous-nvim-plugins" { } (
  ''
    mkdir -p $out
  ''
  + lib.concatStrings (
    lib.mapAttrsToList (name: locked: ''
      cp -r ${fetch name locked} "$out/${name}"
    '') lock
  )
)
