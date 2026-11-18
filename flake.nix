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
          version = "0.2.1";
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

      platformKey = p: { inherit (p) config isStatic; };

      packageFor =
        pkgs:
        let
          locked = self.packages.${pkgs.stdenv.hostPlatform.system}.activity-report or null;
        in
        if
          locked != null
          && platformKey pkgs.stdenv.buildPlatform == platformKey locked.stdenv.buildPlatform
          && platformKey pkgs.stdenv.hostPlatform == platformKey locked.stdenv.hostPlatform
          && pkgs.stdenv.hostPlatform == pkgs.stdenv.targetPlatform
        then
          locked
        else
          mkActivityReport pkgs;

      # A key lets the module system deduplicate the module when it is imported twice.
      homeModuleKey = "${self}/flake.nix#homeModules.default";
    in
    # ----------------------------------------------------------------------------------------------
    # Overlay and Home Manager Module
    # ----------------------------------------------------------------------------------------------
    {
      overlays.default = _: prev: { activity-report = packageFor prev; };

      homeModules.default = {
        _class = "homeManager";
        _file = homeModuleKey;
        key = homeModuleKey;
        imports = [
          (import ./nix/home-manager.nix {
            inherit devkit packageFor;
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
            nu-check.enable = true;
            prettier.enable = true;
            shellcheck.enable = true;
            shfmt.enable = true;
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
        checks = import ./tests {
          inherit
            pkgs
            lib
            dk
            commonInputs
            activityReport
            ;
          homeModule = self.homeModules.default;
          overlay = self.overlays.default;
        };

        # ------------------------------------------------------------------------------------------
        # Formatter
        # ------------------------------------------------------------------------------------------
        formatter = pkgs.nixfmt-tree;
      }
    );
}
