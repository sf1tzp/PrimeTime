#!/usr/bin/env bash
# Server release pipeline (#75): image + Helm chart off the exact vX.Y.Z tag
# on HEAD. Counterpart to scripts/release.sh (#45): same tag, lockstep
# versioning (image tag = chart version = appVersion = ${TAG}; decision on
# #75), but independently runnable — this side needs docker/nerdctl, helm,
# and gh, not a Mac.
#
# The public GHCR push is normally handled by CI — the mirrored tag push
# triggers .github/workflows/release-server.yml, which also builds the arm64
# leg of the manifest. This script is the by-hand fallback for that, and the
# ONLY path to the internal gitea registry (unreachable from GitHub runners).
#
#   preflight  clean tree, HEAD at an exact vX.Y.Z tag, tools present,
#              gh token carries write:packages
#   image      build infra/Dockerfile, version-stamped, tagged for GHCR
#              (public) and the internal gitea registry (#48)
#   chart      helm package with --version/--app-version stamped from the
#              tag — the tag is the source of truth, Chart.yaml's committed
#              version is a placeholder (same rule as bundle-app.sh and
#              Info.plist)
#   publish    push image to both registries, chart to GHCR OCI
#
# Registries:
#   ghcr.io/sf1tzp/primetime-server              public image
#   oci://ghcr.io/sf1tzp/charts/primetime-server public chart
#   gitea.zen.lofi/sfi/primetime-server          internal/staging (#48)
#
# GHCR auth rides the gh CLI token; one-time setup:
#   gh auth refresh -h github.com -s write:packages,read:packages
# The internal push expects a prior `docker login gitea.zen.lofi`. The first
# push of each GHCR package creates it PRIVATE — flip it to public once in
# the package's web-UI settings (there is no API for visibility):
#   https://github.com/users/sf1tzp/packages/container/primetime-server/settings
#   https://github.com/users/sf1tzp/packages/container/charts%2Fprimetime-server/settings
#
# Usage:
#   git tag v1.2.0 && git push origin v1.2.0
#   just release-server                # full pipeline
#   just release-server --no-publish   # build image + chart, push nothing
#   just release-server --no-internal  # skip the gitea push
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHCR_IMAGE="ghcr.io/sf1tzp/primetime-server"
GHCR_CHARTS="oci://ghcr.io/sf1tzp/charts"
INTERNAL_IMAGE="gitea.zen.lofi/sfi/primetime-server"
CHART_DIR="$ROOT/infra/helm/primetime-server"

PUBLISH=1 INTERNAL=1
for arg in "$@"; do
    case "$arg" in
        --no-publish)  PUBLISH=0 ;;
        --no-internal) INTERNAL=0 ;;
        *) echo "unknown flag: $arg (supported: --no-publish --no-internal)" >&2; exit 2 ;;
    esac
done

# --- preflight ---------------------------------------------------------------
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] \
    || { echo "preflight: working tree is dirty — commit or stash first" >&2; exit 1; }

TAG="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null)" \
    || { echo "preflight: HEAD carries no tag — release from an exact vX.Y.Z tag" >&2; exit 1; }
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "preflight: tag '$TAG' is not semver (vX.Y.Z)" >&2; exit 1; }
VERSION="${TAG#v}"

# docker on the Mac, nerdctl on the Linux boxes — same CLI surface for
# build/tag/login/push. Override with DOCKER=… if neither is on PATH.
DOCKER="${DOCKER:-$(command -v docker || command -v nerdctl || true)}"
[[ -n "$DOCKER" ]] \
    || { echo "preflight: neither docker nor nerdctl found (set DOCKER=…)" >&2; exit 1; }
for tool in helm gh; do
    command -v "$tool" >/dev/null \
        || { echo "preflight: '$tool' not found" >&2; exit 1; }
done
if (( PUBLISH )); then
    gh auth status 2>&1 | grep -q "write:packages" \
        || { echo "preflight: gh token lacks write:packages —" \
                  "run: gh auth refresh -h github.com -s write:packages,read:packages" >&2; exit 1; }
fi

echo "==> releasing server $TAG"

# --- image -------------------------------------------------------------------
# Deploy targets are amd64, so pin the platform: without it a build on Apple
# Silicon (just release-all on the Mac) silently produces an arm64 image.
# Cross-building there rides buildkit's QEMU emulation — slower, still correct.
PLATFORM="${PLATFORM:-linux/amd64}"
"$DOCKER" build -f "$ROOT/infra/Dockerfile" \
    --platform "$PLATFORM" \
    --build-arg VERSION="$TAG" \
    --build-arg COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)" \
    --build-arg DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -t "$GHCR_IMAGE:$TAG" -t "$GHCR_IMAGE:latest" -t "$INTERNAL_IMAGE:$TAG" \
    "$ROOT"
echo "==> built $GHCR_IMAGE:$TAG"

# --- chart -------------------------------------------------------------------
mkdir -p "$ROOT/dist"
helm package "$CHART_DIR" --version "$VERSION" --app-version "$VERSION" \
    -d "$ROOT/dist" >/dev/null
CHART_TGZ="$ROOT/dist/primetime-server-$VERSION.tgz"
[[ -f "$CHART_TGZ" ]] || { echo "chart: expected $CHART_TGZ after helm package" >&2; exit 1; }
echo "==> packaged $CHART_TGZ"

# --- publish -----------------------------------------------------------------
if (( !PUBLISH )); then
    echo "==> skipping publish (--no-publish); image is tagged locally, chart is in dist/"
    exit 0
fi

GH_USER="$(gh api user -q .login)"
gh auth token | "$DOCKER" login ghcr.io -u "$GH_USER" --password-stdin >/dev/null
gh auth token | helm registry login ghcr.io -u "$GH_USER" --password-stdin 2>/dev/null

"$DOCKER" push "$GHCR_IMAGE:$TAG"
"$DOCKER" push "$GHCR_IMAGE:latest"
echo "==> pushed $GHCR_IMAGE:$TAG (+latest)"

if (( INTERNAL )); then
    "$DOCKER" push "$INTERNAL_IMAGE:$TAG"
    echo "==> pushed $INTERNAL_IMAGE:$TAG"
fi

helm push "$CHART_TGZ" "$GHCR_CHARTS"
echo "==> pushed $GHCR_CHARTS/primetime-server:$VERSION"
echo "==> if this was the first push, make the GHCR packages public (see header)"
