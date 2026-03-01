# Commis Tech Website — AWS Deployment Guide

## 📁 Package Contents

| File | Purpose |
|------|---------|
| `index.html` | Full website (single-page, production-ready) |
| `deploy-aws.sh` | Automated S3 + CloudFront deployment script |
| `cloudformation.yml` | Full AWS Infrastructure as Code (recommended) |
| `nginx.conf` | Nginx config for EC2 deployment |
| `nginx-docker.conf` | Nginx config for Docker/ECS deployment |
| `Dockerfile` | Container build for ECS / App Runner |

---

## 🚀 Option 1: CloudFormation (Recommended — Infrastructure as Code)

**Prerequisites:** AWS CLI installed and configured

### Step 1 — Deploy infrastructure
```bash
aws cloudformation deploy \
  --template-file cloudformation.yml \
  --stack-name commistech-website \
  --parameter-overrides \
      DomainName=commistech.com \
      BucketName=commistech-website-prod \
  --region us-east-1
```

### Step 2 — Upload website files
```bash
# Get bucket name from stack outputs
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name commistech-website \
  --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
  --output text)

# Upload files
aws s3 sync . s3://$BUCKET/ \
  --exclude "*.sh" --exclude "*.yml" --exclude "*.md" \
  --exclude "Dockerfile" --exclude "*.conf" \
  --delete
```

### Step 3 — Invalidate CloudFront cache (after updates)
```bash
CF_ID=$(aws cloudformation describe-stacks \
  --stack-name commistech-website \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
  --output text)

aws cloudfront create-invalidation \
  --distribution-id $CF_ID \
  --paths "/*"
```

### Step 4 — Add HTTPS with your domain (optional but recommended)
```bash
# 1. Request ACM certificate (must be in us-east-1 for CloudFront)
aws acm request-certificate \
  --domain-name commistech.com \
  --subject-alternative-names "www.commistech.com" \
  --validation-method DNS \
  --region us-east-1

# 2. Validate the certificate via DNS (add the CNAME records shown in ACM console)

# 3. Update stack with certificate ARN
aws cloudformation update-stack \
  --stack-name commistech-website \
  --template-body file://cloudformation.yml \
  --parameters \
    ParameterKey=AcmCertificateArn,ParameterValue=arn:aws:acm:us-east-1:ACCOUNT:certificate/CERT-ID
```

---

## 🚀 Option 2: Bash Script (Quick Deploy)

```bash
# 1. Edit configuration at top of script
nano deploy-aws.sh

# 2. Make executable
chmod +x deploy-aws.sh

# 3. Run
./deploy-aws.sh
```

---

## 🚀 Option 3: EC2 with Nginx

### Launch EC2 (Amazon Linux 2023 recommended)
```bash
# Install Nginx
sudo dnf install -y nginx

# Create web root
sudo mkdir -p /var/www/commistech

# Copy files
sudo cp index.html /var/www/commistech/

# Install Nginx config
sudo cp nginx.conf /etc/nginx/sites-available/commistech.conf
sudo ln -s /etc/nginx/sites-available/commistech.conf /etc/nginx/sites-enabled/

# Generate DH params (security hardening)
sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048

# Install Certbot for free SSL
sudo dnf install -y certbot python3-certbot-nginx
sudo certbot --nginx -d commistech.com -d www.commistech.com

# Enable and start Nginx
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl start nginx
```

### EC2 Security Group Ports
| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 80 | TCP | 0.0.0.0/0 | HTTP (redirects to HTTPS) |
| 443 | TCP | 0.0.0.0/0 | HTTPS |
| 22 | TCP | Your IP only | SSH management |

---

## 🚀 Option 4: Docker / ECS / App Runner

### Build and test locally
```bash
docker build -t commistech-web .
docker run -p 8080:80 commistech-web
# Open http://localhost:8080
```

### Push to Amazon ECR
```bash
REGION=us-east-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REPO="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/commistech-web"

# Create ECR repo
aws ecr create-repository --repository-name commistech-web --region $REGION

# Login
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# Tag and push
docker tag commistech-web:latest "$REPO:latest"
docker push "$REPO:latest"
```

### Deploy to App Runner (simplest ECS option)
```bash
aws apprunner create-service \
  --service-name commistech-web \
  --source-configuration '{
    "ImageRepository": {
      "ImageIdentifier": "'$REPO':latest",
      "ImageRepositoryType": "ECR",
      "ImageConfiguration": { "Port": "80" }
    },
    "AutoDeploymentsEnabled": true
  }' \
  --instance-configuration '{"Cpu":"0.25 vCPU","Memory":"0.5 GB"}'
```

---

## 💰 Cost Estimates (Monthly)

| Option | Est. Cost | Best For |
|--------|-----------|----------|
| S3 + CloudFront | $1–5/mo | Low traffic, static site |
| EC2 t3.micro | $8–15/mo | Full control, dynamic needs |
| App Runner | $5–25/mo | Auto-scaling, zero ops |
| ECS Fargate | $10–30/mo | High traffic, containers |

---

## 🔒 Security Checklist

- [x] HTTPS enforced via CloudFront / Nginx redirect
- [x] TLS 1.2+ only (1.3 preferred)
- [x] HSTS with preload enabled
- [x] CSP headers configured
- [x] X-Frame-Options: DENY
- [x] X-Content-Type-Options: nosniff
- [x] Referrer-Policy: strict-origin
- [x] Permissions-Policy configured
- [x] S3 public access blocked (OAC only)
- [x] S3 server-side encryption enabled
- [x] S3 versioning enabled
- [x] No eval() in JavaScript
- [x] Input validation and sanitization on forms
- [x] Double-submit prevention on contact form
- [x] Sensitive file access blocked (.env, .git, etc.)
- [ ] WAF WebACL — enable for production traffic
- [ ] AWS Shield Standard — enabled by default with CloudFront
- [ ] CloudTrail logging — recommended for audit trail
- [ ] GuardDuty — recommended for threat detection

---

## 🔄 Updating the Website

### S3 + CloudFront
```bash
# Upload changed files
aws s3 cp index.html s3://commistech-website-prod/ \
  --cache-control "no-cache"

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id YOUR_CF_ID \
  --paths "/*"
```

### EC2
```bash
sudo cp index.html /var/www/commistech/
# No restart needed — Nginx serves files directly
```

---

## 📞 Support

Commis Tech | (980) 292-0332 | info@commistech.com
