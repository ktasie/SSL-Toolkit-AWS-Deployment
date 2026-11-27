# 04 — NGINX Reverse Proxy, DNS and HTTPS

[← Application deployment](03-application-deployment.md) · [Next: Monitoring →](05-monitoring-and-automation.md)

## Objective

Published the application over TLS through NGINX, keeping the Node.js runtime isolated on loopback. Implement DNS routing, obtain a public certificate through Let's Encrypt, and verify automated renewal.

## Request path

```text
Browser → DNS A record → EC2 public IPv4 → Security Group :443
          → NGINX (TLS) → http://127.0.0.1:3000 → Node.js
```

NGINX is the only public-facing application listener. A public client should never connect directly to port 3000.

## DNS and address stability

The AWS deployment uses a **separate deployment hostname** from any pre-existing SSL Toolkit site. Configured an A record to point to the EC2 public IPv4/Elastic IP.

```bash
dig +short aws-ssltools.virtualsolutionsng.com A
```

Automatically assigned EC2 public IPv4 addresses normally change when an instance is stopped and started. An Elastic IP offers a stable address but may continue to incur cost while allocated. If using a changing address, update DNS and wait for resolver caches before testing.

## NGINX setup

```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl enable --now nginx
sudo nginx -t
sudo systemctl status nginx --no-pager
```

Stored a sanitized copy of the tested site configuration in [`../nginx/ssl-toolkit.conf`](../nginx/ssl-toolkit.conf).

- Redirects HTTP traffic to HTTPS.
- Uses the Let's Encrypt full chain and key paths.
- Proxies `location /` to `127.0.0.1:3000`.
- Sets host, client IP and scheme headers.
- Limits request body size (`2m` as a _starting_ value) and sets proxy timeouts.

For a deployed config:

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo ss -ltnp | grep -E ':80|:443|:3000'
```

The actual `nginx -T` output is stronger evidence of loaded configuration than merely showing a file on disk. Review output for sensitive details before publishing.

## Certificate issuance and renewal

Certbot with Let's Encrypt provides an ACME-managed publicly trusted TLS certificate for the hostname. In the initial setup, HTTP port 80 was publicly reachable for HTTP-01 validation, while HTTPS 443 was restricted to authorised client IPs.

Example issuance (run only when DNS and public HTTP-01 reachability are valid):

```bash
sudo certbot certonly --nginx -d aws-ssltools.virtualsolutionsng.com
```

The resulting files are typically under `/etc/letsencrypt/live/aws-ssltools.virtualsolutionsng.com/`. `fullchain.pem` and `privkey.pem` are referenced by NGINX.

Review active renewal configuration and run a simulated renewal:

```bash
certbot --version
systemctl list-timers --all | grep -i certbot
sudo certbot renew --dry-run
```

If a deploy hook reloads NGINX after successful renewal, validate it separately. A successful dry-run is a test of the renewal challenge, **not** a guarantee that a stopped EC2 instance will renew automatically. The instance, DNS and validation path must remain usable at renewal time.

## TLS / HTTP tests

```bash
# Test HTTP redirect (remote client or local EC2)
curl -I http://aws-ssltools.virtualsolutionsng.com

# Browser/API check from authorised source
curl --fail --show-error -I https://aws-ssltools.virtualsolutionsng.com

# Avoid public-IP hairpin assumptions: test NGINX via loopback on EC2
DOMAIN='aws-ssltools.virtualsolutionsng.com'
curl --fail --show-error \
  --resolve "${DOMAIN}:443:127.0.0.1" \
  "https://${DOMAIN}/" -o /dev/null

# Presented certificate details
echo | openssl s_client -connect "${DOMAIN}:443" \
  -servername "$DOMAIN" 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates
```

Expected behaviour: HTTP redirects to HTTPS, certificate hostname and chain validate, NGINX serves the application, and Node.js remains loopback-only. A GET may be more suitable than HEAD for application routes.

## Troubleshooting matrix

| Symptom              | Investigate                | Commands                                           |
| -------------------- | -------------------------- | -------------------------------------------------- |
| Domain not resolving | A record/TTL/nameserver    | `dig +short aws-ssltools.virtualsolutionsng.com A` |
| Connection timeout   | Public IP, routes, SG, UFW | `ss -ltnp`, VPC console, `ufw status`              |
| 502 Bad Gateway      | Backend process / port     | `systemctl status ssl-toolkit`, NGINX error log    |
| 413 body too large   | Upload size limit          | `client_max_body_size`, NGINX error log            |
| TLS mismatch/expiry  | Certificate and hostname   | `openssl s_client`, `certbot certificates`         |
| Renewal failure      | DNS, reachability, port 80 | `certbot renew --dry-run`, renewal logs            |

## Security note

NGINX TLS protects transit to the reverse proxy, but **does not secure the certificate-processing code** by itself. Treat private-key uploads as sensitive even in a lab; use disposable keys, avoid retaining payloads/logs, and keep access restricted pending further security review.

## Reference

- [NGINX proxy module](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [Certbot instructions](https://certbot.eff.org/instructions)
