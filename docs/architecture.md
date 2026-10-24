# Architecture

Memories is a private photo platform for 15–20 family members and friends.
Immich is the center. A small custom layer adds personal "You" albums and a
trip-first gallery.

## Design rules

1. **Immich makes all access decisions.** Immich keeps the photos, does the ML,
   does the login and enforces permissions. The web UI calls Immich as the user
   who is signed in. The companion uses an admin API key and changes users,
   albums and memberships only through the Immich API.
2. **The repo is the record of truth for people.** `people.yaml` holds people,
   groups, albums, roles, opt-ins and face links. An access change is a pull
   request. The companion makes Immich agree with the file.
3. **Custom code is thin and you can replace it.** If the web UI or the
   companion fails, Immich and its mobile app continue to work.
4. **Every original photo is in three places**: the Oracle VM, the Hetzner
   Storage Box and a drive at home.
5. **The repo never holds media or plain-text secrets.**

## Components

```
                Browser / Immich mobile app
                           │ HTTPS
┌──────────────────────────▼───────────────────────────── Oracle ARM VM ──┐
│  Caddy (TLS) ── <DOMAIN> ─────────► web (SvelteKit, Phase 6)            │
│              └─ <PHOTOS_HOST> ──┐        │ calls API as the user        │
│                                 ▼        ▼                              │
│                        immich-server ◄── companion (Phase 4)            │
│                         │    │    │       admin API key                 │
│                 Postgres  Valkey  immich-machine-learning               │
│                         │                                               │
│               /srv/photos (block volume): library/, postgres/           │
└─────────────────────────┼───────────────────────────────────────────────┘
                          ▼ restic, nightly 03:00 (Phase 3)
                 Hetzner Storage Box ──► home HDD (weekly restic copy)
```

| Path | What | Phase |
|---|---|---|
| `infra/docker-compose.yml` | The whole stack | 1–2 |
| `infra/caddy/Caddyfile` | TLS and routing | 1 |
| `infra/immich/immich-config.template.yaml` | Immich settings as code | 2 |
| `infra/cloud-init.yaml` | VM bootstrap | 1 |
| `infra/deploy.sh` | Idempotent deploy on the server | 1 |
| `backup/` | restic backup and restore | 3 |
| `companion/` | people.yaml sync, You albums, link audit | 4–5 |
| `web/` | Custom gallery | 6 |

## Decisions

### D1. Immich is on a subdomain, the custom UI is on the root domain
Immich cannot run on a sub-path. `photos.<domain>` serves Immich and the mobile
app. `<domain>` serves the custom UI (a placeholder page until Phase 6).

### D2. Immich settings live in the repo
Immich loads `immich-config.yaml` (rendered from the template by `deploy.sh`).
When a config file is present, the admin UI cannot change settings. This is
intentional: login and access settings change only through a pull request.
Secrets come from `.env` on the server, never from the repo.

### D3. Login is Google only, and auto-registration is off
`oauth.autoRegister: false`. An account must exist for the exact email before
that person can sign in. On the first Google sign-in, Immich links the login to
the existing account by email. Password login is off. The first admin account
keeps a password for break-glass use only (see the runbook).

### D4. Only the admin uploads at first
Immich groups faces per uploading account. One uploader gives one face library,
so each person is one face cluster. Contributor uploads come later; then the
companion merges clusters across uploaders.

### D5. Share by face is off on all albums
The "within reach" rule is the default: a You album only contains photos from
albums that the person can already see. An album owner can opt in later.

### D6. The companion is TypeScript (Phase 4)
The web UI and the companion share `@immich/sdk`, one set of types and one set
of contract tests against the pinned Immich version.

### D7. The companion keeps a small SQLite state file (Phase 4–5)
The review queue, share-by-face approvals and "don't share" flags have no place
in Immich or in `people.yaml`. They are metadata only, never photos. The nightly
backup includes this file.

### D8. You albums belong to the admin (Phase 5)
Each You album is owned by the admin account and shared with its person as a
viewer. The companion is the only writer.

### D9. Deploys copy `infra/` with rsync
The server does not need access to GitHub. GitHub Actions copies `infra/` to a
side folder, checks it against the real `.env`, then copies it to the live
folder and runs `deploy.sh`. Folders, not single files, are bind-mounted, so an
atomic file replace is visible to the running containers.

### D10. Versions are pinned exactly
Immich server and ML use the same exact tag. Postgres and Valkey use the digests
from Immich's own compose file and change only with Immich. Renovate opens one
PR per Immich release, and a human merges it after reading the release notes.
