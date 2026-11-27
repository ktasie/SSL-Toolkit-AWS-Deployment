# 03 — Node.js Application Deployment with systemd

[← Linux administration](02-linux-administration.md) · [Next: NGINX and HTTPS →](04-nginx-https.md)

## Objective

Run SSL Toolkit as a dedicated, supervised service on Ubuntu, using the exact application code from the companion [SSL Toolkit repository](https://github.com/ktasie/ssl-toolkit). Keep the process private on loopback; NGINX becomes the public entry point in Phase 4.

## Application context

SSL Toolkit is a Node.js/Express browser interface over OpenSSL commands. It supports certificate signing request generation, certificate format conversion and key/certificate validation. Its main entry point is `server.js`; application routes and controllers remain in the **application repository**, not this infrastructure repository.

### Verify the deployed application commit

```bash
cd /opt/ssl-toolkit
node --version
npm --version
openssl version
# If a git working tree exists, capture the commit:
git rev-parse HEAD
```

If `.git` was excluded when the application was copied into `/opt`, record the source commit from the staging clone (`~/ssl-toolkit-source`) or the deployment notes. A reproducible deployment must identify **the exact application revision**.

## Runtime and installation

The initial design uses Node.js 24 LTS and system OpenSSL.

```bash
node -v
npm -v
openssl version
```

For a clean clone after the dependency correction:

```bash
git clone https://github.com/ktasie/ssl-toolkit.git ~/ssl-toolkit-source
cd ~/ssl-toolkit-source
git rev-parse HEAD
npm ci --omit=dev
npm audit --omit=dev
```

`npm ci` installs from the tracked lockfile without rewriting its resolution. `--omit=dev` excludes development-only dependencies. Inspect audit output; do not use `npm audit fix --force` as an unreviewed workaround.

For consistency the project plan deploys code under `/opt/ssl-toolkit`:

```bash
sudo rsync -a --exclude='.git/' --exclude='.env' \
  ~/ssl-toolkit-source/ /opt/ssl-toolkit/
sudo chown -R root:root /opt/ssl-toolkit
```

The service runs as user `ssltoolkit` and reads the root-owned code. The application must use separately controlled writable locations, such as `/var/lib/ssltoolkit` or appropriate private temporary storage.

## Environment configuration

Create `/etc/ssl-toolkit.env` on the server, outside Git:

```text
NODE_ENV=production
PORT=3000
HOST=127.0.0.1
```

```bash
sudo chown root:root /etc/ssl-toolkit.env
sudo chmod 600 /etc/ssl-toolkit.env
```

This file is intentionally **not** included in the repository. Real environment settings may differ. Do not copy secrets into GitHub issue screenshots, shell history or documentation.

## Service supervision

See the sanitized template at [`../systemd/ssl-toolkit.service`](../systemd/ssl-toolkit.service). It illustrates:

- `ExecStart=/usr/bin/node /opt/ssl-toolkit/server.js`
- `User=ssltoolkit`, `Group=ssltoolkit`
- `WorkingDirectory=/opt/ssl-toolkit`
- `EnvironmentFile=/etc/ssl-toolkit.env`
- `Restart=on-failure`, restart delay and several basic systemd hardening flags
- stdout/stderr captured through journald

For the actual `/etc/systemd/system/ssl-toolkit.service`, validate and activate with:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ssl-toolkit
sudo systemctl status ssl-toolkit --no-pager
sudo journalctl -u ssl-toolkit -n 50 --no-pager
```

The design avoids running the service through `sudo node`, `nohup`, or a terminal permanently left open. A `systemd` managed unit gives consistent startup, restart and log inspection.

## Local verification

```bash
systemctl is-active ssl-toolkit
sudo ss -ltnp | grep ':3000'
curl --fail --silent --show-error --max-time 10 \
  http://127.0.0.1:3000/ -o /dev/null
```

**Expected design:** TCP `127.0.0.1:3000` only, _not_ `0.0.0.0:3000`. Note that response behaviour depends on the application's actual routes; `curl -I` may not match `GET` handling, so a GET request is preferable.

For workstation-only review before public HTTPS, SSH local forwarding can expose the backend to a browser on the operator's computer without opening port 3000 in the security group:

```powershell
ssh -i "$HOME\Downloads\ssltoolkit-key.pem" `
  -L 8080:127.0.0.1:3000 ubuntu@YOUR_EC2_IP
```

Then browse to `http://localhost:8080` while keeping the SSH session open.

## Deployment safety and rollback

The current approach is manual. There is **no automated deployment or rollback pipeline** in this version. Before replacing a running release, record the deployed Git commit and retain a known-good application artifact in a protected server-side location. Stage and test new dependencies and configuration. Restart the service and validate its local route and HTTPS reverse-proxy path.

If a change fails, restore the known-good **code and dependency tree** along with compatible runtime configuration, then restart and verify. Merely running `git reset` in a directory without a `.git` folder will not work. Do not claim zero downtime or automated rollback.

## Acceptance checks

- Installed runtime and dependencies correspond to the deployed source commit.
- `ssl-toolkit.service` is active and enabled after reboot.
- Runtime user is unprivileged; application files are root-owned.
- Only loopback TCP 3000 is listening.
- The application interface and disposable-certificate workflows respond correctly.
- Journal logging captures application errors without revealing private-key contents.

## Reference

- [npm ci](https://docs.npmjs.com/cli/v10/commands/npm-ci)
- [Node.js net.Server.listen](https://nodejs.org/api/net.html#serverlisten)
