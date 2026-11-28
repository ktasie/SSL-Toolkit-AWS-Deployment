# 05 — CloudWatch Monitoring and Bash Automation

[← NGINX & HTTPS](04-nginx-https.md) · [Next: Incident recovery →](06-incident-recovery.md)

## Objective

Collect basic infrastructure and operating-system metrics, configure alert notifications, inspect application logs and run periodic application health checks. This is observability for a **single-instance deployment**, not an end-to-end on-call or SLO platform.

## Signals and tools

| Signal | Collector | Operational use |
|---|---|---|
| EC2 CPU / status checks | Default EC2 CloudWatch metrics | Detect host load and AWS health checks |
| RAM used % | CloudWatch Agent | Observe memory pressure on a small VM |
| Root disk used % | CloudWatch Agent | Detect filesystem exhaustion risk |
| Node.js unit state | `systemctl` | Check application process supervision |
| HTTP GET via NGINX/TLS | Bash + `curl` | Verify actual application response path |
| Application logs | `journalctl` | Investigate startup/runtime failure |
| Reverse-proxy logs | `/var/log/nginx/` | Diagnose upstream and HTTP failures |

## CloudWatch Agent

The EC2 IAM role needs `CloudWatchAgentServerPolicy` (alongside the Systems Manager role policy used earlier). This prevents having to put permanent AWS access keys onto the instance.

See [`../cloudwatch/cloudwatch-agent.json`](../cloudwatch/cloudwatch-agent.json). The agent publishes `mem_used_percent` and root `disk_used_percent` every 60 seconds to the `CWAgent` namespace with the EC2 instance identifier dimension.

Representative installation/configuration process:

```bash
# On an x86_64 Ubuntu instance; verify architecture first
uname -m
curl -fL \
  https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
  -o /tmp/amazon-cloudwatch-agent.deb
sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb

# After installing your validated configuration file at the server path:
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-agent.json

sudo systemctl status amazon-cloudwatch-agent --no-pager
```

The package URL is for `x86_64` Ubuntu. Use the correct package for another architecture. Check package authenticity using AWS-published signature guidance when installing binaries.

## Alarms and SNS notifications

A Standard SNS topic (e.g., `ssltoolkit-ops-alerts`) has an email subscription which must be confirmed by the recipient. CloudWatch alarm actions send state-change notifications through this topic.

| Alarm | Metric | Example policy |
|---|---|---|
| High CPU | `AWS/EC2 CPUUtilization` | Average >80% for 3 × 5-minute periods |
| High memory | `CWAgent mem_used_percent` | >85% for 5 × 1-minute periods |
| High disk | `CWAgent disk_used_percent` for `/` | >80% for 5 × 1-minute periods |
| EC2 status check failure | `AWS/EC2 StatusCheckFailed` | >0 for 2 supported periods |

Thresholds are **initial operational thresholds**. Confirm the actual metric dimensions and periods used in the Console; do not present these as observed production incident statistics. No automatic reboot/terminate alarm action is part of this first version.

When the instance is stopped, custom agent metrics stop publishing; alarm behaviour depends on missing-data settings. An SNS email alert for infrastructure is not the same as an external end-to-end uptime check.

## Bash application health check

[`../scripts/health-check.sh`](../scripts/health-check.sh) provides a reference script. It:

1. Checks whether `nginx` and `ssl-toolkit` are active.
2. Uses `curl --resolve` to send HTTPS to NGINX on loopback **while preserving the real hostname and certificate validation**.
3. Returns exit code `0` when healthy and `1` when any check fails.

A real hostname is supplied from a protected `/etc/ssl-toolkit-health.env` file:

```text
DOMAIN=aws-ssltools.virtualsolutionsng.com
```

```bash
sudo chown root:root /etc/ssl-toolkit-health.env
sudo chmod 600 /etc/ssl-toolkit-health.env
```

**Example manual check:**

```bash
sudo env DOMAIN=YOUR_REAL_DEPLOYMENT_DOMAIN \
  /usr/local/bin/ssltoolkit-health-check.sh
printf 'Exit status: %s\n' "$?"
```

On the server, copied the **reviewed and tested** health script to `/usr/local/bin/ssltoolkit-health-check.sh`, owned by root and executable by the service user. The effective script does not contain real secrets or keys.

## systemd service and timer

The two reference units are:

- [`../systemd/ssltoolkit-health-check.service`](../systemd/ssltoolkit-health-check.service)
- [`../systemd/ssltoolkit-health-check.timer`](../systemd/ssltoolkit-health-check.timer)

The one-shot service executes the script; the timer runs it periodically after boot and after the previous unit activation. Unit output goes to journald.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ssltoolkit-health-check.timer
systemctl list-timers --all | grep ssltoolkit
sudo systemctl start ssltoolkit-health-check.service
sudo journalctl -u ssltoolkit-health-check.service -n 50 --no-pager
```

A failed oneshot unit is visible through its exit status/logs; **it does not automatically send an SNS message**. Use CloudWatch alarms for the separate metrics listed above. A local timer cannot run during an EC2 host outage.

## Troubleshooting checklist

```bash
systemctl --failed
systemctl is-active nginx ssl-toolkit
sudo journalctl -u ssl-toolkit --since '30 minutes ago' --no-pager
sudo journalctl -u ssltoolkit-health-check.service -n 50 --no-pager
sudo tail -n 50 /var/log/nginx/error.log
free -h
df -h /
sudo ss -ltnp
```

Use logs to establish **what failed** and resource metrics to understand **possible contributing conditions**; don't assume correlation proves root cause.

## Validation criteria

- Memory and disk metrics visible in correct region and namespace.
- Alarm thresholds and recipients correctly configured; SNS subscription confirmed.
- Health script succeeds when app/NGINX are healthy and fails when the app is intentionally stopped.
- Timer executes successfully and its result appears in journald.
- Logs are usable for diagnosis and do not expose certificate key material.

## Reference

- [CloudWatch Agent configuration schema](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html)
- [AWS metrics and alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
