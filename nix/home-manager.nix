# ==================================================================================================
# activity-report Home Manager Module
# ==================================================================================================

{
  devkit,
  mkActivityReport,
}:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.activity-report;
  toml = pkgs.formats.toml { };
in
{
  # ------------------------------------------------------------------------------------------------
  # Module Options
  # ------------------------------------------------------------------------------------------------
  options.programs.activity-report = {
    enable = lib.mkEnableOption "activity-report and its agent skill";

    package = lib.mkOption {
      type = lib.types.package;
      default = mkActivityReport pkgs;
      defaultText = lib.literalMD "activity-report built from this flake";
      description = "Package that provides the `activity-report` command.";
    };

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      description = "Settings written to `activity-report/config.toml` in the XDG config directory.";
    };

    skillDirectories = lib.mkOption devkit.lib.skillDirectoriesOption;
  };

  # ------------------------------------------------------------------------------------------------
  # Module Config
  # ------------------------------------------------------------------------------------------------
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    home.file = devkit.lib.skillLinks {
      inherit (cfg) package;
      name = "activity-report";
      directories = cfg.skillDirectories;
    };
    xdg.configFile = lib.mkIf (cfg.settings != { }) {
      "activity-report/config.toml".source = toml.generate "config.toml" cfg.settings;
    };
  };
}
