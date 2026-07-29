TAGS=netgo osusergo sqlite_omit_load_extension
VERSION=$(shell git describe --tags --abbrev=0 | cut -c 2-)
COMMIT=$(shell git rev-parse --verify HEAD)
DATE=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
LD_FLAGS=-s -w -linkmode external -extldflags "-static" -X main.BuildDate=$(DATE) -X main.BuildMode=prod -X main.BuildCommit=$(COMMIT) -X main.BuildVersion=$(VERSION)
BUILD_DIR=./build
PWD=$(shell pwd)

download-tools:
	go install golang.org/x/tools/cmd/goimports@v0.1.10
	go install github.com/99designs/gqlgen@v0.17.85

generate:
	gqlgen

lint:
	go vet ./...
	goimports -l $(shell find . -type f -name '*.go' -not -path "./vendor/*")

format:
	goimports -w $(shell find . -type f -name '*.go' -not -path "./vendor/*")

test:
	go test --race -coverprofile=coverage.txt -covermode=atomic ./...

install:
	go mod download

build-bin-local:
	CGO_ENABLED=1 go build -a -ldflags '${LD_FLAGS}' -tags '${TAGS}' -o ${BUILD_DIR}/primetime-server

.PHONY: download-tools generate lint format test install build-bin-local
