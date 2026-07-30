# primetime-server Helm chart

Deploys the [PrimeTime server](../../../server/) — a headless GraphQL
time-tracking backend — to Kubernetes. SQLite on a PersistentVolume; a single
replica (SQLite is a single writer, so the Deployment uses the `Recreate`
strategy and never runs two pods against one DB file).

## Install

```sh
helm install primetime ./infra/helm/primetime-server \
  --namespace primetime --create-namespace \
  --set admin.password=<something-better-than-admin>
```

The default image is `gitea.zen.lofi/sfi/primetime-server:v<appVersion>`. For a
private registry, create a pull secret and reference it:

```sh
kubectl -n primetime create secret docker-registry gitea-registry \
  --docker-server=gitea.zen.lofi --docker-username=<user> --docker-password=<token>

helm install primetime ./infra/helm/primetime-server -n primetime \
  --set imagePullSecrets[0].name=gitea-registry
```

## Key values

| Key | Default | Notes |
|---|---|---|
| `image.repository` | `gitea.zen.lofi/sfi/primetime-server` | |
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
| `ingress.host` | `primetime.local` | |
| `config.logLevel` | `info` | |

Only `sqlite3` is a supported `TRAGGO_DATABASE_DIALECT`, so there is no
external-database option — the chart always provisions SQLite persistence.

## Persistence & uninstall

The PVC carries `helm.sh/resource-policy: keep`, so `helm uninstall` leaves the
database behind. Delete it explicitly to start clean:

```sh
kubectl -n primetime delete pvc primetime-primetime-server-data
```

## User administration

```sh
kubectl -n primetime exec deploy/primetime-primetime-server -- ./admin list-users
kubectl -n primetime exec deploy/primetime-primetime-server -- \
  ./admin create-user -name alice -pass secret
```

## Licensing

The chart ships `LICENSE` (GPL-3.0), `LICENSE.AGPL-3.0`, and `NOTICE`: the
server is a GPL-3.0 §13 combination with PrimeTime's AGPL-3.0 additions. See
[`NOTICE`](NOTICE).
