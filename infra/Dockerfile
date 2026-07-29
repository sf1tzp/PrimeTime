# PrimeTime server image. Build from the repository root:
#   docker build -f infra/Dockerfile -t primetime-server .
# or via infra/docker-compose.yml.

FROM golang:1.24-alpine AS builder
RUN apk add --no-cache build-base
WORKDIR /src

COPY server/go.mod server/go.sum ./
RUN go mod download
RUN go install github.com/99designs/gqlgen@v0.17.85

COPY server/ .
RUN gqlgen
RUN CGO_ENABLED=1 go build -a \
        -ldflags '-s -w -linkmode external -extldflags "-static" -X main.BuildMode=prod' \
        -tags 'netgo osusergo sqlite_omit_load_extension' \
        -o /out/primetime-server . \
    && CGO_ENABLED=1 go build -a \
        -ldflags '-s -w -linkmode external -extldflags "-static"' \
        -tags 'netgo osusergo sqlite_omit_load_extension' \
        -o /out/admin ./cmd/admin

FROM scratch
WORKDIR /opt/primetime
COPY --from=builder /out/primetime-server /opt/primetime/primetime-server
COPY --from=builder /out/admin /opt/primetime/admin
EXPOSE 3030
ENTRYPOINT ["./primetime-server"]
