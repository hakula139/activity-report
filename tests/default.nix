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
  home-module = import ./home-module {
    inherit
      pkgs
      lib
      activityReport
      homeModule
      overlay
      ;
  };

  package = activityReport;

  tests = import ./scripts {
    inherit pkgs dk commonInputs;
    root = ../.;
  };
}
