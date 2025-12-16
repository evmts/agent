//go:build !windows

package embedded

import (
	"os/exec"
	"syscall"
)

// setProcAttr sets Unix-specific process attributes.
func setProcAttr(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid: true,
	}
}
