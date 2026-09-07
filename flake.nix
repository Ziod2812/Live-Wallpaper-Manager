{
  description = "Live Wallpaper Manager (Quickshell/QML) - pinned dev/runtime environment";

  inputs = {
    # Pinned to a specific nixos-unstable revision known to carry a
    # recent-enough `quickshell` (needs 25.05+ semantics per
    # install_quickshell_nixos() in install.sh). Update this hash
    # deliberately with `nix flake update`, not by tracking a moving
    # channel name -- that unpinned-channel drift is exactly what
    # install.sh's lw_nix_install() has to route around at install time.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = false;
        };

        runtimeDeps = with pkgs; [
          quickshell
          mpv
          mpvpaper
          qt6.qtbase
          qt6.qtdeclarative
          wayland-protocols
          python3
          jq
          ffmpeg
          hyprland
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          name = "live-wallpaper-manager";
          buildInputs = runtimeDeps ++ [ pkgs.nodejs_22 ];

          # install.sh/utils.sh discover binaries purely via PATH
          # (command -v mpvpaper / hyprctl / jq / python3), never a
          # hardcoded /usr or /usr/local prefix -- so a plain buildInputs
          # PATH injection is enough here; no wrapper scripts or
          # store-path substitution needed for this shell to be usable
          # by install.sh's existing distro-detection/dependency logic.
          shellHook = ''
            echo "Live Wallpaper Manager dev shell (NixOS) — quickshell, mpv/mpvpaper, qt6, python3, node ${pkgs.nodejs_22.version} on PATH."
          '';
        };

        packages.runtimeDeps = pkgs.buildEnv {
          name = "live-wallpaper-manager-runtime";
          paths = runtimeDeps;
        };
      });
}
