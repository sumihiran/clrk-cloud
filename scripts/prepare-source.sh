#!/usr/bin/env bash
# Prepares a clrk checkout so cmd/controller-manager and cmd/worker build
# with plain `go build`. Upstream builds these with Bazel in apoxy-cloud,
# which does two things implicitly that a Go-only build has to do itself:
#
#   1. Generate *.pb.go from the .proto sources (never checked in).
#   2. Use the gvisor fork that github.com/apoxy-dev/apoxy is built against.
#      clrk's go.mod can lag behind the apoxy pin, and the worker then fails
#      to compile against the older fork.
#
# Usage: prepare-source.sh <clrk-source-dir>
set -euo pipefail

cd "${1:?usage: prepare-source.sh <clrk-source-dir>}"

tools="$(mktemp -d)"
trap 'rm -rf "$tools"' EXIT

echo "Generating protobuf Go code"
protobuf_version="$(go list -m -f '{{.Version}}' google.golang.org/protobuf)"
GOBIN="$tools" go install "google.golang.org/protobuf/cmd/protoc-gen-go@${protobuf_version}"
GOBIN="$tools" go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.5.1
find . -name '*.proto' -not -path './console/*' -not -path '*/node_modules/*' -print0 |
  xargs -0 -r protoc -I . \
    --plugin=protoc-gen-go="$tools/protoc-gen-go" \
    --plugin=protoc-gen-go-grpc="$tools/protoc-gen-go-grpc" \
    --go_out=. --go_opt=module=github.com/apoxy-dev/clrk \
    --go-grpc_out=. --go-grpc_opt=module=github.com/apoxy-dev/clrk

echo "Aligning gvisor replace with github.com/apoxy-dev/apoxy"
go mod download github.com/apoxy-dev/apoxy
apoxy_gomod="$(go list -m -f '{{.GoMod}}' github.com/apoxy-dev/apoxy)"
gvisor="$(awk '$1 == "replace" && $2 == "gvisor.dev/gvisor" { print $4 "@" $5 }' "$apoxy_gomod")"
if [[ -n "$gvisor" ]]; then
  echo "Using gvisor.dev/gvisor => $gvisor"
  go mod edit -replace "gvisor.dev/gvisor=$gvisor"
fi

# The gvisor fork pulls in packages whose checksums aren't in clrk's go.sum.
go mod download all >/dev/null 2>&1 || true
GOFLAGS=-mod=mod go list ./cmd/... >/dev/null
