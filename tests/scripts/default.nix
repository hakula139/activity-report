# ==================================================================================================
# Script Tests
# ==================================================================================================

{
  pkgs,
  dk,
  commonInputs,
  root,
}:

(dk.nuTests {
  src = root;
  runtimeInputs = commonInputs;
}).overrideAttrs
  {
    TZDIR = "${pkgs.tzdata}/share/zoneinfo";
  }
