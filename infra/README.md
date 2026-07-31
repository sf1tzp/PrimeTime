# PrimeTime server — deployment

Container distribution for [../server/](../server/) (headless GraphQL
backend, SQLite by default). Two supported paths: **Docker Compose** for a
single host and **Helm** ([helm/](helm/)) for Kubernetes.

## Published images & chart (#75)

Every `vX.Y.Z` release publishes the server image (multi-arch, amd64 + arm64)
and Helm chart publicly to GHCR — automated by
[release-server.yml](../.github/workflows/release-server.yml), which the tag's
arrival on the public mirror triggers; `just release-server` is the by-hand
equivalent. Image tag, chart version, and appVersion all match the release
tag:

```sh
docker pull ghcr.io/sf1tzp/primetime-server:v0.2.0   # or :latest
helm install primetime oci://ghcr.io/sf1tzp/charts/primetime-server
```

The internal gitea registry (`gitea.zen.lofi/sfi/primetime-server`; #48)
receives the same image for staging; it needs a `docker login`.

## Docker Compose

```sh
cd infra
docker compose up -d --build
```

The server listens on port 3030. `docker compose up --build` builds the image
from source, so no Go toolchain is needed on the host. To run a published
image instead of building, set `image:` on the service (e.g.
`ghcr.io/sf1tzp/primetime-server:v0.2.0`, or the internal
`gitea.zen.lofi/sfi/primetime-server:v0.2.0`).

To stamp the release version into a compose-built binary, export the build
args (a plain build reports `develop`):

```sh
PRIMETIME_VERSION=$(git -C .. describe --tags) \
PRIMETIME_COMMIT=$(git -C .. rev-parse --short HEAD) \
PRIMETIME_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  docker compose up -d --build
```

### Configuration

All configuration is `TRAGGO_*` environment variables
(see [../server/.env.sample](../server/.env.sample)). **None are required** —
every setting has a default — but the defaults create an `admin`/`admin` user,
so change the password (or set `TRAGGO_DEFAULT_USER_PASS`) before exposing the
server. The compose file sets:

| Variable | Compose value | Default | Notes |
|---|---|---|---|
| `TRAGGO_DEFAULT_USER_NAME` | `admin` | `admin` | Only used to seed the first user on an empty DB. |
| `TRAGGO_DEFAULT_USER_PASS` | `admin` | `admin` | Change this. Seeds the first user only. |
| `TRAGGO_DATABASE_DIALECT` | `sqlite3` | `sqlite3` | **SQLite is the only supported dialect.** |
| `TRAGGO_DATABASE_CONNECTION` | `data/primetime.db` | `data/traggo.db` | Path is relative to the workdir `/opt/primetime`. |
| `TRAGGO_LOG_LEVEL` | `info` | `info` | `debug`, `info`, `warn`, `error`, `fatal`, `panic`. |
| `TRAGGO_PORT` | (unset) | `3030` | The published container port. |
| `TRAGGO_PASS_STRENGTH` | (unset) | `10` | bcrypt cost. |

### Volume layout

The SQLite database lives in the named volume `primetime-data`, mounted at
`/opt/primetime/data`. With `TRAGGO_DATABASE_CONNECTION=data/primetime.db`
(relative to the `/opt/primetime` workdir) the database file is
`/opt/primetime/data/primetime.db`. Back up by copying that file (or the whole
volume) while the server is stopped. The default admin user and the default
label-set collection are seeded on first start against an empty database.

## User administration

The image ships the admin CLI alongside the server:

```sh
docker compose exec primetime-server ./admin list-users
docker compose exec primetime-server ./admin create-user -name alice -pass secret
docker compose exec primetime-server ./admin reset-password -name alice -pass newsecret
docker compose exec primetime-server ./admin list-devices
```

(On Kubernetes: `kubectl exec deploy/<release>-primetime-server -- ./admin ...`.)

## Licensing

The published image and the Helm chart carry the GPL-3.0 (`LICENSE`),
AGPL-3.0 (`LICENSE.AGPL-3.0`), and `NOTICE` files from
[../server/](../server/) — the server is a GPL-3.0 §13 combination with
PrimeTime's AGPL-3.0 additions (see [../server/NOTICE](../server/NOTICE)). In
the image they are under `/opt/primetime/`.
