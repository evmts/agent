package agent

import (
	"context"
	"net/http"
)

// ListSessions returns all sessions.
func (c *Client) ListSessions(ctx context.Context) ([]Session, error) {
	var result []Session
	if err := c.doRequest(ctx, http.MethodGet, "/session", nil, &result); err != nil {
		return nil, err
	}
	return result, nil
}

// CreateSession creates a new session.
func (c *Client) CreateSession(ctx context.Context, req *CreateSessionRequest) (*Session, error) {
	if req == nil {
		req = &CreateSessionRequest{}
	}
	var result Session
	if err := c.doRequest(ctx, http.MethodPost, "/session", req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// GetSession retrieves a session by ID.
func (c *Client) GetSession(ctx context.Context, sessionID string) (*Session, error) {
	var result Session
	if err := c.doRequest(ctx, http.MethodGet, "/session/"+sessionID, nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// DeleteSession deletes a session.
func (c *Client) DeleteSession(ctx context.Context, sessionID string) error {
	var result bool
	return c.doRequest(ctx, http.MethodDelete, "/session/"+sessionID, nil, &result)
}

// UpdateSession updates a session's title or archived status.
func (c *Client) UpdateSession(ctx context.Context, sessionID string, req *UpdateSessionRequest) (*Session, error) {
	var result Session
	if err := c.doRequest(ctx, http.MethodPatch, "/session/"+sessionID, req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}
