# Issue Tracking API

Complete implementation of issue tracking routes for the Zig server, matching the Bun implementation API.

## Implementation Details

### Files Created/Modified

1. **Database Schema** (`/Users/williamcory/agent/db/schema.sql`)
   - Added `labels` table for issue labels
   - Added `issue_labels` junction table for many-to-many relationship

2. **Database Functions** (`/Users/williamcory/agent/server-zig/src/lib/db_issues.zig`)
   - Repository operations: `getRepositoryByName()`
   - Issue operations: `listIssues()`, `getIssue()`, `createIssue()`, `updateIssue()`, `closeIssue()`, `reopenIssue()`, `getIssueCounts()`
   - Comment operations: `getComments()`, `addComment()`, `updateComment()`, `deleteComment()`
   - Label operations: `getLabels()`, `createLabel()`, `addLabelToIssue()`, `removeLabelFromIssue()`, `getIssueLabels()`, `getLabelByName()`

3. **Route Handlers** (`/Users/williamcory/agent/server-zig/src/routes/issues.zig`)
   - All 14 endpoints implemented with proper authentication and error handling

4. **Route Registration** (`/Users/williamcory/agent/server-zig/src/routes.zig`)
   - Registered all issue routes in the router configuration

## API Endpoints

### Issue Endpoints

#### 1. List Issues
```
GET /api/:user/:repo/issues?state=<open|closed|all>
```
Returns list of issues with counts.

**Response:**
```json
{
  "issues": [...],
  "counts": { "open": 5, "closed": 3 },
  "total": 8
}
```

#### 2. Get Single Issue
```
GET /api/:user/:repo/issues/:number
```
Returns issue with comments.

**Response:**
```json
{
  "id": 1,
  "number": 1,
  "title": "Bug report",
  "body": "Description",
  "state": "open",
  "createdAt": 1234567890,
  "updatedAt": 1234567890,
  "comments": [...]
}
```

#### 3. Create Issue
```
POST /api/:user/:repo/issues
Authentication: Required
```

**Request Body:**
```json
{
  "title": "New issue",
  "body": "Description"
}
```

**Response:** Created issue (201 status)

#### 4. Update Issue
```
PATCH /api/:user/:repo/issues/:number
Authentication: Required
```

**Request Body:**
```json
{
  "title": "Updated title",
  "body": "Updated description"
}
```

**Response:** Updated issue

#### 5. Close Issue
```
POST /api/:user/:repo/issues/:number/close
Authentication: Required
```

**Response:** Closed issue

#### 6. Reopen Issue
```
POST /api/:user/:repo/issues/:number/reopen
Authentication: Required
```

**Response:** Reopened issue

### Comment Endpoints

#### 7. Get Comments
```
GET /api/:user/:repo/issues/:number/comments
```

**Response:**
```json
{
  "comments": [
    {
      "id": 1,
      "body": "Comment text",
      "authorId": 1,
      "createdAt": 1234567890,
      "edited": false
    }
  ]
}
```

#### 8. Add Comment
```
POST /api/:user/:repo/issues/:number/comments
Authentication: Required
```

**Request Body:**
```json
{
  "body": "Comment text"
}
```

**Response:** Created comment (201 status)

#### 9. Update Comment
```
PATCH /api/:user/:repo/issues/:number/comments/:commentId
Authentication: Required
```

**Request Body:**
```json
{
  "body": "Updated comment text"
}
```

**Response:** Updated comment

#### 10. Delete Comment
```
DELETE /api/:user/:repo/issues/:number/comments/:commentId
Authentication: Required
```

**Response:**
```json
{
  "success": true
}
```

### Label Endpoints

#### 11. Get Labels
```
GET /api/:user/:repo/labels
```

**Response:**
```json
{
  "labels": [
    {
      "id": 1,
      "name": "bug",
      "color": "#ff0000",
      "description": "Bug reports"
    }
  ]
}
```

#### 12. Create Label
```
POST /api/:user/:repo/labels
Authentication: Required
```

**Request Body:**
```json
{
  "name": "enhancement",
  "color": "#00ff00",
  "description": "Feature requests"
}
```

**Response:** Created label (201 status)

#### 13. Add Labels to Issue
```
POST /api/:user/:repo/issues/:number/labels
Authentication: Required
```

**Request Body:**
```json
{
  "labels": ["bug", "critical"]
}
```

**Response:**
```json
{
  "success": true
}
```

#### 14. Remove Label from Issue
```
DELETE /api/:user/:repo/issues/:number/labels/:labelId
Authentication: Required
```

**Response:**
```json
{
  "success": true
}
```

## Database Schema

### Labels Table
```sql
CREATE TABLE IF NOT EXISTS labels (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  color VARCHAR(7) NOT NULL, -- hex color like #ff0000
  description TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);
```

### Issue Labels Junction Table
```sql
CREATE TABLE IF NOT EXISTS issue_labels (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  label_id INTEGER NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
  added_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(issue_id, label_id)
);
```

## Build Status

All routes compile successfully with Zig 0.15.1. The implementation:
- Uses proper ArrayList syntax for Zig 0.15.1 (`.init(allocator)` pattern)
- Follows httpz request API (`req.url.query.get()` for query parameters)
- Uses numeric HTTP status codes (200, 201, 400, 401, 404, 500)
- Includes proper authentication checks on all mutating operations
- Returns appropriate JSON error messages

## Testing

To test the API:

1. Build the server:
   ```bash
   zig build
   ```

2. Run the server:
   ```bash
   ./zig-out/bin/server-zig
   ```

3. Test endpoints with curl or Postman:
   ```bash
   # List issues
   curl http://localhost:8080/api/user/repo/issues

   # Create issue (requires auth token)
   curl -X POST http://localhost:8080/api/user/repo/issues \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{"title":"Test issue","body":"Description"}'
   ```

## Notes

- The Bun implementation uses git-based file storage for issues
- This Zig implementation uses PostgreSQL database for better performance and queryability
- Authentication is required for all POST, PATCH, and DELETE operations
- All timestamps are returned as Unix epoch seconds
- Error responses follow a consistent JSON format: `{"error": "message"}`
