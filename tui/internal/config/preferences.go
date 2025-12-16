package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// ResumePreference represents the user's preference for session resumption
type ResumePreference string

const (
	// ResumeAlwaysAsk prompts the user on every startup
	ResumeAlwaysAsk ResumePreference = "ask"
	// ResumeAlwaysContinue automatically resumes the last session
	ResumeAlwaysContinue ResumePreference = "continue"
	// ResumeAlwaysNew always creates a new session
	ResumeAlwaysNew ResumePreference = "new"
)

// Default preference values
const (
	DefaultResumePreference = ResumeAlwaysAsk
	MaxSessionAge           = 24 * time.Hour // Sessions older than this won't trigger resume prompt
)

// LastSessionInfo contains information about the last active session
type LastSessionInfo struct {
	SessionID    string    `json:"sessionId"`
	Title        string    `json:"title"`
	LastActive   time.Time `json:"lastActive"`
	MessageCount int       `json:"messageCount"`
	LastMessage  string    `json:"lastMessage"` // Truncated preview
}

// NotificationPreferences stores notification settings
type NotificationPreferences struct {
	Enabled              bool    `json:"enabled"`
	SoundType            string  `json:"soundType"` // "bell", "chime", "custom", "visual"
	Volume               float64 `json:"volume"`
	CustomPath           string  `json:"customPath,omitempty"`
	NotifyOnComplete     bool    `json:"notifyOnComplete"`
	NotifyOnError        bool    `json:"notifyOnError"`
	NotifyOnConfirmation bool    `json:"notifyOnConfirmation"`
}

// DefaultNotificationPreferences returns the default notification preferences
func DefaultNotificationPreferences() NotificationPreferences {
	return NotificationPreferences{
		Enabled:              true,
		SoundType:            "bell",
		Volume:               0.8,
		NotifyOnComplete:     true,
		NotifyOnError:        true,
		NotifyOnConfirmation: true,
	}
}

// Preferences stores user preferences for the TUI
type Preferences struct {
	ResumePreference ResumePreference        `json:"resumePreference"`
	LastSession      *LastSessionInfo        `json:"lastSession,omitempty"`
	Notifications    NotificationPreferences `json:"notifications"`
}

// getConfigDir returns the configuration directory path
func getConfigDir() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(homeDir, ".config", "agent-tui"), nil
}

// getPreferencesPath returns the path to the preferences file
func getPreferencesPath() (string, error) {
	configDir, err := getConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(configDir, "preferences.json"), nil
}

// LoadPreferences loads preferences from disk
func LoadPreferences() (*Preferences, error) {
	prefPath, err := getPreferencesPath()
	if err != nil {
		return nil, err
	}

	// If file doesn't exist, return defaults
	if _, err := os.Stat(prefPath); os.IsNotExist(err) {
		return &Preferences{
			ResumePreference: DefaultResumePreference,
			Notifications:    DefaultNotificationPreferences(),
		}, nil
	}

	data, err := os.ReadFile(prefPath)
	if err != nil {
		return nil, err
	}

	var prefs Preferences
	if err := json.Unmarshal(data, &prefs); err != nil {
		return nil, err
	}

	// Ensure notification preferences have defaults if missing
	if prefs.Notifications.SoundType == "" {
		prefs.Notifications = DefaultNotificationPreferences()
	}

	return &prefs, nil
}

// SavePreferences saves preferences to disk
func SavePreferences(prefs *Preferences) error {
	configDir, err := getConfigDir()
	if err != nil {
		return err
	}

	// Create config directory if it doesn't exist
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return err
	}

	prefPath, err := getPreferencesPath()
	if err != nil {
		return err
	}

	data, err := json.MarshalIndent(prefs, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(prefPath, data, 0644)
}

// SaveLastSession saves the last active session information
func SaveLastSession(sessionID, title string, messageCount int, lastMessage string) error {
	prefs, err := LoadPreferences()
	if err != nil {
		// If we can't load, create new prefs
		prefs = &Preferences{
			ResumePreference: DefaultResumePreference,
			Notifications:    DefaultNotificationPreferences(),
		}
	}

	// Truncate last message to 200 characters for preview
	const maxMessageLen = 200
	if len(lastMessage) > maxMessageLen {
		lastMessage = lastMessage[:maxMessageLen] + "..."
	}

	prefs.LastSession = &LastSessionInfo{
		SessionID:    sessionID,
		Title:        title,
		LastActive:   time.Now(),
		MessageCount: messageCount,
		LastMessage:  lastMessage,
	}

	return SavePreferences(prefs)
}

// GetLastSession retrieves the last active session info, or nil if too old or doesn't exist
func GetLastSession() (*LastSessionInfo, error) {
	prefs, err := LoadPreferences()
	if err != nil {
		return nil, err
	}

	if prefs.LastSession == nil {
		return nil, nil
	}

	// Check if session is too old
	if time.Since(prefs.LastSession.LastActive) > MaxSessionAge {
		return nil, nil
	}

	return prefs.LastSession, nil
}

// GetResumePreference returns the user's resume preference
func GetResumePreference() (ResumePreference, error) {
	prefs, err := LoadPreferences()
	if err != nil {
		return DefaultResumePreference, err
	}
	return prefs.ResumePreference, nil
}

// SetResumePreference sets the user's resume preference
func SetResumePreference(pref ResumePreference) error {
	prefs, err := LoadPreferences()
	if err != nil {
		prefs = &Preferences{}
	}
	prefs.ResumePreference = pref
	return SavePreferences(prefs)
}

// ClearLastSession clears the saved last session info
func ClearLastSession() error {
	prefs, err := LoadPreferences()
	if err != nil {
		return err
	}
	prefs.LastSession = nil
	return SavePreferences(prefs)
}
