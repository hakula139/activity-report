# ==================================================================================================
# Checks
# ==================================================================================================

{
  pkgs,
  lib,
  dk,
  commonInputs,
  activityReport,
  homeModule,
  overlay,
}:

{
  package = activityReport;

  # ------------------------------------------------------------------------------------------------
  # Script Tests
  # ------------------------------------------------------------------------------------------------
  tests =
    (dk.nuTests {
      src = ../.;
      runtimeInputs = commonInputs;
    }).overrideAttrs
      { TZDIR = "${pkgs.tzdata}/share/zoneinfo"; };

  # ------------------------------------------------------------------------------------------------
  # Home Manager Module
  # ------------------------------------------------------------------------------------------------
  home-module =
    let
      consumerPkgs = pkgs.extend (_: prev: { zstd = prev.hello; });
      overlaidPkgs = consumerPkgs.extend overlay;

      staticPlatform = consumerPkgs.stdenv.hostPlatform // {
        isStatic = true;
      };
      staticPkgs = consumerPkgs // {
        stdenv = consumerPkgs.stdenv // {
          hostPlatform = staticPlatform;
          targetPlatform = staticPlatform;
        };
      };
      fallbackPkgs = overlay staticPkgs staticPkgs;

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
    in
    assert consumerEval.config.programs.activity-report.package.drvPath == activityReport.drvPath;
    assert overlaidPkgs.activity-report.drvPath == activityReport.drvPath;
    assert fallbackPkgs.activity-report.drvPath != activityReport.drvPath;
    pkgs.writeText "home-module.json" (builtins.toJSON { inherit (eval.config) home xdg; });
}
