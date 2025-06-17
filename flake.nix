{
  description = "Plue - Swift and Zig multi-agent coding assistant";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Fetch Ghostty from GitHub 
    ghostty-src = {
      url = "github:ghostty-org/ghostty";
      flake = false;
    };
    
    # zon2nix for Zig dependency management
    zon2nix = {
      url = "github:jcollie/zon2nix?ref=56c159be489cc6c0e73c3930bd908ddc6fe89613";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ghostty-src, zon2nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Zig dependencies from deps.nix
        zigDeps = pkgs.callPackage ./deps.nix { };
        
        # Ghostty dependencies from their build.zig.zon.nix
        ghosttyZigDeps = pkgs.callPackage ./ghostty-deps.nix { 
          zig_0_14 = pkgs.zig;
        };
        
        # Build libghostty using Ghostty's own build system
        ghosttyPkg = pkgs.stdenv.mkDerivation {
          pname = "libghostty";
          version = "unstable";
          
          src = ghostty-src;
          
          nativeBuildInputs = with pkgs; [
            zig
            pkg-config
            git
            pandoc
            ncurses
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            xcbuild
          ];
          
          buildInputs = with pkgs; [] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            darwin.apple_sdk.frameworks.CoreFoundation
            darwin.apple_sdk.frameworks.CoreGraphics
            darwin.apple_sdk.frameworks.CoreText
            darwin.apple_sdk.frameworks.CoreVideo
            darwin.apple_sdk.frameworks.Foundation
            darwin.apple_sdk.frameworks.Metal
            darwin.apple_sdk.frameworks.MetalKit
            darwin.apple_sdk.frameworks.QuartzCore
            darwin.apple_sdk.frameworks.Carbon
            darwin.apple_sdk.frameworks.Cocoa
            darwin.apple_sdk.frameworks.IOKit
            darwin.apple_sdk.frameworks.Security
            darwin.apple_sdk.frameworks.UniformTypeIdentifiers
            darwin.apple_sdk.frameworks.CoreServices
          ];
          
          configurePhase = ''
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            mkdir -p $ZIG_GLOBAL_CACHE_DIR
            
            # Link Ghostty's deps
            ln -s ${ghosttyZigDeps} $ZIG_GLOBAL_CACHE_DIR/p
          '';
          
          buildPhase = ''
            # Build libghostty using Ghostty's build system
            zig build -Doptimize=ReleaseFast -Dapp-runtime=none --prefix $out --verbose
          '';
          
          installPhase = ''
            # Library and header should already be installed by zig build
            # Just ensure they're in the right place
            echo "Checking installed files..."
            ls -la $out/lib/ || echo "No lib directory"
            ls -la $out/include/ || echo "No include directory"
          '';
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
            darwin.apple_sdk.frameworks.CoreServices
            # Include libghostty
            ghosttyPkg
          ];
          
          configurePhase = ''
            # Set up Zig package cache
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            mkdir -p $ZIG_GLOBAL_CACHE_DIR
            ln -s ${zigDeps} $ZIG_GLOBAL_CACHE_DIR/p
            
            # Set up Ghostty library paths
            export GHOSTTY_LIB_PATH="${ghosttyPkg}/lib"
            export GHOSTTY_INCLUDE_PATH="${ghosttyPkg}/include"
          '';
          
          buildPhase = ''
            # Use integrated Zig build that includes Swift
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
          libghostty = ghosttyPkg;
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
            # Include Ghostty
            ghosttyPkg
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