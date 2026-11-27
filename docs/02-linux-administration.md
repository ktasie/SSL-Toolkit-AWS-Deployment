# 02 — Ubuntu Linux Administration & Hardening

[← AWS infrastructure](01-aws-infrastructure.md) · [Next: Application deployment →](03-application-deployment.md)

## Objective

Prepared the EC2 instance as a maintainable Linux server by patching the OS, enforcing least-privilege execution, configuring SSH and host firewall controls, and using standard diagnostic facilities.

## Host baseline

- OS: Ubuntu Server 24.04 LTS (verify with `cat /etc/os-release`).
- Administrative access: `ubuntu` via SSH public-key authentication and restricted source IP.
- Application runtime account: `ssltoolkit`, a dedicated system user with no interactive login shell.
- Application code: `/opt/ssl-toolkit`, administrator-owned.
- Writable application data: `/var/lib/ssltoolkit`, owned by the service account.
- Service environment: `/etc/ssl-toolkit.env`, readable only by root; not committed.

## Updates and required tools

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl wget git jq unzip openssl ca-certificates \
  dnsutils lsof htop ufw unattended-upgrades rsync
```

`apt update` refreshes package indexes; `apt upgrade` applies candidate upgrades. `jq` validates JSON and parses API responses. `lsof`, `ss` and `ip` help diagnose open files, sockets and routes. `openssl` is required by SSL Toolkit's cryptographic workflows.

Reboot only during a maintenance window when needed; reconnect and verify both application and NGINX after reboot.

## System identity and application permissions

```bash
sudo hostnamectl set-hostname ssltoolkit-web-01
sudo useradd --system --home-dir /var/lib/ssltoolkit \
  --shell /usr/sbin/nologin ssltoolkit
sudo install -d -o root -g root -m 755 /opt/ssl-toolkit
sudo install -d -o ssltoolkit -g ssltoolkit -m 750 /var/lib/ssltoolkit
id ssltoolkit
stat -c '%A %U:%G %n' /opt/ssl-toolkit /var/lib/ssltoolkit
```

If the user or directories already exist, **inspect rather than blindly recreate** them. The service may read its installed dependencies and views but should not rewrite executable code. Review certificate processing and temporary file operations to ensure any necessary writes land in explicitly permitted locations and are removed when no longer needed.

## SSH authentication

```bash
sudo sshd -T | grep -E '^(passwordauthentication|permitrootlogin|pubkeyauthentication) '
```

Intended effective settings:

```text
passwordauthentication no
permitrootlogin no
pubkeyauthentication yes
```

Change SSH settings only after confirming a separate working key-based login and preferably a Systems Manager Session Manager fallback. A mistaken SSH change can lock you out of the instance. The AWS Security Group limits port 22 to the current authorised public address.

## Host firewall: UFW

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw show added
sudo ufw enable
sudo ufw status verbose
```

Open SSH **before** enabling UFW. Validate a second SSH connection before closing the original session. UFW permits relevant ports at the host layer; the EC2 security group narrows source IP ranges. There should be **no UFW ingress rule for port 3000**.

## Automatic updates

```bash
cat /etc/apt/apt.conf.d/20auto-upgrades
systemctl status apt-daily.timer apt-daily-upgrade.timer
```

With `unattended-upgrades` enabled, the apt configuration typically includes periodic package-list refresh and unattended upgrades. Keep automatic reboots under explicit operational control for this lab and record when the server was last rebooted after patching.

## Logging and resource diagnostics

| Goal | Command |
|---|---|
| Current resource usage | `free -h; df -h /; uptime` |
| Inspect storage | `lsblk -f` |
| Check failed units | `systemctl --failed` |
| View OS errors since boot | `sudo journalctl -p err -b --no-pager -n 50` |
| Inspect listeners | `sudo ss -ltnp` |
| Verify route | `ip route` |
| Check application logs | `sudo journalctl -u ssl-toolkit -n 50 --no-pager` |

`systemctl` manages units; `journalctl` reads the system journal. NGINX also maintains access/error log files. A listening socket does not prove the port is remotely reachable; security groups, firewalls and routes must all be considered.

## Validation / acceptance

- Can reconnect using key-based SSH.
- `ssltoolkit` is a non-login user and does not need `sudo`.
- Application code is not writable by `ssltoolkit`.
- UFW is active with the expected ingress controls.
- OS patch/update status is understood and operational errors can be inspected.
- No AWS access keys are stored on disk.

## Security limitations

Host hardening does **not** guarantee that the Node.js application is secure. A certificate-processing service requires separate review for unsafe file uploads, temporary files, request size constraints, dependency vulnerabilities and private-key handling. Refer to [security/limitations](07-security-and-limitations.md).

## Reference

- [Ubuntu Server security](https://documentation.ubuntu.com/server/explanation/security/security/)
- [systemd](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)
