# ==================================================================================================
# Home Manager Module Check
# ==================================================================================================

{
  pkgs,
  lib,
  activityReport,
  homeModule,
  overlay,
}:

let
  consumerPkgs = pkgs.extend (_: prev: { zstd = prev.hello; });

  evalWith =
    modulePkgs: settings:
    lib.evalModules {
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
            _module.args.pkgs = modulePkgs;
            programs.activity-report = {
              enable = true;
              inherit settings;
            };
          };
        }
      ];
    };

  eval = evalWith pkgs { labels.default = [ "work" ]; };
  consumerEval = evalWith consumerPkgs { };
  overlaidPkgs = consumerPkgs.extend overlay;

  fallbackPkgs =
    if pkgs.stdenv.isLinux then
      pkgs.pkgsMusl.extend overlay
    else
      let
        staticPkgs = consumerPkgs // {
          stdenv = consumerPkgs.stdenv // {
            hostPlatform = consumerPkgs.stdenv.hostPlatform // {
              isStatic = true;
            };
          };
        };
      in
      overlay staticPkgs staticPkgs;

  drvPath = pkg: builtins.unsafeDiscardStringContext pkg.drvPath;
in
assert drvPath consumerEval.config.programs.activity-report.package == drvPath activityReport;
assert drvPath overlaidPkgs.activity-report == drvPath activityReport;
assert drvPath fallbackPkgs.activity-report != drvPath activityReport;
pkgs.writeText "home-module.json" (
  builtins.toJSON {
    inherit (eval.config) home xdg;
  }
)
