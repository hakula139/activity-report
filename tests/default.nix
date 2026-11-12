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
}:

{
  home-module = import ./home-module { inherit pkgs lib homeModule; };

  package = activityReport;

  tests = import ./scripts {
    inherit dk commonInputs;
    root = ../.;
  };
}
