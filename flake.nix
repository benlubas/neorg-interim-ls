{
  description = "Flake for Neorg Module Development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    gen-luarc.url = "github:mrcjkb/nix-gen-luarc-json";
    gen-luarc.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      gen-luarc,
      ...
    }:

    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ gen-luarc.overlays.default ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "Neorg-Module DevShell";

          shellHook =
            let
              luarc = pkgs.mk-luarc-json {
                plugins = with pkgs; [
                  vimPlugins.neorg
                  lua51Packages.pathlib-nvim
                  lua51Packages.nvim-nio
                ];
              };
            in
            # bash
            ''
              ln -fs ${luarc} .luarc.json
            '';

          packages = with pkgs; [
            lua-language-server
            stylua
            nil
            lua5_1
          ];
        };
      }
    );
}
