# Memories

A private, self-hosted photo platform for family and friends. Trip albums are
shared only with invited Google accounts. Built on [Immich](https://immich.app),
with a small custom layer for personal "You" albums and a trip-first gallery.

- **Architecture and decisions:** [docs/architecture.md](docs/architecture.md)
- **Setup and operations:** [docs/runbook.md](docs/runbook.md)
- **Who has access:** [people.yaml](people.yaml)

## Layout

```
infra/
  docker-compose.yml         Caddy + Immich (server, ML, Postgres, Valkey)
  caddy/Caddyfile            TLS and routing
  immich/                    Immich settings as code (rendered by deploy.sh)
  placeholder/               root-domain page until the custom UI ships
  cloud-init.yaml            VM bootstrap
  deploy.sh                  idempotent deploy, runs on the server
  scripts/                   one-time server scripts
  .env.example               every variable, no values
docs/                        architecture, runbook
people.yaml                  people, groups, albums, roles
.github/                     CI, deploy, Renovate
```

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Accounts, domain, storage | manual, see runbook |
| 1 | VM, Caddy, CI/CD | code ready |
| 2 | Immich core, Google login | code ready |
| 3 | Backups and restore drill | next |
| 4 | Invite and share, companion v0 | |
| 5 | Faces and You albums | |
| 6 | Custom web UI | |

## Rules

- Never commit media, `.env` or other plain-text secrets.
- Change access only through `people.yaml` in a pull request.
- Immich is pinned to an exact version. Upgrade only through the Renovate PR.
