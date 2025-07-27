# Build stage for Zig application
FROM alpine:3.19 as zig-builder

ARG ZIGVER=0.14.0

RUN apk update && \
    apk add \
        curl \
        xz \
        git \
        libc-dev \
        nodejs \
        npm

# Install Zig
RUN mkdir -p /deps
WORKDIR /deps
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then ZIG_ARCH="aarch64"; else ZIG_ARCH="x86_64"; fi && \
    curl -L https://ziglang.org/download/$ZIGVER/zig-linux-$ZIG_ARCH-$ZIGVER.tar.xz -O && \
    tar xf zig-linux-$ZIG_ARCH-$ZIGVER.tar.xz && \
    mv zig-linux-$ZIG_ARCH-$ZIGVER/ /usr/local/zig/

ENV PATH="/usr/local/zig:${PATH}"

# Copy source code
WORKDIR /app
COPY . .

# Build Zig application
RUN zig build -Doptimize=ReleaseSafe

# Build stage for SPA assets
FROM node:20-alpine as spa-builder

WORKDIR /app/gui
COPY src/gui/package*.json ./
RUN npm ci

COPY src/gui/ ./
RUN npm run build

# Web server stage for SPA
FROM nginx:alpine as web

COPY --from=spa-builder /app/gui/dist /usr/share/nginx/html
COPY infra/docker/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

# CLI stage 
FROM alpine:3.19 as cli

RUN apk add --no-cache libc-dev wget

COPY --from=zig-builder /app/zig-out/bin/plue /usr/local/bin/plue
COPY --from=zig-builder /app /app
COPY --from=zig-builder /usr/local/zig /usr/local/zig
ENV PATH="/usr/local/zig:${PATH}"

ENTRYPOINT ["plue"]