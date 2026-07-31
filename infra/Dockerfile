# PrimeTime server image. Build from the repository root:
#   docker build -f infra/Dockerfile -t primetime-server .
# or via infra/docker-compose.yml.
#
# Version stamping: pass --build-arg VERSION=$(git describe --tags) (and
# COMMIT/DATE) so the binary reports the release version — the Makefile does
# the same for local builds. Left at the develop defaults when unset.

# Base pinned to an explicit Alpine minor: an unpinned `1.24-alpine` rolls
# forward (it reached Alpine 3.23 / musl 1.2.5), which is how this build first
# broke. Bump deliberately.
FROM golang:1.24-alpine3.22 AS builder
RUN apk add --no-cache build-base
WORKDIR /src

ARG VERSION=develop
ARG COMMIT=-
ARG DATE=unknown

COPY server/go.mod server/go.sum ./
RUN go mod download
RUN go install github.com/99designs/gqlgen@v0.17.85

COPY server/ .
RUN gqlgen
RUN CGO_ENABLED=1 go build -a \
        -ldflags "-s -w -linkmode external -extldflags '-static' -X main.BuildMode=prod -X main.BuildVersion=${VERSION} -X main.BuildCommit=${COMMIT} -X main.BuildDate=${DATE}" \
        -tags 'netgo osusergo sqlite_omit_load_extension' \
        -o /out/primetime-server . \
    && CGO_ENABLED=1 go build -a \
        -ldflags "-s -w -linkmode external -extldflags '-static'" \
        -tags 'netgo osusergo sqlite_omit_load_extension' \
        -o /out/admin ./cmd/admin

FROM scratch
# The source label links the GHCR package to the public mirror repo (#75).
LABEL org.opencontainers.image.source="https://github.com/sf1tzp/PrimeTime" \
      org.opencontainers.image.description="PrimeTime sync server — headless GraphQL time-tracking backend (SQLite)" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later AND GPL-3.0-only"
WORKDIR /opt/primetime
COPY --from=builder /out/primetime-server /opt/primetime/primetime-server
COPY --from=builder /out/admin /opt/primetime/admin
# Licensing (per server/NOTICE — a GPL-3.0 §13 combination with AGPL-3.0):
# ship the notices in the image so the source-availability obligation travels
# with the binary.
COPY --from=builder /src/LICENSE /src/LICENSE.AGPL-3.0 /src/NOTICE /opt/primetime/
EXPOSE 3030
ENTRYPOINT ["./primetime-server"]
