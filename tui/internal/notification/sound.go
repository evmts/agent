package notification

import (
	"fmt"
	"os/exec"
	"runtime"
	"time"
)

// SoundType represents different notification sound types
type SoundType int

const (
	SoundBell SoundType = iota
	SoundChime
	SoundError
	SoundCustom
)

// NotificationConfig holds notification preferences
type NotificationConfig struct {
	Enabled     bool
	SoundType   SoundType
	Volume      float64 // 0.0 to 1.0
	CustomPath  string  // For custom sound files
	VisualFlash bool    // Flash terminal instead of sound

	// When to notify
	NotifyOnComplete      bool
	NotifyOnError         bool
	NotifyOnConfirmation  bool
}

// DefaultNotificationConfig returns the default notification configuration
func DefaultNotificationConfig() NotificationConfig {
	return NotificationConfig{
		Enabled:              true,
		SoundType:            SoundBell,
		Volume:               0.8,
		VisualFlash:          false,
		NotifyOnComplete:     true,
		NotifyOnError:        true,
		NotifyOnConfirmation: true,
	}
}

// lastNotificationTime tracks the last notification to prevent spam
var lastNotificationTime time.Time

const (
	// MinNotificationInterval is the minimum time between notifications (debounce)
	MinNotificationInterval = 500 * time.Millisecond
)

// PlayNotification plays a notification sound or visual effect
func PlayNotification(soundType SoundType, config NotificationConfig) error {
	if !config.Enabled {
		return nil
	}

	// Debounce notifications
	now := time.Now()
	if now.Sub(lastNotificationTime) < MinNotificationInterval {
		return nil
	}
	lastNotificationTime = now

	if config.VisualFlash {
		return flashTerminal()
	}

	switch soundType {
	case SoundBell:
		return playBell()
	case SoundChime, SoundError:
		return playSystemSound(soundType, config.Volume)
	case SoundCustom:
		return playCustomSound(config.CustomPath, config.Volume)
	}

	return nil
}

// playBell plays the terminal bell sound
func playBell() error {
	fmt.Print("\a")
	return nil
}

// flashTerminal flashes the terminal using reverse video
func flashTerminal() error {
	fmt.Print("\033[?5h") // Enable reverse video
	time.Sleep(100 * time.Millisecond)
	fmt.Print("\033[?5l") // Disable reverse video
	return nil
}

// playSystemSound plays a system sound (platform-specific)
func playSystemSound(soundType SoundType, volume float64) error {
	switch runtime.GOOS {
	case "darwin":
		return playMacOSSound(soundType, volume)
	case "linux":
		return playLinuxSound(soundType, volume)
	case "windows":
		return playWindowsSound(soundType, volume)
	default:
		// Fallback to terminal bell
		return playBell()
	}
}

// playMacOSSound plays a system sound on macOS
func playMacOSSound(soundType SoundType, volume float64) error {
	soundFile := "/System/Library/Sounds/Glass.aiff"
	if soundType == SoundError {
		soundFile = "/System/Library/Sounds/Basso.aiff"
	}

	cmd := exec.Command("afplay", "-v", fmt.Sprintf("%.1f", volume), soundFile)
	return cmd.Start() // Use Start instead of Run to not block
}

// playLinuxSound plays a system sound on Linux
func playLinuxSound(soundType SoundType, volume float64) error {
	soundFile := "/usr/share/sounds/freedesktop/stereo/complete.oga"
	if soundType == SoundError {
		soundFile = "/usr/share/sounds/freedesktop/stereo/dialog-error.oga"
	}

	// Try paplay first (PulseAudio)
	cmd := exec.Command("paplay", soundFile)
	if err := cmd.Start(); err == nil {
		return nil
	}

	// Fallback to aplay (ALSA)
	cmd = exec.Command("aplay", soundFile)
	if err := cmd.Start(); err == nil {
		return nil
	}

	// Final fallback to terminal bell
	return playBell()
}

// playWindowsSound plays a system sound on Windows
func playWindowsSound(soundType SoundType, volume float64) error {
	sound := "Asterisk"
	if soundType == SoundError {
		sound = "Hand"
	}

	cmd := exec.Command("powershell", "-c",
		fmt.Sprintf("[System.Media.SystemSounds]::%s.Play()", sound))
	return cmd.Start() // Use Start instead of Run to not block
}

// playCustomSound plays a custom sound file
func playCustomSound(path string, volume float64) error {
	if path == "" {
		return playBell()
	}

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("afplay", "-v", fmt.Sprintf("%.1f", volume), path)
	case "linux":
		cmd = exec.Command("paplay", path)
	case "windows":
		// Windows doesn't have a simple built-in command-line player
		// Fallback to bell
		return playBell()
	default:
		return playBell()
	}

	return cmd.Start()
}

// NotifyComplete plays a completion notification
func NotifyComplete(config NotificationConfig) error {
	if !config.NotifyOnComplete {
		return nil
	}
	return PlayNotification(SoundChime, config)
}

// NotifyError plays an error notification
func NotifyError(config NotificationConfig) error {
	if !config.NotifyOnError {
		return nil
	}
	return PlayNotification(SoundError, config)
}

// NotifyConfirmation plays a confirmation needed notification
func NotifyConfirmation(config NotificationConfig) error {
	if !config.NotifyOnConfirmation {
		return nil
	}
	return PlayNotification(SoundChime, config)
}
