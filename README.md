# plue

A minimal, brutalist GitHub competitor built with Astro SSR.

## Features

- Repository listing and creation
- File browser with tree view
- README rendering (markdown)
- Issue tracking (create, open/close, comments)
- Real git integration (clone URLs, commits, branches)
- Mock users (no auth required)

## Setup

1. Install dependencies:

```bash
bun install
```

2. Start Postgres with Docker:

```bash
docker compose up -d
```

3. Run database migrations:

```bash
bun run db:migrate
```

4. Start the dev server:

```bash
bun run dev
```

Open http://localhost:5173

## Usage

- Create a new repository from the home page
- Browse files, view README, check commits
- Create and manage issues with comments
- Clone repositories locally using the file:// URL

## Stack

- **Astro** - SSR framework
- **Postgres** - Database (via Electric SQL docker-compose)
- **Git** - Real git repos on filesystem
- **No frameworks** - Pure CSS, minimal JS

## Project Structure

```
src/
├── layouts/Layout.astro     # Base layout with brutalist styles
├── components/              # Reusable components
├── lib/                     # Database, git, markdown utilities
└── pages/
    ├── index.astro          # Home - all repos
    ├── new.astro            # Create repo
    ├── [user]/              # User profile
    └── [user]/[repo]/       # Repo pages
        ├── index.astro      # Repo home
        ├── tree/            # File browser
        ├── blob/            # File viewer
        ├── commits/         # Commit history
        └── issues/          # Issue tracker
```
