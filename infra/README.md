# PrimeTime server — deployment

Container distribution for [../server/](../server/) (headless GraphQL
backend, sqlite by default).

```sh
cd infra
docker compose up -d --build
```

The server listens on port 3030; the sqlite database lives in the
`primetime-data` volume. Configuration is `TRAGGO_*` environment variables
(see [../server/.env.sample](../server/.env.sample)).

User administration (the image also ships the admin CLI):

```sh
docker compose exec primetime-server ./admin list-users
docker compose exec primetime-server ./admin create-user -name alice -pass secret
docker compose exec primetime-server ./admin reset-password -name alice -pass newsecret
docker compose exec primetime-server ./admin list-devices
```
