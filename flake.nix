{
  description = "Plue - Swift and Zig multi-agent coding assistant";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zon2nix.url = "github:nix-community/zon2nix";
  };

  outputs = { self, nixpkgs, flake-utils, zon2nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Generate Zig dependencies using zon2nix
        zp = zon2nix.builders.${system};
        
        # Build Zig dependencies from build.zig.zon
        zigDeps = zp.buildZigPackage {
          src = ./.;
          dontCheck = true;
        };
        
        # Unified Swift + Zig package using integrated build
        swiftPackage = pkgs.stdenv.mkDerivation {
          pname = "plue";
          version = "0.0.0";
          
          src = ./.;
          
          nativeBuildInputs = with pkgs; [
            swift
            zig
            pkg-config
          ];
          
          buildInputs = with pkgs; [
            darwin.apple_sdk.frameworks.Foundation
            darwin.apple_sdk.frameworks.AppKit
            darwin.apple_sdk.frameworks.WebKit
            darwin.apple_sdk.frameworks.Security
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            darwin.apple_sdk.frameworks.CoreServices
          ];
          
          configurePhase = ''
            # Copy Zig dependencies
            mkdir -p .zig-cache
            cp -r ${zigDeps}/* .zig-cache/ || true
          '';
          
          buildPhase = ''
            # Use integrated Zig build that includes Swift
            zig build swift
          '';
          
          installPhase = ''
            mkdir -p $out/bin
            cp .build/release/plue $out/bin/
          '';
          
          meta = with pkgs.lib; {
            description = "Multi-agent coding assistant built with Swift and Zig";
            homepage = "https://github.com/williamcory/plue";
            license = licenses.mit;
            platforms = platforms.darwin;
          };
        };
        
      in {
        packages = {
          default = swiftPackage;
          plue = swiftPackage;
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            swift
            zig
            pkg-config
            # Development tools
            git
            curl
            jq
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            darwin.apple_sdk.frameworks.Foundation
            darwin.apple_sdk.frameworks.AppKit
            darwin.apple_sdk.frameworks.WebKit
            darwin.apple_sdk.frameworks.Security
            darwin.apple_sdk.frameworks.CoreServices
          ];
          
          shellHook = ''
            echo "🚀 Plue development environment"
            echo "Available commands:"
            echo "  zig build        - Build complete project (Zig + Swift)"
            echo "  zig build run    - Build and run Swift application"
            echo "  zig build swift  - Build complete project (Zig + Swift)"
            echo "  nix build        - Build with Nix"
            echo ""
            echo "Environment ready!"
          '';
        };
        
        # Apps for easy running
        apps = {
          default = {
            type = "app";
            program = "${swiftPackage}/bin/plue";
          };
        };
      });
}