# Repository Topics Implementation

This document describes the implementation of repository topics/tags feature for Plue.

## Overview

Repository topics allow users to categorize and discover repositories by subject matter. Users can add up to 20 topics per repository, and topics are searchable and filterable across the platform.

## Database Changes

### Schema Update (`db/schema.sql`)

Added `topics` column to the `repositories` table:

```sql
CREATE TABLE IF NOT EXISTS repositories (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE RESTRICT,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  is_public BOOLEAN DEFAULT true,
  default_branch VARCHAR(255) DEFAULT 'main',
  topics TEXT[] DEFAULT '{}',  -- NEW: Array of topic strings
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, name)
);
```

### Migration Script (`db/migrations/add_topics_to_repositories.sql`)

A migration script is provided to add the topics column to existing databases:

```bash
psql -d plue < db/migrations/add_topics_to_repositories.sql
```

This migration:
- Adds the `topics` column if it doesn't exist
- Creates a GIN index for efficient topic searches

## API Routes

### New Route File: `server/routes/repositories.ts`

Two endpoints for managing repository topics:

#### GET `/:user/:repo/topics`

Returns the topics for a repository.

**Response:**
```json
{
  "topics": ["rust", "blockchain", "ethereum"]
}
```

#### PUT `/:user/:repo/topics`

Updates the topics for a repository.

**Request:**
```json
{
  "topics": ["rust", "blockchain", "ethereum"]
}
```

**Validation:**
- Maximum 20 topics
- Each topic max 35 characters
- Only lowercase letters, numbers, and hyphens allowed
- Topics are automatically lowercased and trimmed

**Response:**
```json
{
  "topics": ["rust", "blockchain", "ethereum"]
}
```

### Route Registration

The repositories route is registered in `server/routes/index.ts`:

```typescript
import repositories from './repositories';
app.route('/', repositories);
```

## Frontend Components

### TopicBadge Component (`ui/components/TopicBadge.astro`)

Reusable component for displaying topic badges:

```astro
<TopicBadge topic="rust" />
<TopicBadge topic="ethereum" clickable={false} />
```

**Props:**
- `topic: string` - The topic name
- `clickable?: boolean` - Whether the badge is clickable (default: true)

**Styling:**
- Pill-shaped badge with border
- Hover effect for clickable badges
- Links to explore page with topic filter

## Pages

### 1. Repository Index Page (`ui/pages/[user]/[repo]/index.astro`)

**Changes:**
- Added topics display below description
- Topics are clickable and link to explore page
- Added "Settings" link to repo navigation

### 2. Repository Settings Page (`ui/pages/[user]/[repo]/settings.astro`)

**NEW PAGE** - Comprehensive repository settings interface:

**Features:**
- Description editor
- Topics input (comma-separated)
  - Real-time preview of topics
  - Client-side validation
  - Visual feedback for valid topics
- Default branch selector (populated from existing branches)
- Visibility toggle (Public/Private)
- Danger zone with delete repository button

**Topics Input:**
- Comma-separated input
- Live preview shows validated topics as badges
- Invalid topics are filtered out automatically
- Max 20 topics enforced

### 3. Explore Page (`ui/pages/explore.astro`)

**NEW PAGE** - Repository discovery and search:

**Features:**
- Search repositories by name or description
- Filter by topic
- Popular topics grid showing repo counts
- Sort options (Recent, Name)
- Clean URL parameters for sharing filtered views

**URL Patterns:**
- `/explore` - All public repositories
- `/explore?q=ethereum` - Search for "ethereum"
- `/explore?topic=rust` - Filter by "rust" topic
- `/explore?topic=blockchain&sort=name` - Filter and sort

**Popular Topics Section:**
- Shows top 20 topics by repository count
- Grid layout with topic cards
- Each card shows topic name and repo count
- Clickable to filter by that topic

### 4. Home Page (`ui/pages/index.astro`)

**Changes:**
- Repository cards now display topics
- Topics are clickable and link to explore page

### 5. RepoCard Component (`ui/components/RepoCard.astro`)

**Changes:**
- Added topics display
- Topics shown below description
- Maintains consistent styling across all repo lists

## Type Updates

Updated `ui/lib/types.ts` to include topics:

```typescript
export interface Repository {
  id: number;
  user_id: number;
  name: string;
  description: string | null;
  is_public: boolean;
  default_branch: string;
  topics: string[];  // NEW
  created_at: Date;
  updated_at: Date;
  username?: string;
}
```

## Styling

All styles follow Plue's brutalist design system:

- **Colors:** Uses existing CSS variables (`--border`, `--gray-*`, etc.)
- **Typography:** Monospace font, consistent sizing
- **Interactions:** Subtle hover effects, no loading spinners
- **Responsive:** Mobile-friendly layouts

**Topic Badge Styling:**
- Border: `1px solid var(--border)`
- Background: `var(--gray-900)`
- Border radius: `99px` (pill shape)
- Padding: `4px 10px`
- Font size: `11px`
- Hover: Lighter background and border

## User Flow

### Adding Topics to a Repository

1. Navigate to repository settings: `/:user/:repo/settings`
2. Enter topics in comma-separated format: `rust, blockchain, ethereum`
3. See live preview of validated topics
4. Click "Save changes"
5. Topics appear on repository page and cards

### Discovering Repositories by Topic

1. Click on any topic badge → redirects to `/explore?topic=<topic>`
2. Or visit explore page and browse popular topics
3. Or search for repositories by name/description

### Navigation

- **Header:** Added "explore" link between "home" and "new"
- **Repository Nav:** Added "Settings" tab
- **Explore Page:** Breadcrumb and clear filters

## Implementation Notes

### Topic Validation

Topics must match the regex: `^[a-z0-9-]+$`

This allows:
- Lowercase letters (a-z)
- Numbers (0-9)
- Hyphens (-)

Invalid examples:
- `Rust` (uppercase)
- `web3.js` (periods)
- `c++` (special chars)
- `hello world` (spaces)

Valid examples:
- `rust`
- `web3`
- `ethereum-2`
- `proof-of-stake`

### Database Queries

The explore page uses PostgreSQL array operations:

```sql
-- Filter by topic
SELECT * FROM repositories
WHERE 'rust' = ANY(topics)

-- Get popular topics
SELECT unnest(topics) as topic, COUNT(*) as count
FROM repositories
WHERE is_public = true AND array_length(topics, 1) > 0
GROUP BY topic
ORDER BY count DESC
```

### Performance

- GIN index on `topics` column for fast array searches
- Results limited to 50 repositories
- Popular topics limited to 20

## Testing

To test the implementation:

1. **Run migration:**
   ```bash
   psql -d plue < db/migrations/add_topics_to_repositories.sql
   ```

2. **Start the server:**
   ```bash
   bun run dev
   ```

3. **Test adding topics:**
   - Navigate to a repository
   - Click "Settings"
   - Add topics: `rust, blockchain, ethereum`
   - Save and verify they appear on the repo page

4. **Test explore page:**
   - Navigate to `/explore`
   - Click on a popular topic
   - Verify repositories are filtered correctly
   - Test search functionality

5. **Test topic badges:**
   - Click a topic badge on any repository
   - Verify it links to `/explore?topic=<topic>`
   - Verify the explore page filters correctly

## Files Changed/Created

### Created:
- `ui/components/TopicBadge.astro` - Reusable topic badge component
- `ui/pages/explore.astro` - Repository exploration and search page
- `ui/pages/[user]/[repo]/settings.astro` - Repository settings page
- `server/routes/repositories.ts` - API routes for topics
- `db/migrations/add_topics_to_repositories.sql` - Migration script

### Modified:
- `db/schema.sql` - Added topics column to repositories table
- `ui/lib/types.ts` - Added topics field to Repository interface
- `ui/pages/index.astro` - No changes needed (uses RepoCard)
- `ui/pages/[user]/[repo]/index.astro` - Display topics, add Settings link
- `ui/components/RepoCard.astro` - Display topics on repository cards
- `ui/components/Header.astro` - Added "explore" navigation link
- `server/routes/index.ts` - Registered repositories route

## Future Enhancements

Possible improvements:
- Topic suggestions based on repository content
- Trending topics by time period
- Topic descriptions/metadata
- Topic aliases/redirects
- Topic categories/hierarchies
- User-specific topic preferences
- Repository recommendations based on followed topics
