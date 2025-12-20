# =============================================================================
# Base stage - shared dependencies for web/tui (Bun)
# =============================================================================
FROM oven/bun:1 AS base
WORKDIR /app

# Install curl for healthchecks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Dependencies stage (for web frontend)
# =============================================================================
FROM base AS deps
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

# =============================================================================
# Build stage (Astro)
# =============================================================================
FROM base AS build
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build Astro for production (skip type checking - done in CI)
RUN bunx astro build

# =============================================================================
# API Server (Zig)
# =============================================================================
FROM debian:bookworm-slim AS api-build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    build-essential \
    pkg-config \
    libssl-dev \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Zig
ARG ZIG_VERSION=0.14.0
RUN curl -L "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" | tar -xJ -C /opt \
    && ln -s /opt/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig

# Install Rust (for jj-ffi)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Copy server source
COPY server ./server
COPY core ./core
COPY db ./db

# Build the Zig server (includes jj-ffi build via build.zig)
WORKDIR /app/server
RUN zig build -Doptimize=ReleaseFast

# =============================================================================
# API Runtime
# =============================================================================
FROM debian:bookworm-slim AS api
ENV PORT=4000

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the built binary and required libraries
COPY --from=api-build /app/server/zig-out/bin/server-zig ./server
COPY --from=api-build /app/server/jj-ffi/target/release/libjj_ffi.so /usr/local/lib/
RUN ldconfig

EXPOSE 4000

CMD ["./server"]

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
