# ==================================================================================================
# Home Manager Module Check
# ==================================================================================================

{
  pkgs,
  lib,
  homeModule,
}:

let
  eval = lib.evalModules {
    class = "homeManager";
    modules = [
      homeModule
      {
        options = {
          home = {
            packages = lib.mkOption { type = lib.types.anything; };
            file = lib.mkOption { type = lib.types.anything; };
          };
          xdg.configFile = lib.mkOption { type = lib.types.anything; };
        };
        config = {
          _module.args.pkgs = pkgs;
          programs.activity-report = {
            enable = true;
            settings.labels.default = [ "work" ];
          };
        };
      }
    ];
  };
in
pkgs.writeText "home-module.json" (
  builtins.toJSON {
    inherit (eval.config) home xdg;
  }
)
