#!/usr/bin/env bash
# Wrapper to use system Swift when in Nix environment
# This is a temporary workaround until we get Swift Package Manager in Nix

if [ "$1" = "build" ]; then
    # Use system swift for build commands
    /usr/bin/swift "$@"
else
    # Use Nix swift for everything else
    swift "$@"
fi