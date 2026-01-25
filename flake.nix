{
  description = "Omarchy on NixOS";

  nixConfig = {
    extra-substituters = [ "https://nix-cache.codingismy11to7.us/omarchy" ];
    extra-trusted-public-keys = [ "omarchy:TRPnFp7RNU+BhR64bXpG61cNE7TlB53BAoc7wEmhzyE=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default-linux";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    terminaltexteffects = {
      url = "github:ChrisBuilds/terminaltexteffects";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    elephant = {
      url = "github:abenz1267/elephant/2.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    voxtype = {
      url = "github:peteonrails/voxtype";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    walker = {
      url = "github:abenz1267/walker/2.0.0";
      inputs = {
        elephant.follows = "elephant";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };
    hyprland-preview-share-picker.url = "github:codingismy11to7/hyprland-preview-share-picker/nix";
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { flake-parts-lib, ... }:
      let
        inherit (flake-parts-lib) importApply;
      in
      {
        systems = import inputs.systems;

        flake = {
          homeManagerModules = {
            default = self.homeManagerModules.omarchy;
            omarchy = importApply ./nix/modules/home-manager.nix { inherit self inputs; };
          };

          lazyvimTheme = {
            default = self.lazyvimTheme.omarchy;
            omarchy = import ./nix/modules/lazyvim-theme.nix;
          };

          nixosModules = {
            default = self.nixosModules.omarchy;
            omarchy = importApply ./nix/modules/nixos.nix { inherit self inputs; };
          };
        };

        perSystem =
          {
            config,
            self',
            inputs',
            pkgs,
            system,
            ...
          }:
          {
            formatter = pkgs.nixfmt;

            devShells.default = pkgs.mkShell {
              shellHook = ''
                echo "*** watch for changes with 'dev-mode' ***" | tte --frame-rate 300 wipe
              '';
              packages = with pkgs; [
                inputs'.terminaltexteffects.packages.default
                watchexec
                (pkgs.writeShellScriptBin "dev-mode" ''
                  watchexec --restart --clear --ignore result nix flake check
                '')
                (pkgs.writeShellScriptBin "lint" ''
                  if [[ "$1" == "--fix" ]]; then
                    shift
                    ${lib.getExe pkgs.statix} fix "$@"
                    ${lib.getExe pkgs.deadnix} -e "$@"
                  else
                    EXIT_CODE=0
                    ${lib.getExe pkgs.statix} check "$@" || EXIT_CODE=1
                    ${lib.getExe pkgs.deadnix} "$@" || EXIT_CODE=1
                    exit $EXIT_CODE
                  fi
                '')
              ];
            };

            checks = {
              test-build =
                (inputs.nixpkgs.lib.nixosSystem {
                  inherit system;
                  specialArgs = { inherit inputs; };
                  modules = [
                    self.nixosModules.default
                    inputs.home-manager.nixosModules.home-manager
                    {
                      fileSystems."/".device = "/dev/null";
                      boot.loader.grub.enable = false;
                      system.stateVersion = "25.11";
                      users.users.testuser = {
                        isNormalUser = true;
                        group = "testuser";
                      };
                      users.groups.testuser = { };
                      home-manager = {
                        useUserPackages = true;
                        useGlobalPkgs = true;
                        extraSpecialArgs = { inherit inputs; };
                        users.testuser = {
                          imports = [
                            self.homeManagerModules.default
                          ];

                          home.stateVersion = "25.11";
                          omarchy.enable = true;
                          omarchy.voxtype = { };
                        };
                      };
                    }
                  ];
                }).config.system.build.toplevel;
            };
          };
      }
    );
}
