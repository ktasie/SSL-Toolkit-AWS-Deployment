#!/usr/bin/env bash
# Reference implementation. Compare with deployed /usr/local/bin script.
# Requires DOMAIN to be supplied by the systemd EnvironmentFile.
set -uo pipefail

: "${DOMAIN:?Set DOMAIN to the real HTTPS hostname in a protected env file}"
failed=0
printf '[%s] SSL Toolkit health check started\n' "$(date --iso-8601=seconds)"

for service in nginx ssl-toolkit; do
    if systemctl is-active --quiet "$service"; then
        printf 'OK: %s active\n' "$service"
    else
        printf 'FAIL: %s inactive\n' "$service" >&2
        failed=1
    fi
done

if curl --fail --silent --show-error --max-time 10 \
    --resolve "${DOMAIN}:443:127.0.0.1" \
    --output /dev/null "https://${DOMAIN}/"; then
    echo 'OK: local HTTPS reverse-proxy request succeeded'
else
    echo 'FAIL: local HTTPS reverse-proxy request failed' >&2
    failed=1
fi

if (( failed != 0 )); then
    echo 'RESULT: UNHEALTHY' >&2
    exit 1
fi

echo 'RESULT: HEALTHY'
