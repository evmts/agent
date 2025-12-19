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
# Native module build stage
# =============================================================================
FROM base AS native-build
WORKDIR /app/native

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

# Copy native module source
COPY native/package.json native/bun.lock* ./
COPY native/Cargo.toml native/Cargo.lock ./
COPY native/build.rs ./
COPY native/src ./src
COPY native/.cargo ./.cargo

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

# Copy native module with built binary
COPY native/package.json native/index.js native/index.d.ts ./native/
COPY native/src ./native/src
COPY --from=native-build /app/native/*.node ./native/

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
