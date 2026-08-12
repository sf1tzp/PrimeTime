# moment-tally-server Helm chart

Deploys the [Moment Tally server](../../../server/) — a headless GraphQL
time-tracking backend — to Kubernetes. SQLite on a PersistentVolume; a single
replica (SQLite is a single writer, so the Deployment uses the `Recreate`
strategy and never runs two pods against one DB file).

## Install

From the public registry (chart and image both on GHCR; #75):

```sh
helm install momenttally oci://ghcr.io/sf1tzp/charts/moment-tally-server \
  --namespace momenttally --create-namespace \
  --set admin.password=<something-better-than-admin>
```

Pin a release with `--version X.Y.Z`; chart version, `appVersion`, and image
tag all track the repo's `vX.Y.Z` release tags in lockstep. Or install from a
checkout (uses the placeholder version in Chart.yaml):

```sh
helm install momenttally ./infra/helm/moment-tally-server \
  --namespace momenttally --create-namespace \
  --set admin.password=<something-better-than-admin>
```

The default image is `ghcr.io/sf1tzp/moment-tally-server:v<appVersion>` — public,
no pull secret needed. For internal/staging deploys off the gitea registry
(#48), override the repository and add a pull secret:

```sh
kubectl -n momenttally create secret docker-registry gitea-registry \
  --docker-server=gitea.zen.lofi --docker-username=<user> --docker-password=<token>

helm install momenttally ./infra/helm/moment-tally-server -n momenttally \
  --set image.repository=gitea.zen.lofi/sfi/moment-tally-server \
  --set imagePullSecrets[0].name=gitea-registry
```

## Key values

| Key | Default | Notes |
|---|---|---|
| `image.repository` | `ghcr.io/sf1tzp/moment-tally-server` | Public; set `gitea.zen.lofi/sfi/moment-tally-server` for staging. |
| `image.tag` | `""` → `v<appVersion>` | Overrides the appVersion-derived tag. |
| `admin.username` / `admin.password` | `admin` / `admin` | Seeds the first user on an empty DB. **Change the password.** |
| `admin.existingSecret` | `""` | Source `username`/`password` keys from your own Secret. |
| `persistence.enabled` | `true` | Set false for an ephemeral `emptyDir` (testing only). |
| `persistence.size` | `1Gi` | |
| `persistence.storageClass` | `""` | Empty = cluster default (local-path on k3s). |
| `persistence.existingClaim` | `""` | Reuse an existing PVC. |
| `service.port` | `3030` | |
| `ingress.enabled` | `false` | |
| `ingress.className` | `traefik` | |
| `ingress.host` | `momenttally.local` | |
| `config.logLevel` | `info` | |

Only `sqlite3` is a supported `MOMENTTALLY_DATABASE_DIALECT`, so there is no
external-database option — the chart always provisions SQLite persistence.

## Persistence & uninstall

The PVC carries `helm.sh/resource-policy: keep`, so `helm uninstall` leaves the
database behind. Delete it explicitly to start clean:

```sh
kubectl -n momenttally delete pvc momenttally-moment-tally-server-data
```

## User administration

```sh
kubectl -n momenttally exec deploy/momenttally-moment-tally-server -- ./admin list-users
kubectl -n momenttally exec deploy/momenttally-moment-tally-server -- \
  ./admin create-user -name alice -pass secret
```

## Licensing

The chart ships `LICENSE` (GPL-3.0), `LICENSE.AGPL-3.0`, and `NOTICE`: the
server is a GPL-3.0 §13 combination with Moment Tally's AGPL-3.0 additions. See
[`NOTICE`](NOTICE).
