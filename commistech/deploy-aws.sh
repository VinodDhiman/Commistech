#!/bin/bash
# ============================================================
#  Commis Tech Website — AWS S3 + CloudFront Deployment Script
#  Usage: chmod +x deploy-aws.sh && ./deploy-aws.sh
# ============================================================

set -e  # Exit immediately on error

# ─── CONFIGURATION — edit these values ───────────────────
BUCKET_NAME="commistech-website"          # Must be globally unique on S3
REGION="us-east-1"                        # AWS region
DOMAIN="commistech.com"                   # Your domain name
PROFILE="default"                         # AWS CLI profile name
DIST_DIR="."                              # Directory containing your HTML files
# ─────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "======================================================="
echo "  🚀  Commis Tech — AWS Deployment"
echo "======================================================="
echo ""

# ─── PREFLIGHT CHECKS ────────────────────────────────────
log_info "Checking dependencies..."
command -v aws  >/dev/null 2>&1 || log_error "AWS CLI not installed. Install: https://aws.amazon.com/cli/"
command -v jq   >/dev/null 2>&1 || log_warn  "jq not found — some output may be raw JSON. Install: brew install jq"

log_info "Verifying AWS credentials..."
aws sts get-caller-identity --profile "$PROFILE" --output json >/dev/null 2>&1 \
  || log_error "AWS credentials not configured. Run: aws configure --profile $PROFILE"
log_success "AWS credentials valid."

# ─── STEP 1: CREATE S3 BUCKET ────────────────────────────
log_info "Creating S3 bucket: $BUCKET_NAME ..."

# Check if bucket already exists (owned by you)
if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$PROFILE" 2>/dev/null; then
  log_warn "Bucket $BUCKET_NAME already exists — skipping creation."
else
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --output json
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" \
      --profile "$PROFILE" \
      --output json
  fi
  log_success "Bucket created: s3://$BUCKET_NAME"
fi

# ─── STEP 2: BLOCK PUBLIC ACCESS (CloudFront will serve) ─
log_info "Blocking all public S3 access (OAC will be used instead)..."
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --profile "$PROFILE"
log_success "Public access blocked."

# ─── STEP 3: ENABLE VERSIONING ────────────────────────────
log_info "Enabling S3 versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled \
  --profile "$PROFILE"
log_success "Versioning enabled."

# ─── STEP 4: ENABLE SERVER-SIDE ENCRYPTION ───────────────
log_info "Enabling server-side encryption (AES-256)..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }' \
  --profile "$PROFILE"
log_success "Encryption enabled."

# ─── STEP 5: UPLOAD FILES ────────────────────────────────
log_info "Uploading website files to S3..."

# HTML files — no cache (always fresh)
aws s3 sync "$DIST_DIR" "s3://$BUCKET_NAME/" \
  --exclude "*" \
  --include "*.html" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "text/html; charset=utf-8" \
  --profile "$PROFILE" \
  --delete

# CSS files — 1 year cache
aws s3 sync "$DIST_DIR" "s3://$BUCKET_NAME/" \
  --exclude "*" \
  --include "*.css" \
  --cache-control "max-age=31536000, immutable" \
  --content-type "text/css" \
  --profile "$PROFILE"

# JS files — 1 year cache
aws s3 sync "$DIST_DIR" "s3://$BUCKET_NAME/" \
  --exclude "*" \
  --include "*.js" \
  --cache-control "max-age=31536000, immutable" \
  --content-type "application/javascript" \
  --profile "$PROFILE"

# Images — 30 days cache
aws s3 sync "$DIST_DIR" "s3://$BUCKET_NAME/" \
  --exclude "*" \
  --include "*.png" --include "*.jpg" --include "*.jpeg" \
  --include "*.gif"  --include "*.svg" --include "*.webp" \
  --include "*.ico" \
  --cache-control "max-age=2592000" \
  --profile "$PROFILE"

log_success "Files uploaded."

# ─── STEP 6: CREATE CLOUDFRONT OAC ───────────────────────
log_info "Creating CloudFront Origin Access Control (OAC)..."
OAC_RESULT=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config '{
    "Name": "commistech-oac",
    "Description": "OAC for Commis Tech website",
    "SigningProtocol": "sigv4",
    "SigningBehavior": "always",
    "OriginAccessControlOriginType": "s3"
  }' \
  --profile "$PROFILE" \
  --output json 2>/dev/null || echo '{"OriginAccessControl":{"Id":"EXISTING"}}')

OAC_ID=$(echo "$OAC_RESULT" | grep -o '"Id": "[^"]*"' | head -1 | cut -d'"' -f4)
log_success "OAC ID: $OAC_ID"

# ─── STEP 7: CREATE CLOUDFRONT DISTRIBUTION ──────────────
log_info "Creating CloudFront distribution..."

CF_CONFIG=$(cat <<CFEOF
{
  "Comment": "Commis Tech Website",
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "S3Origin",
      "DomainName": "${BUCKET_NAME}.s3.${REGION}.amazonaws.com",
      "S3OriginConfig": { "OriginAccessIdentity": "" },
      "OriginAccessControlId": "${OAC_ID}"
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3Origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "ResponseHeadersPolicyId": "eaab4381-ed33-4a86-88ca-d9558dc6cd63",
    "Compress": true,
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] }
    }
  },
  "CustomErrorResponses": {
    "Quantity": 2,
    "Items": [
      {
        "ErrorCode": 403,
        "ResponsePagePath": "/index.html",
        "ResponseCode": "200",
        "ErrorCachingMinTTL": 300
      },
      {
        "ErrorCode": 404,
        "ResponsePagePath": "/index.html",
        "ResponseCode": "200",
        "ErrorCachingMinTTL": 300
      }
    ]
  },
  "PriceClass": "PriceClass_100",
  "Enabled": true,
  "HttpVersion": "http2and3",
  "IsIPV6Enabled": true
}
CFEOF
)

CF_RESULT=$(aws cloudfront create-distribution \
  --distribution-config "$CF_CONFIG" \
  --profile "$PROFILE" \
  --output json)

CF_ID=$(echo "$CF_RESULT"     | grep -o '"Id": "[^"]*"' | head -1 | cut -d'"' -f4)
CF_DOMAIN=$(echo "$CF_RESULT" | grep -o '"DomainName": "[^"]*\.cloudfront\.net"' | head -1 | cut -d'"' -f4)

log_success "CloudFront Distribution: $CF_ID"
log_success "CloudFront Domain: https://$CF_DOMAIN"

# ─── STEP 8: ATTACH S3 BUCKET POLICY FOR OAC ─────────────
log_info "Attaching S3 bucket policy for CloudFront OAC..."

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)

BUCKET_POLICY=$(cat <<PEOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontServicePrincipal",
    "Effect": "Allow",
    "Principal": {
      "Service": "cloudfront.amazonaws.com"
    },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CF_ID}"
      }
    }
  }]
}
PEOF
)

aws s3api put-bucket-policy \
  --bucket "$BUCKET_NAME" \
  --policy "$BUCKET_POLICY" \
  --profile "$PROFILE"
log_success "Bucket policy applied."

# ─── DONE ────────────────────────────────────────────────
echo ""
echo "======================================================="
echo "  ✅  Deployment Complete!"
echo "======================================================="
echo ""
echo "  CloudFront URL:  https://$CF_DOMAIN"
echo "  S3 Bucket:       s3://$BUCKET_NAME"
echo "  CF Distribution: $CF_ID"
echo ""
echo "  ⏳  Note: CloudFront may take 5–15 minutes to fully deploy."
echo ""
echo "  📋  Next Steps:"
echo "  1. Point your domain ($DOMAIN) CNAME → $CF_DOMAIN"
echo "  2. Request an ACM certificate in us-east-1 for HTTPS"
echo "  3. Attach the cert to your CloudFront distribution"
echo "  4. Set CF Alternate Domain Name (CNAME) to $DOMAIN"
echo ""
