# 01 — AWS Infrastructure Provisioning

[← Project overview](../README.md) · [Next: Linux administration →](02-linux-administration.md)

## Objective

Created a small, deliberately understandable AWS environment for hosting SSL Toolkit on a single Ubuntu EC2 instance. The VPC design is public-subnet based; it avoids the expense and complexity of a NAT Gateway and an Application Load Balancer at this stage.

## Deployment profile

These are the configuration values used in the project plan. 

| Resource | Intended implementation | Engineering reason |
|---|---|---|
| Region | Europe (London), `eu-west-2a` | Locality and a consistent region for all services |
| VPC | `ssltoolkit-vpc`, `10.20.0.0/16` | Isolated address space and ownership of network design |
| Public subnet | `ssltoolkit-public-subnet`, `10.20.1.0/24` | Address space for the EC2 web host |
| Internet Gateway | `ssltoolkit-igw` | Internet ingress/egress path |
| Route table | `ssltoolkit-public-rt` | `0.0.0.0/0` → Internet Gateway, plus VPC local route |
| Security Group | `ssltoolkit-frontend-sg` | Stateful allow-list for inbound ports |
| EC2 | `ssltoolkit-web-01`; Ubuntu 24.04 LTS; initial `t3.micro` | General-purpose Linux host for the application |
| EBS | 8 GiB gp3 root volume | Persistent OS, software and log storage |
| IAM role | `ssltoolkit-ec2-role` | EC2 temporary credentials for management/telemetry |
| Public address | EC2 public IPv4 or Elastic IP | DNS target; choice influences stop/start behaviour |
| AWS Budget | Monthly notification threshold | Operational spending awareness; not a hard cap |

## Network traffic path

```text
Authorised client
      |
      | DNS A → public IPv4 address
      v
Internet Gateway → Public route table → EC2 Security Group
                                              |
                                     NGINX :443 / :80
                                              |
                                      127.0.0.1:3000
                                              |
                                         SSL Toolkit
```

The internet route alone does not publish a workload: the instance also requires a public IP, its route association, permissive network ACLs, and the appropriate inbound security-group rules. The Node.js service is intentionally **not** allowed directly on TCP 3000.

## Inbound exposure

| Port | Source | Purpose |
|---|---|---|
| TCP 22 | Own / authorised public IP only | Key-based SSH management |
| TCP 80 | Internet, if using HTTP-01 certificate validation | Let's Encrypt validation and redirect |
| TCP 443 | Authorised public IP only for this setup | TLS-protected demonstration access |
| TCP 3000 | No public security-group rule | Backend is bound to loopback only |

**Defence in depth:** UFW provides host-based ingress control in addition to the AWS security group. Both controls must be configured correctly; an allow-list at one layer cannot override a denial at another.

## Provisioning sequence

1. Selected `eu-west-2a`; configured a spending budget notification.
2. Created custom VPC `10.20.0.0/16`.
3. Created the public subnet `10.20.1.0/24` in a London availability zone.
4. Created and attached an Internet Gateway.
5. Created a route table with `0.0.0.0/0` through the gateway and associated the public subnet.
6. Created a security group with restrictive SSH and web ingress.
7. Created an EC2 IAM role (later extended for CloudWatch Agent).
8. Launched Ubuntu EC2 in the custom subnet with gp3 EBS root storage and key-pair access.
9. Assigned a public IPv4 address, confirmed status checks and validated SSH connectivity.
10. Captured the network topology and resource settings for the evidence register.

## IAM role design

The instance role uses AWS-provided temporary credentials; no permanent access key needs to be stored in `/home/ubuntu` or the application environment. Policies used in the project:

- `AmazonSSMManagedInstanceCore`: Systems Manager agent access, assuming networking and user IAM permissions allow sessions.
- `CloudWatchAgentServerPolicy`: CloudWatch Agent metric publishing.

Do not give the EC2 role `AdministratorAccess` for convenience.

## Verification

**AWS Console checks:** Confirm selected region, instance subnet association, route table, IAM role, EBS encryption and security-group rules. Inspect EC2 `Status checks` separately from application health.

**Ubuntu checks:**

```bash
hostnamectl
cat /etc/os-release
lsblk -f
df -h /
ip -br addr
ip route
curl -I --max-time 10 https://www.amazon.com
```

**Why EBS?** EC2 provides CPU/RAM; EBS provides the root disk where Ubuntu, application code, packages, configuration and persisted logs reside. Stopping an EBS-backed instance preserves the volume; terminating usually deletes the root volume if delete-on-termination is enabled. 

## Constraints and trade-offs

- A public-subnet EC2 host has more direct network exposure than a private instance behind a load balancer. Access rules are therefore deliberately restrictive.
- The architecture has one availability zone and one VM: there is no automatic failover.
- The manual console setup is not infrastructure as code. Terraform is planned as a subsequent version.
- EBS and public IPv4 may incur charges even when compute is stopped; see [cost controls](09-cost-and-teardown.md).

## Evidence to attach

- VPC resource map and route table association, without sensitive identifiers.
- EC2 instance details (AMI/instance type), encrypted root EBS volume.
- Security-group inbound rules (no open port 3000, no world-open SSH).

See [validation/evidence register](08-validation-evidence.md).

## Reference

- [Amazon VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)
- [Amazon EC2 User Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/concepts.html)
