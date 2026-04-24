# AWS EC2 Apache Web Server — Level Up Bank

## Business Use Case
Level Up Bank is migrating its website and online banking platform 
from on-premises infrastructure to AWS EC2 to improve scalability, 
reliability, and security.

**Why move from on-premises to EC2?**
- **Scalability** — EC2 instances scale up or down on demand without 
  hardware investment
- **Reliability** — Multiple availability zones with automatic failover
- **Security** — AWS compliance certifications, encryption, and access 
  controls built in
- **Cost savings** — Pay-as-you-go eliminates upfront hardware costs
- **Flexibility** — Spin up new instances, test features, and respond 
  quickly to market changes

## Architecture

## Tools & Services Used
- AWS EC2 (Elastic Compute Cloud)
- Amazon Linux 2023
- Apache HTTP Server (httpd)
- AWS AMI (Amazon Machine Image)
- AWS Console (Console method)
- AWS CLI (CLI method — coming soon)

## Prerequisites
- AWS Account with EC2 permissions
- AWS CLI installed and configured (for CLI method)
- Key pair for SSH access

---

## Implementation — Console Method

### Step 1: Launch EC2 Instance

**Configuration:**

| Setting | Value | Reason |
|---|---|---|
| Instance type | t2.micro | Free tier eligible |
| AMI | Amazon Linux 2023 | AWS-optimized, free tier eligible |
| Key pair | Existing sandbox key pair | Required for SSH access |
| Auto-assign public IP | Enabled | Required for browser verification |
| Storage | 8 GiB EBS | Default, within free tier |

### Step 2: Configure Security Group

Created security group: `levelupbank-sg`

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | 0.0.0.0/0 | SSH management access |
| 80 | TCP | 0.0.0.0/0 | HTTP web traffic |

> **Security Note:** In production, port 22 would be restricted to 
> a specific corporate IP range, never open to 0.0.0.0/0. Port 80 
> would sit behind a load balancer rather than being directly exposed. 
> Additional layers including NACLs, VPCs, and WAF would provide 
> defense in depth.

### Step 3: User-Data Script

The following script runs automatically on first boot, installing and 
starting Apache before the instance is accessible:

```bash
#!/bin/bash
sudo dnf update -y
sudo dnf install -y httpd
sudo systemctl start httpd
sudo systemctl enable httpd
```

> **Two most important lines:**
> - `sudo dnf install -y httpd` — installs Apache. The `-y` flag 
>   prevents the script from hanging waiting for user confirmation 
>   since user-data runs non-interactively
> - `sudo systemctl enable httpd` — ensures Apache restarts 
>   automatically if the instance reboots. Without this, a reboot 
>   would take the website down

### Step 4: Verify Apache Installation

Verified two ways:

**Browser verification:**
- Navigated to `http://54.172.59.245` in an incognito browser
- Confirmed default Apache page: "It works!"

**SSH verification:**

Two methods available:

*Method 1 — EC2 Instance Connect (Console):*
- Navigate to EC2 → Instances → Select instance → Click "Connect"
- Select "EC2 Instance Connect" tab → Click "Connect"
- Ran: `systemctl status httpd`
- Confirmed: `active (running)`

*Method 2 — CLI SSH (Recommended for production):*
- Requires your `.pem` key pair file downloaded locally
- Run the following command from your terminal:
```bash
ssh -i "your-key-pair.pem" ec2-user@54.172.59.245
```
- Once connected, verify Apache:
```bash
systemctl status httpd
```

> **Why CLI SSH is preferred:** EC2 Instance Connect requires AWS 
> Console access and an internet-accessible instance. CLI SSH works 
> in private subnets via a bastion host and doesn't depend on the 
> AWS Console being available — critical for production environments 
> where console access may be restricted.

### Troubleshooting Note
The AWS Console "open address" link defaults to `https://` (port 443). 
Since only port 80 (HTTP) was opened, this caused a connection timeout. 
Manually navigating to `http://[public-ip]` resolved the issue. 

> **Key lesson:** Always verify which port your browser is using when 
> testing. HTTPS (443) and HTTP (80) are different ports and both must 
> be explicitly opened in the security group to work.

---

## Advanced Tier — AMI Creation

### What is an AMI?
An Amazon Machine Image (AMI) is a golden image — a complete snapshot 
of a configured EC2 instance that can be used to launch identical 
instances on demand.

**Why AMIs matter:**
- **Rapid scaling** — spin up 50 identical configured instances in 
  minutes without manual setup
- **Consistency** — every instance launched from the AMI is identical, 
  eliminating configuration drift
- **Disaster recovery** — if an instance is compromised or fails, 
  terminate it and replace it instantly from the golden image
- **Immutable infrastructure** — instead of patching a potentially 
  compromised server, destroy and replace from a known-good baseline

> **Real-world analogy:** The original Amazon Linux 2023 AMI is the 
> plain base. Our AMI is the fully configured golden image — same base, 
> with Apache installed, enabled, and ready to serve traffic the moment 
> the instance boots.

### Step 1: Create the AMI

From EC2 → Instances → select `levelupbank-webserver` →
Actions → Image and templates → Create image

| Setting | Value |
|---|---|
| Image name | `levelupbank-webserver-ami` |
| Description | `Golden image — Amazon Linux 2023 with Apache installed and enabled` |
| AMI ID | `ami-0e863c09000596c5e` |
| Visibility | Private |
| Architecture | x86_64 |
| Virtualization | HVM |

> **Security Note:** Visibility is set to Private — only this AWS 
> account can use this image. Never make a golden image public unless 
> intentionally sharing it, as it could expose your server configuration 
> to bad actors.

> **Cost Note:** AMIs themselves are free. The EBS snapshot backing 
> the AMI costs ~$0.05/GB/month (~$0.40/month for an 8GB instance). 
> Delete AMIs and their associated snapshots when no longer needed.

### Step 2: Launch Instance from AMI

Launched a new instance directly from the golden image:

| Setting | Value |
|---|---|
| Instance name | `levelupbank-from-ami` |
| AMI | `ami-0e863c09000596c5e` (our golden image) |
| Instance type | t2.micro |
| Security group | `levelupbank-sg` (existing) |
| User-data | **Empty — not required** |
| Public IP | `23.20.71.156` |

### Step 3: Verify

- Navigated to `http://23.20.71.156` in an incognito browser
- Confirmed: **"It works!"** — Apache serving traffic immediately
- No user-data script required — Apache was already installed 
  and enabled inside the golden image

### Key Insight — User-Data vs AMI

| Approach | How Apache Gets Installed | Time to Serve Traffic |
|---|---|---|
| User-data script | Installs on first boot | 2-3 min after launch |
| Golden AMI | Already installed | Immediately on boot |

> **DevSecOps Note:** Adding a user-data script to an instance launched 
> from this AMI could cause conflicts since Apache is already installed. 
> In production, scripts should be **idempotent** — designed to run 
> safely multiple times without causing errors regardless of current state.

### Running Instances

| Instance | ID | Public IP | Source |
|---|---|---|---|
| `levelupbank-webserver` | i-0525b76b904678550 | 54.172.59.245 | Original — user-data |
| `levelupbank-from-ami` | i-01059c9ef7d501a38 | 23.20.71.156 | Golden AMI — no script |

## Complex Tier — CLI Method
*Coming soon*

---

## Security Findings & Next Steps

| Finding | Risk | Remediation |
|---|---|---|
| Port 22 open to 0.0.0.0/0 | High — SSH brute force attacks | Restrict to corporate IP range |
| HTTP only — no HTTPS | High — unencrypted traffic | Add SSL certificate + load balancer |
| No WAF | Medium — vulnerable to web attacks | Add AWS WAF ($14/month minimum) |
| Public IP directly exposed | Medium — no DDoS protection | Place behind load balancer |

## What I Learned
- User-data scripts run once on first boot — automation starts before 
  the instance is accessible
- The `-y` flag is critical in non-interactive scripts to prevent hangs
- Package name matters — Apache on Amazon Linux is `httpd` not `apache`
- Security groups are stateful firewalls — each port must be explicitly 
  opened or traffic is denied by default
- HTTP (port 80) and HTTPS (port 443) are separate ports requiring 
  separate security group rules

## Next Iterations
- [ ] Create AMI from running instance and launch new instance from it
- [ ] Repeat full implementation using AWS CLI
- [ ] Create key pair via CLI
- [ ] Add HTTPS with SSL certificate
