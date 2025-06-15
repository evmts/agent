{
  description = "Plue - Swift and Zig multi-agent coding assistant";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Add Ghostty source as an input (we'll build it ourselves for macOS)
    ghostty-src = {
      url = "github:ghostty-org/ghostty";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ghostty-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Zig dependencies from deps.nix
        zigDeps = pkgs.callPackage ./deps.nix { };
        
        # For now, skip Ghostty build - it requires its own dependencies
        # TODO: Add proper Ghostty build once we set up build.zig.zon dependencies
        ghosttyPkg = null;
        
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
            # Include Ghostty's build inputs (if available)
          ] ++ pkgs.lib.optionals (pkgs.stdenv.isDarwin && ghosttyPkg != null) [
            ghosttyPkg
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            darwin.apple_sdk.frameworks.CoreServices
          ];
          
          configurePhase = ''
            # Set up Zig package cache
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            mkdir -p $ZIG_GLOBAL_CACHE_DIR
            ln -s ${zigDeps} $ZIG_GLOBAL_CACHE_DIR/p
            
            # Set up Ghostty library paths (if available)
            ${pkgs.lib.optionalString (ghosttyPkg != null) ''
              export GHOSTTY_LIB_PATH="${ghosttyPkg}/lib"
              export GHOSTTY_INCLUDE_PATH="${ghosttyPkg}/include"
            ''}
          '';
          
          buildPhase = ''
            # Use integrated Zig build that includes Swift
            if [ -n "$GHOSTTY_LIB_PATH" ]; then
              zig build swift \
                -Dghostty-lib-path="$GHOSTTY_LIB_PATH" \
                -Dghostty-include-path="$GHOSTTY_INCLUDE_PATH"
            else
              zig build swift
            fi
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
          ] ++ pkgs.lib.optionals (pkgs.stdenv.isDarwin && ghosttyPkg != null) [
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
            
            # Temporary workaround: alias swift to use system Swift for builds
            alias swift="$PWD/nix-swift-wrapper.sh"
            
            # Export Ghostty paths for development (if available)
            ${pkgs.lib.optionalString (ghosttyPkg != null) ''
              export GHOSTTY_LIB_PATH="${ghosttyPkg}/lib"
              export GHOSTTY_INCLUDE_PATH="${ghosttyPkg}/include"
              echo "Ghostty library available at: $GHOSTTY_LIB_PATH"
            ''}
            
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