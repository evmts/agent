package agent

import (
	"context"
	"fmt"
	"net/http"
)

// AbortSession aborts an active session.
func (c *Client) AbortSession(ctx context.Context, sessionID string) error {
	var result bool
	return c.doRequest(ctx, http.MethodPost, "/session/"+sessionID+"/abort", nil, &result)
}

// GetSessionDiff returns file diffs for a session.
func (c *Client) GetSessionDiff(ctx context.Context, sessionID string, messageID *string) ([]FileDiff, error) {
	path := "/session/" + sessionID + "/diff"
	if messageID != nil {
		path = fmt.Sprintf("%s?messageID=%s", path, *messageID)
	}

	var result []FileDiff
	if err := c.doRequest(ctx, http.MethodGet, path, nil, &result); err != nil {
		return nil, err
	}
	return result, nil
}

// ForkSession creates a fork of a session.
func (c *Client) ForkSession(ctx context.Context, sessionID string, req *ForkRequest) (*Session, error) {
	if req == nil {
		req = &ForkRequest{}
	}
	var result Session
	if err := c.doRequest(ctx, http.MethodPost, "/session/"+sessionID+"/fork", req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// RevertSession reverts a session to a specific message.
func (c *Client) RevertSession(ctx context.Context, sessionID string, req *RevertRequest) (*Session, error) {
	var result Session
	if err := c.doRequest(ctx, http.MethodPost, "/session/"+sessionID+"/revert", req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// UnrevertSession undoes a revert on a session.
func (c *Client) UnrevertSession(ctx context.Context, sessionID string) (*Session, error) {
	var result Session
	if err := c.doRequest(ctx, http.MethodPost, "/session/"+sessionID+"/unrevert", nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}
