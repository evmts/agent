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
RUN bun install --frozen-lockfile

# =============================================================================
# Snapshot module build stage (Rust/napi-rs for jj-lib)
# =============================================================================
FROM base AS snapshot-build
WORKDIR /app/snapshot

# Install Rust and build dependencies
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Copy snapshot module source
COPY snapshot/package.json snapshot/bun.lock* ./
COPY snapshot/Cargo.toml snapshot/Cargo.lock ./
COPY snapshot/build.rs ./
COPY snapshot/src ./src
COPY snapshot/.cargo ./.cargo

# Install napi-rs CLI and build
RUN bun install
RUN bun run build

# =============================================================================
# Build stage (Astro)
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

# Copy native module (TypeScript/WebUI)
COPY native ./native

# Copy snapshot module with built binary
COPY snapshot/package.json snapshot/index.js snapshot/index.d.ts ./snapshot/
COPY snapshot/src ./snapshot/src
COPY --from=snapshot-build /app/snapshot/*.node ./snapshot/

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

CMD ["bun", "./dist/server/entry.mjs"]

# =============================================================================
# TUI (Terminal User Interface)
# =============================================================================
FROM base AS tui-build
WORKDIR /app/tui

# Copy TUI source
COPY tui/package.json tui/bun.lock* ./
RUN bun install --frozen-lockfile

COPY tui/src ./src
COPY tui/tsconfig.json ./

# Build TUI binary
RUN bun build src/index.ts --compile --outfile plue

# =============================================================================
# TUI Runtime
# =============================================================================
FROM base AS tui
WORKDIR /app

# Copy the compiled binary
COPY --from=tui-build /app/tui/plue ./plue

# Default API URL for container networking
ENV PLUE_API_URL=http://api:4000

# Make it executable and add to path
RUN chmod +x ./plue && ln -s /app/plue /usr/local/bin/plue

CMD ["./plue"]
