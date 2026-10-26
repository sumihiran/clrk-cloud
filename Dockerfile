# syntax=docker/dockerfile:1.7
#
# Builds the clrk controller-manager and worker images from a clrk checkout
# placed at ./clrk in the build context. Targets: controller-manager, worker.

ARG GO_VERSION=1.25
ARG NODE_VERSION=20
# Keep in sync with github.com/envoyproxy/gateway in clrk's go.mod.
ARG ENVOY_GATEWAY_VERSION=v1.4.0
ARG CLICKHOUSE_VERSION=25.8

FROM envoyproxy/gateway:${ENVOY_GATEWAY_VERSION} AS envoy-gateway
FROM clickhouse/clickhouse-server:${CLICKHOUSE_VERSION} AS clickhouse

# The controller-manager embeds the console SPA from internal/console/dist.
FROM node:${NODE_VERSION}-bookworm AS console
RUN corepack enable && corepack prepare pnpm@10.11.0 --activate
WORKDIR /src/console
COPY clrk/console/ ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile && pnpm -C apps/clrk-console build

FROM golang:${GO_VERSION}-bookworm AS source
RUN apt-get update \
    && apt-get install -y --no-install-recommends protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY clrk/ ./
COPY scripts/prepare-source.sh /usr/local/bin/prepare-source.sh
RUN --mount=type=cache,target=/go/pkg/mod \
    prepare-source.sh /src

# cgo is required: the embedded apiserver's kine storage uses go-sqlite3.
FROM source AS build-controller-manager
ARG VERSION=""
COPY --from=console /src/console/apps/clrk-console/dist/ /src/internal/console/dist/
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=1 GOFLAGS=-mod=mod go build -trimpath \
      -ldflags="-s -w -X github.com/apoxy-dev/clrk/internal/version.version=${VERSION}" \
      -o /out/controller-manager ./cmd/controller-manager

# The worker links libcontainer's nsenter, so it needs cgo (glibc).
FROM source AS build-worker
ARG VERSION=""
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=1 GOFLAGS=-mod=mod go build -trimpath \
      -ldflags="-s -w -X github.com/apoxy-dev/clrk/internal/version.version=${VERSION}" \
      -o /out/worker ./cmd/worker

FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

FROM runtime AS worker
COPY --from=build-worker /out/worker /usr/local/bin/worker
ENTRYPOINT ["/usr/local/bin/worker"]

# envoy-gateway and clickhouse are supervised as child processes at their
# default flag paths (--envoy-gateway-binary, --embedded-clickhouse-binary).
FROM runtime AS controller-manager
# envoy-go and go-control-plane both register Envoy's TLS protos. clrk's
# installer sets this on the Deployment; baking it in covers other launchers.
ENV GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore
COPY --from=envoy-gateway /usr/local/bin/envoy-gateway /usr/local/bin/envoy-gateway
COPY --from=clickhouse /usr/bin/clickhouse /usr/local/bin/clickhouse
COPY --from=build-controller-manager /out/controller-manager /usr/local/bin/controller-manager
ENTRYPOINT ["/usr/local/bin/controller-manager"]
