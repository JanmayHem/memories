# Runbook

This runbook is for the admin and the second admin. Do the steps in sequence.
Each step tells you what to do and how to make sure that it is correct.

Placeholders:
- `<domain>`: the root domain, for example `memories.example.com`.
- `<photos-host>`: the Immich subdomain, for example `photos.memories.example.com`.
- `<vm-ip>`: the public IP address of the VM.

---

## Phase 0 – Accounts (manual)

1. Create the Oracle Cloud account. Select the home region carefully. You cannot
   change it later. Mumbai or Hyderabad gives low latency, if Ampere A1 capacity
   is available.
2. Buy the domain.
3. Create the Hetzner Storage Box (BX11). Phase 3 uses it.
4. Buy the external HDD. Phase 3 uses it.
5. Make an SSH key for yourself if you do not have one:
   `ssh-keygen -t ed25519 -C janmay`.

---

## Phase 1 – Foundation

### 1.1 Create the VM

1. In the OCI console, create an instance:
   - Image: Canonical Ubuntu 24.04 (aarch64).
   - Shape: VM.Standard.A1.Flex, 2 OCPU, 12 GB memory.
   - Boot volume: 50 GB.
   - Public IPv4 address: yes. Reserve it, so that it does not change.
   - Advanced options > Management > cloud-init: paste `infra/cloud-init.yaml`.
     Before you paste, replace the SSH key placeholder with your public key.
2. If the console shows "Out of capacity", try again later or in a different
   availability domain.
3. Open ports in the subnet security list (Networking > VCN > Security Lists >
   Ingress rules). Add, source `0.0.0.0/0`:
   - TCP 80
   - TCP 443
   - UDP 443
4. Make sure that it is correct:
   ```bash
   ssh memories@<vm-ip> 'cloud-init status --wait && docker compose version'
   ```
   The output must show `status: done` and a Compose version.

### 1.2 Attach and mount the data volume

1. In the OCI console, create a block volume of about 150 GB in the same
   availability domain. The free tier allows 200 GB in total, boot volume included.
2. Attach it to the instance: type **Paravirtualized**, and select **Use consistent
   device paths** with device `/dev/oracleoci/oraclevdb`.
3. Copy the script to the VM and run it. Use `--format` only the first time:
   ```bash
   scp infra/scripts/mount-data-volume.sh memories@<vm-ip>:
   ssh memories@<vm-ip> 'sudo ./mount-data-volume.sh --format'
   ```
4. Make sure that it is correct: the output shows about 150G on `/srv/photos`.
   Reboot the VM one time and make sure that `/srv/photos` is mounted again.

### 1.3 DNS

1. Make two A records that point to `<vm-ip>`: `<domain>` and `<photos-host>`.
2. If you use Cloudflare, set both records to **DNS only** (grey cloud).
   The Cloudflare proxy limits uploads to 100 MB, which stops video uploads.
3. Make sure that it is correct: `dig +short <photos-host>` shows `<vm-ip>`.

### 1.4 Google OAuth client

1. In Google Cloud console, create a project named `memories`.
2. Google Auth Platform > Branding: app name `Memories`, your support email.
3. Audience: **External**. Then select **Publish app**. With only the
   `openid email profile` scopes, Google does not need a verification review.
   (In "Testing" mode only listed test users can sign in.)
4. Clients > Create client > **Web application**. Authorized redirect URIs:
   - `https://<photos-host>/auth/login`
   - `https://<photos-host>/user-settings`
   - `https://<photos-host>/api/oauth/mobile-redirect`
5. Keep the client ID and client secret for step 1.5.

### 1.5 First deploy (by hand)

1. Copy `infra/` to the VM:
   ```bash
   rsync -az --exclude .env --exclude immich/immich-config.yaml --exclude data/ infra/ memories@<vm-ip>:/opt/memories/infra/
   ```
2. On the VM, make the `.env` file:
   ```bash
   cd /opt/memories/infra && cp .env.example .env && chmod 600 .env && nano .env
   ```
   Fill in every value. Use `openssl rand -hex 24` for `DB_PASSWORD`.
   Keep `PASSWORD_LOGIN_ENABLED=false`.
   DNS (step 1.3) must resolve before you deploy. Immich stops with
   `ENOTFOUND <photos-host>` if it cannot resolve its own domain.
3. Deploy:
   ```bash
   ./deploy.sh
   ```
   The first start pulls about 2 GB of images. All services must show `healthy`.
4. Make sure that it is correct:
   - `https://<domain>` shows the Memories placeholder page with a valid certificate.
   - `https://<photos-host>` shows the Immich welcome page.

### 1.6 Create the admin account

1. Open `https://<photos-host>`. Immich asks you to create the admin account.
   (Admin sign-up works while password login is off.)
2. Use the **same email as your Google account**. Use a long random password.
   Keep it in the password manager. This is the **break-glass password**.
3. Select **Sign in with Google** and use the same Google account.
   You must arrive in your own library. This proves that Google login links to
   the existing account by email.
4. Make sure that it is correct: `https://<photos-host>/auth/login?autoLaunch=0`
   shows no password form, only the Google button.
5. Do the break-glass procedure (below) one time, so that you know it works.
6. Protect the Google account behind the admin: use a hardware key or an
   authenticator app.

### 1.7 Turn on deploys from GitHub

1. On your laptop, make a deploy key with no passphrase:
   ```bash
   ssh-keygen -t ed25519 -N '' -C github-deploy -f ~/.ssh/memories_deploy
   ```
2. Add `~/.ssh/memories_deploy.pub` to `/home/memories/.ssh/authorized_keys` on the VM.
3. In GitHub > Settings > Environments, create the environment `production`.
   Add these environment secrets:
   | Secret | Value |
   |---|---|
   | `DEPLOY_HOST` | `<vm-ip>` |
   | `DEPLOY_USER` | `memories` |
   | `DEPLOY_SSH_KEY` | contents of `~/.ssh/memories_deploy` |
   | `DEPLOY_KNOWN_HOSTS` | output of `ssh-keyscan -t ed25519 <vm-ip>` |
4. In Settings > Secrets and variables > Actions > Variables, add
   `DEPLOY_ENABLED` = `true`.
5. Make sure that it is correct: Actions > Deploy > Run workflow. The run must
   pass, and the last log lines must show `deploy: done`.

**Phase 1 gate:** the placeholder page has HTTPS, and a merge to `main` deploys
without manual steps.

---

## Phase 2 – Immich core

1. Install the Renovate GitHub app on the `memories` repo only
   (https://github.com/apps/renovate). Renovate reads `.github/renovate.json`.
2. Upload one real album from your laptop (Immich web, or the Immich mobile
   app with server URL `https://<photos-host>`).
3. In Administration > Job Queues, wait until all queues are empty. Face
   detection on 2 ARM cores takes hours for ~1,500 photos. This is normal.
4. Make sure that it is correct:
   - Explore shows face clusters.
   - Smart search finds photos with a phrase such as "beach at sunset".
   - The Immich mobile app signs in with Google.
   - `df -h /srv/photos` shows the expected use.

**Phase 2 gate:** one real album is indexed, search works, and mobile login works.
Do **not** invite other people before the Phase 3 restore drill passes.

---

## Operations

### Add a person (until the companion exists in Phase 4)

1. Add the person to `people.yaml` in a pull request, and merge it.
2. In Immich, Administration > Users > Create user. Use the **exact** Google
   email. Set a random password (nobody uses it). For people who never upload,
   set a quota of 1 GiB.
3. Share the albums that `people.yaml` gives them.

### Break-glass login (Google login does not work)

1. On the VM, set `PASSWORD_LOGIN_ENABLED=true` in `.env`, then run `./deploy.sh`.
2. Open `https://<photos-host>/auth/login?autoLaunch=0` and sign in with the
   admin email and the break-glass password.
3. When the problem is fixed, set `PASSWORD_LOGIN_ENABLED=false` and run
   `./deploy.sh` again.

### Change an Immich setting

Immich settings are in `infra/immich/immich-config.template.yaml`. The admin UI
cannot change them. Change the file in a pull request. The deploy restarts
`immich-server` when the rendered config changes.

### Update Immich (monthly)

1. Renovate opens a PR named "Update Immich". Read the release notes for
   breaking changes.
2. Compare `infra/docker-compose.yml` with Immich's `docker/docker-compose.yml`
   at the new tag. Copy changes to Postgres or Valkey (image digests) by hand.
3. Make a DB dump: Administration > Job Queues > Create job > Create Database Dump.
4. Merge. The deploy workflow updates the server.

### Keep an encrypted copy of `.env` (sops + age)

1. Install `sops` and `age` on your laptop. Make a key one time:
   `age-keygen -o ~/.config/sops/age/keys.txt`.
2. Put the public key (`age1...`) in `.sops.yaml`.
3. Copy the server `.env` to your laptop and encrypt it:
   ```bash
   sops --encrypt --input-type dotenv --output-type dotenv server.env > secrets/prod.sops.env
   ```
   Delete the plain copy. Commit `secrets/prod.sops.env`.
4. Keep the private age key offline (password manager plus a printed copy).
   Give a copy to the second admin.

### Useful commands (on the VM, in `/opt/memories/infra`)

| Task | Command |
|---|---|
| Status | `docker compose ps` |
| Logs | `docker compose logs -f --tail 100 immich-server` |
| Restart all | `docker compose restart` |
| Validate only | `./deploy.sh --check` |
| Immich admin CLI | `docker compose exec immich-server immich-admin list-users` |
| Disk use | `df -h /srv/photos /` |
