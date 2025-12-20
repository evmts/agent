# Issue Dependencies API Reference

This document describes the REST API endpoints for managing issue dependencies in Plue.

## Endpoints

### GET `/repos/:user/:repo/issues/:number/dependencies`

Get all dependencies for an issue.

**Parameters:**
- `user` (string): Repository owner username
- `repo` (string): Repository name
- `number` (integer): Issue number

**Response:** `200 OK`
```json
{
  "blocks": [
    {
      "number": 2,
      "title": "Fix login bug",
      "state": "open",
      "author": { "id": 1, "username": "alice" },
      "created_at": "2025-01-15T10:00:00Z",
      ...
    }
  ],
  "blocked_by": [
    {
      "number": 5,
      "title": "Implement authentication",
      "state": "closed",
      "author": { "id": 2, "username": "bob" },
      "created_at": "2025-01-10T10:00:00Z",
      ...
    }
  ]
}
```

**Error Responses:**
- `400 Bad Request`: Invalid issue number
- `404 Not Found`: Issue not found

---

### POST `/repos/:user/:repo/issues/:number/dependencies`

Add a dependency where this issue blocks another issue.

**Parameters:**
- `user` (string): Repository owner username
- `repo` (string): Repository name
- `number` (integer): Issue number (the blocking issue)

**Request Body:**
```json
{
  "blocks": 2
}
```

**Response:** `201 Created`
```json
{
  "blocking": {
    "number": 1,
    "title": "Current issue",
    "blocks": [2],
    "blocked_by": [],
    ...
  },
  "blocked": {
    "number": 2,
    "title": "Blocked issue",
    "blocks": [],
    "blocked_by": [1],
    ...
  }
}
```

**Error Responses:**
- `400 Bad Request`: Invalid issue number or self-dependency
- `404 Not Found`: Issue not found

**Example:**
```bash
curl -X POST http://localhost:3000/repos/alice/myrepo/issues/1/dependencies \
  -H "Content-Type: application/json" \
  -d '{"blocks": 2}'
```

---

### DELETE `/repos/:user/:repo/issues/:number/dependencies/:blockedNumber`

Remove a dependency where this issue no longer blocks another issue.

**Parameters:**
- `user` (string): Repository owner username
- `repo` (string): Repository name
- `number` (integer): Issue number (the blocking issue)
- `blockedNumber` (integer): The issue number to unblock

**Response:** `200 OK`
```json
{
  "blocking": {
    "number": 1,
    "blocks": [],
    ...
  },
  "blocked": {
    "number": 2,
    "blocked_by": [],
    ...
  }
}
```

**Error Responses:**
- `400 Bad Request`: Invalid issue number
- `404 Not Found`: Issue not found

**Example:**
```bash
curl -X DELETE http://localhost:3000/repos/alice/myrepo/issues/1/dependencies/2
```

---

### GET `/repos/:user/:repo/issues/:number/can-close`

Check if an issue can be closed (no open blocking issues).

**Parameters:**
- `user` (string): Repository owner username
- `repo` (string): Repository name
- `number` (integer): Issue number

**Response:** `200 OK`
```json
{
  "canClose": false,
  "openBlockers": [
    {
      "number": 5,
      "title": "Implement authentication",
      "state": "open",
      "author": { "id": 2, "username": "bob" },
      ...
    }
  ]
}
```

**Error Responses:**
- `400 Bad Request`: Invalid issue number
- `404 Not Found`: Issue not found

**Example:**
```bash
curl http://localhost:3000/repos/alice/myrepo/issues/2/can-close
```

---

## Dependency Semantics

### Bidirectional Relationships

Dependencies are automatically maintained as bidirectional relationships:

- When issue A is set to block issue B:
  - Issue A's `blocks` array includes B
  - Issue B's `blocked_by` array includes A

- Removing the dependency updates both issues

### Creating "Blocked By" Relationships

To add an issue to the "blocked by" list, make a request from the **blocking** issue's perspective:

```bash
# To make issue 3 "blocked by" issue 1
# POST from issue 1 to block issue 3
curl -X POST http://localhost:3000/repos/alice/myrepo/issues/1/dependencies \
  -H "Content-Type: application/json" \
  -d '{"blocks": 3}'
```

The UI handles this automatically by posting to the correct issue endpoint based on the relationship type.

### Self-Dependencies

Self-dependencies are prevented. Attempting to make an issue depend on itself will return a `400 Bad Request` error.

### Idempotency

Adding the same dependency multiple times is safe and idempotent. The relationship is created only once.

---

## Integration Examples

### JavaScript/TypeScript

```typescript
// Add dependency
async function addDependency(user: string, repo: string, blockingIssue: number, blockedIssue: number) {
  const response = await fetch(
    `/repos/${user}/${repo}/issues/${blockingIssue}/dependencies`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ blocks: blockedIssue })
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error);
  }

  return await response.json();
}

// Get dependencies
async function getDependencies(user: string, repo: string, issueNumber: number) {
  const response = await fetch(
    `/repos/${user}/${repo}/issues/${issueNumber}/dependencies`
  );
  return await response.json();
}

// Check if can close
async function canCloseIssue(user: string, repo: string, issueNumber: number) {
  const response = await fetch(
    `/repos/${user}/${repo}/issues/${issueNumber}/can-close`
  );
  const { canClose, openBlockers } = await response.json();

  if (!canClose) {
    console.log(`Cannot close: blocked by ${openBlockers.length} open issues`);
  }

  return canClose;
}
```

### curl Examples

```bash
# Get all dependencies for issue 1
curl http://localhost:3000/repos/alice/myrepo/issues/1/dependencies

# Make issue 1 block issue 2
curl -X POST http://localhost:3000/repos/alice/myrepo/issues/1/dependencies \
  -H "Content-Type: application/json" \
  -d '{"blocks": 2}'

# Remove dependency
curl -X DELETE http://localhost:3000/repos/alice/myrepo/issues/1/dependencies/2

# Check if issue can be closed
curl http://localhost:3000/repos/alice/myrepo/issues/2/can-close
```

---

## Error Handling

All endpoints return standard HTTP status codes:

- `200 OK`: Successful request
- `201 Created`: Dependency created successfully
- `400 Bad Request`: Invalid parameters (e.g., invalid issue number, self-dependency)
- `404 Not Found`: Issue not found
- `500 Internal Server Error`: Server error

Error responses include a JSON object with an `error` field:

```json
{
  "error": "An issue cannot depend on itself"
}
```
