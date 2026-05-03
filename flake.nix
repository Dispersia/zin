{
  description = "Zig 0.16"

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";

    zls-flake.url = "github:zigtools/zls";
    nls-flake.inputs.nixpkgs.follows = "nixpkgs";
    zls-flake.inputs.zig-overlay.follows = "zig-overlay";
  };

  outputs = { self, nixpkgs, zig-overlay, zls-flake }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system}

      zig = zig-overlay.packages.${system}."0.16.0"
      zls = zls-flake.packages.${system}.zls;
    in {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = [
          zig
          zls
        ];
      };
    };
}
