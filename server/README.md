# PrimeTime server

The PrimeTime sync server: a headless, tag-based time-tracking backend
speaking GraphQL. The [PrimeTime mac app](../) is the client — there is no
web UI in this tree.

## Provenance

This tree is a derivative of [traggo/server](https://github.com/traggo/server)
(GPL-3.0), vendored via `git subtree` at commit
`6321119c3c2d55f04e2e4967f6492aabd6067b76` and modified:

- the embedded web UI and its build/release machinery are removed — the
  GraphQL API (timespans, tags, users/auth/devices) is the product here;
- the Go module is renamed to `primetime.tools/server`;
- an admin CLI is added under `cmd/admin` for the user administration the
  web UI used to provide.

The API is traggo-compatible at this stage. See the repository history for
the full record of modifications.

Licensing: traggo-derived code (every file without an SPDX header) is
GPL-3.0 ([LICENSE](LICENSE)); PrimeTime-authored additions carry
`SPDX-License-Identifier: AGPL-3.0-or-later` headers
([LICENSE.AGPL-3.0](LICENSE.AGPL-3.0)) — a combination GPLv3 §13
permits. See [NOTICE](NOTICE) for the full statement.

## Running

```sh
make download-tools   # installs gqlgen + goimports
make generate         # gqlgen: regenerates generated/ (gitignored)
go build -o build/primetime-server .
./build/primetime-server
```

Configuration is via `TRAGGO_*` environment variables or `.env` — see
[.env.sample](.env.sample). Defaults: port 3030, sqlite3 database, and a
default `admin`/`admin` user created when the database is empty.

A GraphQL playground is served on the `/graphql` endpoint for browser
requests; the API is `POST /graphql` with
`Authorization: traggo <device token>`.

For container deployment see [../infra/](../infra/).

## Admin CLI

```sh
go run ./cmd/admin -h
```

Subcommands: `create-user`, `reset-password`, `list-users`, `list-devices`.
The CLI operates directly on the database; point it at the same
`TRAGGO_DATABASE_*` configuration as the server.
