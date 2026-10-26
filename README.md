# clrk-cloud

Builds and publishes [clrk](https://github.com/sumihiran/clrk) container images and binaries.
Upstream, clrk is built by Bazel in apoxy-dev's private `apoxy-cloud` repo. This repo does the
same job with a plain Dockerfile and GitHub Actions.

## Artifacts

Each build is tagged with the first 8 hex characters of the clrk commit SHA, the same tag
clrk's `drivers.ImageTag()` derives.

| Artifact | Where |
|---|---|
| controller-manager image (amd64, arm64) | `ghcr.io/sumihiran/clrk-controller-manager:<tag>` |
| worker image (amd64, arm64) | `ghcr.io/sumihiran/clrk-worker:<tag>` |
| `clrk` CLI, controller-manager, worker binaries | [Releases](https://github.com/sumihiran/clrk-cloud/releases), as `clrk-<tag>` |

`:latest` points at the most recent build.

The controller-manager image includes the console bundle, `envoy-gateway` (v1.4.0) and
`clickhouse`, at the paths its flags default to. The Envoy data-plane image (`--envoy-image`)
is not built here; it still defaults to apoxy-dev's public image.

## Running a build

From the Actions tab, run **build** with a repository and ref (defaults: `sumihiran/clrk`,
`main`). Or from the CLI:

```bash
gh workflow run build.yml -R sumihiran/clrk-cloud -f ref=main
```

The workflow also accepts the `clrk-build` `repository_dispatch` event that clrk's `ci.yml`
sends, with `{"sha": "...", "repository": "owner/name"}` as the payload.

## Building locally

```bash
git clone https://github.com/sumihiran/clrk.git clrk
docker buildx build --target worker -t clrk-worker:dev --load .
docker buildx build --target controller-manager -t clrk-controller-manager:dev --load .
```

`scripts/prepare-source.sh` does the two things the Bazel build handles implicitly: it
generates the `*.pb.go` files and aligns the `gvisor.dev/gvisor` replace with the fork
`github.com/apoxy-dev/apoxy` is built against.

## License

clrk is AGPL-3.0. The images and binaries published here are built from its public source. The
only build-time changes are the generated protobuf code and the `go.mod` replace described above.
