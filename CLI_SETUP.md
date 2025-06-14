# Plue CLI Setup

This document explains how to set up Plue to be launched from the command line, similar to how you can run `code` to open Visual Studio Code.

## Quick Setup

### 1. Install the CLI Command

Run the installation script from the project root:

```bash
./scripts/install.sh
```

This will:
- Build the Plue project
- Install the `plue` command to `/usr/local/bin/`
- Make it available globally in your terminal

### 2. Usage

Once installed, you can use `plue` from anywhere:

```bash
# Open Plue in the current directory
plue

# Open Plue in a specific directory
plue /path/to/your/project

# Open Plue in current directory (explicit)
plue .

# Open Plue in your home directory
plue ~

# Open Plue in a relative path
plue ../my-other-project
```

## Examples

```bash
# Navigate to your project and open Plue
cd ~/code/my-awesome-project
plue

# Open Plue directly in a project directory
plue ~/code/my-awesome-project

# Open Plue in your Documents folder
plue ~/Documents

# Open multiple instances in different directories
plue ~/project1 &
plue ~/project2 &
```

## How it Works

1. **Command Line Parsing**: The `main.swift` file parses command line arguments and validates directory paths
2. **Working Directory**: Plue sets its working directory to the specified path
3. **Shell Script**: The `/usr/local/bin/plue` script is a wrapper that:
   - Validates the directory exists
   - Converts relative paths to absolute paths
   - Launches the Plue executable with the directory argument

## Manual Installation

If you prefer to install manually:

1. Build the project:
   ```bash
   zig build swift
   ```

2. Copy the CLI script:
   ```bash
   sudo cp scripts/plue /usr/local/bin/plue
   sudo chmod +x /usr/local/bin/plue
   ```

3. Edit the script to point to your Plue executable:
   ```bash
   sudo nano /usr/local/bin/plue
   ```

## Uninstall

To remove the CLI command:

```bash
sudo rm /usr/local/bin/plue
```

## Troubleshooting

### "Command not found"
- Make sure `/usr/local/bin` is in your PATH
- Try running `echo $PATH` to verify
- If not, add this to your shell profile (`.bashrc`, `.zshrc`, etc.):
  ```bash
  export PATH="/usr/local/bin:$PATH"
  ```

### "Permission denied"
- Make sure the script is executable: `chmod +x /usr/local/bin/plue`
- The installation script should handle this automatically

### "Plue executable not found"
- Make sure you've built the project with `zig build swift`
- Check that the executable exists at `.build/release/plue`
- The installation script will update the path automatically

## Development

During development, you can test the CLI without installing by running:

```bash
# Test the local script
./scripts/plue /path/to/test/directory

# Or run the executable directly
./.build/release/plue /path/to/test/directory
```