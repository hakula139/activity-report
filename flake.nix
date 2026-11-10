# ==================================================================================================
# activity-report Development Flake
# ==================================================================================================

{
  description = "activity-report packages and development environment";

  nixConfig = {
    extra-substituters = [ "https://hakula.cachix.org" ];
    extra-trusted-public-keys = [
      "hakula.cachix.org-1:7zwB3fhMfReHdOjh6DmnaLXgqbPDBcojvN9F+osZw0k="
    ];
  };

  # ------------------------------------------------------------------------------------------------
  # Inputs
  # ------------------------------------------------------------------------------------------------
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    devkit = {
      url = "github:hakula139/devkit/v3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # ------------------------------------------------------------------------------------------------
  # Outputs
  # ------------------------------------------------------------------------------------------------
  outputs =
    {
      self,
      nixpkgs,
      devkit,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      runtimeInputs =
        pkgs: with pkgs; [
          git
          zstd
        ];

      mkActivityReport =
        pkgs:
        (devkit.lib.mkLib pkgs).mkNuApplication {
          pname = "activity-report";
          entry = "activity-report";
          version = "0.0.0";
          src = ./skills/activity-report/scripts;
          skills = [ ./skills/activity-report ];
          runtimeInputs = runtimeInputs pkgs;
          meta = {
            description = "Report what you worked on from agent transcripts, with hours per project and task";
            homepage = "https://github.com/hakula139/activity-report";
            license = lib.licenses.mit;
            platforms = lib.platforms.all;
          };
        };

      # A key lets the module system deduplicate the module when it is imported twice.
      homeModuleKey = "${self}/flake.nix#homeModules.default";
    in
    # ----------------------------------------------------------------------------------------------
    # Overlay and Home Manager Module
    # ----------------------------------------------------------------------------------------------
    {
      overlays.default = final: _: { activity-report = mkActivityReport final; };

      homeModules.default = {
        _class = "homeManager";
        _file = homeModuleKey;
        key = homeModuleKey;
        imports = [
          (import ./nix/home-manager.nix {
            inherit devkit mkActivityReport;
          })
        ];
      };
    }
    // devkit.lib.eachSystem devkit.lib.systems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        dk = devkit.lib.mkLib pkgs;

        commonInputs = runtimeInputs pkgs;

        activityReport = mkActivityReport pkgs;

        preCommit = dk.preCommit {
          src = ./.;
          hooks = {
            actionlint.enable = true;
            check-yaml.enable = true;
            cspell.enable = true;
            deadnix.enable = true;
            dprint.enable = true;
            editorconfig-checker.enable = true;
            markdownlint-cli2.enable = true;
            nixfmt.enable = true;
            nu-check.enable = true;
            prettier.enable = true;
            shellcheck.enable = true;
            shfmt.enable = true;
            sort-file-contents.enable = true;
            statix.enable = true;
          };
        };
      in
      {
        # ------------------------------------------------------------------------------------------
        # Dev Shell
        # ------------------------------------------------------------------------------------------
        devShells.default = pkgs.mkShell {
          name = "activity-report-dev";

          packages = [
            dk.nushell
            dk.nu-test
          ]
          ++ commonInputs;

          inputsFrom = [ preCommit ];
        };

        # ------------------------------------------------------------------------------------------
        # Packages
        # ------------------------------------------------------------------------------------------
        packages = {
          default = activityReport;
          activity-report = activityReport;
        };

        # ------------------------------------------------------------------------------------------
        # Checks
        # ------------------------------------------------------------------------------------------
        checks = {
          home-module =
            let
              eval = lib.evalModules {
                class = "homeManager";
                modules = [
                  self.homeModules.default
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
            );

          package = activityReport;

          tests = dk.nuTests {
            src = ./.;
            runtimeInputs = commonInputs;
          };
        };

        # ------------------------------------------------------------------------------------------
        # Formatter
        # ------------------------------------------------------------------------------------------
        formatter = pkgs.nixfmt-tree;
      }
    );
}
