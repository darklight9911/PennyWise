# Deploying pennyWise (one VPS)

Everything runs with Docker Compose on one small server (for example
Hetzner CX22, 2 vCPU / 4 GB). Caddy serves HTTPS and gets its certificate
by itself; nothing else is reachable from the internet.

## 1. Server

```bash
# As root on a fresh Ubuntu or Debian server:
adduser --disabled-password deploy && usermod -aG sudo deploy
# Copy your SSH public key to ~deploy/.ssh/authorized_keys, then in
# /etc/ssh/sshd_config set: PasswordAuthentication no, PermitRootLogin no
systemctl reload ssh

ufw default deny incoming && ufw allow OpenSSH && ufw allow 80,443/tcp && ufw allow 443/udp && ufw enable
apt install -y docker.io docker-compose-v2 rclone unattended-upgrades
usermod -aG docker deploy
```

## 2. Domain

Point an `A` (and `AAAA`) record for your API domain at the server. With
Cloudflare DNS keep the record **DNS only** (grey cloud): the API then
sees real client IPs for its rate limits.

## 3. Configure and start

```bash
git clone https://github.com/darklight9911/PennyWise.git /opt/pennywise
cd /opt/pennywise/deploy
cp env.production.example .env && chmod 600 .env   # fill it in
docker compose -f docker-compose.prod.yml up -d --build
curl https://YOUR_DOMAIN/readyz                    # {"status":"ok",...}
```

Before the first start:

- **Email provider**: the API will not start with `MAILER=log` in
  production. Verification and password-reset emails need a real provider,
  which is not chosen yet.
- **Placeholders** in `site/privacy.html` and `site/delete-account.html`
  (`[CONTACT EMAIL]`, `[YOUR NAME OR COMPANY]`, `[HOSTING PROVIDER]`,
  `[COUNTRY]`, `[DATE]`) must be filled in.

The privacy policy is then at `https://YOUR_DOMAIN/privacy` and the
deletion page at `https://YOUR_DOMAIN/delete-account` (both needed in
Play Console).

## 4. Updating

```bash
cd /opt/pennywise && git pull && cd deploy
docker compose -f docker-compose.prod.yml up -d --build   # migrations run first
```

## 5. Backups

`backup.sh` dumps the database every night to a second, private R2 bucket
and keeps 7 daily, 4 weekly and 6 monthly copies:

```bash
crontab -e
# 15 2 * * * cd /opt/pennywise/deploy && ./backup.sh >> "$HOME/backup.log" 2>&1
```

**Restore once a month to check the backups work**, e.g. into a scratch
database on another machine (the command is at the top of `backup.sh`).
Continuous WAL archiving (WAL-G, lose at most a few minutes) is not set up
yet; with nightly dumps up to one day of changes can be lost (phones keep
unsynced changes and upload them again).

## Notes

- `/metrics` is blocked at Caddy; read it from the server itself
  (`docker compose exec api wget -qO- localhost:8080/metrics` is not
  possible in the distroless image, so add a Prometheus container on the
  compose network if you want graphs).
- Container logs rotate at 5 x 20 MB per service.
- Postgres and Redis data live in Docker volumes `pgdata` and `redisdata`;
  certificates in `caddy_data`. Do not delete these volumes.
