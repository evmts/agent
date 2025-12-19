# =============================================================================
# Base stage - shared dependencies
# =============================================================================
FROM oven/bun:1 AS base
WORKDIR /app

# Install curl for healthchecks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Dependencies stage
# =============================================================================
FROM base AS deps
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile --production=false

# =============================================================================
# Build stage
# =============================================================================
FROM base AS build
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build Astro for production
RUN bun run build

# =============================================================================
# API Server
# =============================================================================
FROM base AS api
ENV NODE_ENV=production
ENV PORT=4000

# Copy dependencies
COPY --from=deps /app/node_modules ./node_modules

# Copy source files needed for API
COPY package.json ./
COPY server ./server
COPY core ./core
COPY db ./db
COPY ai ./ai
COPY native ./native

# Create entrypoint script
RUN echo '#!/bin/sh\nbun run server/main.ts' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

EXPOSE 4000

CMD ["bun", "run", "server/main.ts"]

# =============================================================================
# Web Frontend (Astro SSR)
# =============================================================================
FROM base AS web
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=5173

# Copy built Astro output
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY package.json ./

EXPOSE 5173

CMD ["node", "./dist/server/entry.mjs"]
