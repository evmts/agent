{
  description = "Plue - Swift and Zig multi-agent coding assistant";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zon2nix.url = "github:nix-community/zon2nix";
    
    # Add Ghostty as an input
    ghostty = {
      url = "github:ghostty-org/ghostty";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zon2nix, ghostty }:
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
        
        # Get the Ghostty package
        ghosttyPkg = ghostty.packages.${system}.default;
        
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
            # Include Ghostty's build inputs
            ghosttyPkg
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            darwin.apple_sdk.frameworks.CoreServices
          ];
          
          configurePhase = ''
            # Copy Zig dependencies
            mkdir -p .zig-cache
            cp -r ${zigDeps}/* .zig-cache/ || true
            
            # Set up Ghostty library paths
            export GHOSTTY_LIB_PATH="${ghosttyPkg}/lib"
            export GHOSTTY_INCLUDE_PATH="${ghosttyPkg}/include"
          '';
          
          buildPhase = ''
            # Use integrated Zig build that includes Swift with Ghostty paths
            zig build swift \
              -Dghostty-lib-path="$GHOSTTY_LIB_PATH" \
              -Dghostty-include-path="$GHOSTTY_INCLUDE_PATH"
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
            # Include Ghostty
            ghosttyPkg
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
            
            # Export Ghostty paths for development
            export GHOSTTY_LIB_PATH="${ghosttyPkg}/lib"
            export GHOSTTY_INCLUDE_PATH="${ghosttyPkg}/include"
            echo "Ghostty library available at: $GHOSTTY_LIB_PATH"
            
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