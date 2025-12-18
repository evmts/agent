package agent

import (
	"context"
	"io"
	"log/slog"
	"os"
	"strings"
	"time"
)

// LogLevel represents the logging level.
type LogLevel int

const (
	// LevelDebug logs verbose debugging information.
	LevelDebug LogLevel = iota
	// LevelInfo logs normal operational messages.
	LevelInfo
	// LevelWarn logs warning messages.
	LevelWarn
	// LevelError logs error messages only.
	LevelError
	// LevelOff disables all logging.
	LevelOff
)

// Logger wraps slog for SDK/TUI logging.
type Logger struct {
	slog  *slog.Logger
	level LogLevel
}

// Default logger instance (disabled by default for SDK usage).
var defaultLogger = &Logger{level: LevelOff}

// SetLogger sets the global default logger.
func SetLogger(l *Logger) {
	if l != nil {
		defaultLogger = l
	}
}

// GetLogger returns the current default logger.
func GetLogger() *Logger {
	return defaultLogger
}

// NewLogger creates a new logger with the specified level and output.
func NewLogger(level LogLevel, w io.Writer) *Logger {
	if w == nil {
		w = os.Stderr
	}

	var slogLevel slog.Level
	switch level {
	case LevelDebug:
		slogLevel = slog.LevelDebug
	case LevelInfo:
		slogLevel = slog.LevelInfo
	case LevelWarn:
		slogLevel = slog.LevelWarn
	case LevelError:
		slogLevel = slog.LevelError
	default:
		slogLevel = slog.LevelInfo
	}

	opts := &slog.HandlerOptions{
		Level: slogLevel,
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			// Simplify time format
			if a.Key == slog.TimeKey {
				t := a.Value.Time()
				a.Value = slog.StringValue(t.Format("15:04:05.000"))
			}
			return a
		},
	}

	handler := slog.NewTextHandler(w, opts)
	return &Logger{
		slog:  slog.New(handler),
		level: level,
	}
}

// NewLoggerFromEnv creates a logger based on LOG_LEVEL environment variable.
// Defaults to LevelOff (no logging) if not set.
func NewLoggerFromEnv() *Logger {
	levelStr := strings.ToUpper(os.Getenv("LOG_LEVEL"))
	var level LogLevel
	switch levelStr {
	case "DEBUG":
		level = LevelDebug
	case "INFO":
		level = LevelInfo
	case "WARN", "WARNING":
		level = LevelWarn
	case "ERROR":
		level = LevelError
	default:
		level = LevelOff
	}

	if level == LevelOff {
		return &Logger{level: LevelOff}
	}

	return NewLogger(level, os.Stderr)
}

// IsEnabled returns true if logging is enabled at any level.
func (l *Logger) IsEnabled() bool {
	return l != nil && l.level != LevelOff && l.slog != nil
}

// Debug logs a debug message.
func (l *Logger) Debug(msg string, args ...any) {
	if l.IsEnabled() && l.level <= LevelDebug {
		l.slog.Debug(msg, args...)
	}
}

// Info logs an info message.
func (l *Logger) Info(msg string, args ...any) {
	if l.IsEnabled() && l.level <= LevelInfo {
		l.slog.Info(msg, args...)
	}
}

// Warn logs a warning message.
func (l *Logger) Warn(msg string, args ...any) {
	if l.IsEnabled() && l.level <= LevelWarn {
		l.slog.Warn(msg, args...)
	}
}

// Error logs an error message.
func (l *Logger) Error(msg string, args ...any) {
	if l.IsEnabled() && l.level <= LevelError {
		l.slog.Error(msg, args...)
	}
}

// With returns a new logger with the given attributes.
func (l *Logger) With(args ...any) *Logger {
	if !l.IsEnabled() {
		return l
	}
	return &Logger{
		slog:  l.slog.With(args...),
		level: l.level,
	}
}

// WithContext returns a logger for use in context-aware operations.
func (l *Logger) WithContext(ctx context.Context) *Logger {
	return l
}

// RequestLogger provides helpers for logging HTTP requests.
type RequestLogger struct {
	logger    *Logger
	method    string
	path      string
	startTime time.Time
}

// StartRequest begins timing an HTTP request.
func (l *Logger) StartRequest(method, path string) *RequestLogger {
	if !l.IsEnabled() {
		return &RequestLogger{logger: l}
	}
	l.Debug("request started", "method", method, "path", path)
	return &RequestLogger{
		logger:    l,
		method:    method,
		path:      path,
		startTime: time.Now(),
	}
}

// Success logs a successful request completion.
func (r *RequestLogger) Success(statusCode int) {
	if !r.logger.IsEnabled() {
		return
	}
	duration := time.Since(r.startTime)
	r.logger.Info("request completed",
		"method", r.method,
		"path", r.path,
		"status", statusCode,
		"duration_ms", duration.Milliseconds(),
	)
}

// Error logs a request error.
func (r *RequestLogger) Error(err error) {
	if !r.logger.IsEnabled() {
		return
	}
	duration := time.Since(r.startTime)
	r.logger.Error("request failed",
		"method", r.method,
		"path", r.path,
		"error", err.Error(),
		"duration_ms", duration.Milliseconds(),
	)
}
