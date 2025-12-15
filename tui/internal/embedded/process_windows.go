//go:build windows

package embedded

import (
	"os/exec"
)

// setProcAttr sets Windows-specific process attributes.
func setProcAttr(cmd *exec.Cmd) {
	// Windows doesn't support Setpgid
}
