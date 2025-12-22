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
# Copy local @plue/snapshot package (required by package.json)
COPY snapshot ./snapshot
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
    libgcc-s1 \
    && rm -rf /var/lib/apt/lists/*

# Install Zig (detect architecture)
ARG ZIG_VERSION=0.15.1
ARG TARGETARCH
RUN ZIG_ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "x86_64" ;; \
        "arm64") echo "aarch64" ;; \
        *) echo "x86_64" ;; \
    esac) && \
    curl -L "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" | tar -xJ -C /opt && \
    ln -s /opt/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}/zig /usr/local/bin/zig

# Install Rust (for jj-ffi)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Copy server source (voltaire must be a real directory, not a symlink)
# If using symlink locally, run: rm server/voltaire && git submodule update --init server/voltaire
COPY server ./server
COPY core ./core
COPY db ./db

# Build voltaire's Rust crypto wrappers (panic=abort avoids unwind dependency)
WORKDIR /app/server/voltaire
RUN RUSTFLAGS="-C panic=abort" cargo build --release

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

# Create expected path for jj_ffi library (binary has absolute rpath)
RUN mkdir -p /app/server/jj-ffi/target/release

# Copy the built binary and required libraries
COPY --from=api-build /app/server/zig-out/bin/server-zig ./server-bin
COPY --from=api-build /app/server/jj-ffi/target/release/libjj_ffi.so /app/server/jj-ffi/target/release/
RUN ldconfig

EXPOSE 4000

CMD ["./server-bin"]

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
