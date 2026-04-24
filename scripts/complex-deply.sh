#!/bin/bash
# =============================================================================
# LUIT EC2 Apache Webserver — Complex Tier
# AWS CLI Implementation
# =============================================================================
# Prerequisites:
#   - AWS CLI installed and configured (aws configure)
#   - Existing key pair available in your AWS account
#   - Update the variables below before running
# =============================================================================

# ------------------------------------------------------------------------------
# VARIABLES — update these before running
# ------------------------------------------------------------------------------
KEY_NAME="LUIT-2-kp"               # Your existing key pair name
REGION="us-east-1"                  # Target region
SG_NAME="luit-complex-sg"           # Security group name
INSTANCE_NAME="luit-complex-ec2"    # EC2 instance tag name
AMI_NAME="luit-complex-ami"         # Custom AMI name

# ------------------------------------------------------------------------------
# STEP 1: Get Default VPC ID
# ------------------------------------------------------------------------------
echo "Retrieving default VPC ID..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region $REGION)
echo "Default VPC: $VPC_ID"

# ------------------------------------------------------------------------------
# STEP 2: Create Security Group
# ------------------------------------------------------------------------------
echo "Creating security group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_NAME" \
  --description "Security group for LUIT complex EC2 project" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "GroupId" \
  --output text)
echo "Security Group ID: $SG_ID"

# ------------------------------------------------------------------------------
# STEP 3: Configure Inbound Rules
# Port 80 — HTTP (Apache web traffic)
# Port 22 — SSH (management access)
# NOTE: In production, restrict port 22 to your IP: --cidr YOUR.IP.HERE/32
# ------------------------------------------------------------------------------
echo "Opening port 80 (HTTP)..."
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region $REGION

echo "Opening port 22 (SSH)..."
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region $REGION

# ------------------------------------------------------------------------------
# STEP 4: Get Latest Amazon Linux 2023 AMI
# --owners amazon ensures only official Amazon AMIs are returned
# sort_by selects the most recently published image automatically
# ------------------------------------------------------------------------------
echo "Retrieving latest Amazon Linux 2023 AMI..."
BASE_AMI=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=owner-alias,Values=amazon" \
             "Name=architecture,Values=x86_64" \
             "Name=name,Values=al2023-ami-*" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text \
  --region $REGION)
echo "Amazon Linux 2023 AMI: $BASE_AMI"

# ------------------------------------------------------------------------------
# STEP 5: Create User-Data Script
# systemctl start httpd  — starts Apache immediately on first boot
# systemctl enable httpd — ensures Apache restarts on every subsequent reboot
# ------------------------------------------------------------------------------

```bash
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
```

**PowerShell (Windows):**
```powershell
New-Item -Path . -Name "userdata.sh" -ItemType "file" -Value "#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd"
```

Passed to the instance at launch via `file://userdata.sh`.

# ------------------------------------------------------------------------------
# STEP 6: Launch EC2 Instance
# ------------------------------------------------------------------------------
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $BASE_AMI \
  --instance-type t2.micro \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --user-data file://userdata.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --count 1 \
  --region $REGION \
  --query "Instances[0].InstanceId" \
  --output text)
echo "Instance ID: $INSTANCE_ID"

# ------------------------------------------------------------------------------
# STEP 7: Wait for Instance to be Running
# ------------------------------------------------------------------------------
echo "Waiting for instance to reach running state..."
aws ec2 wait instance-running \
  --instance-ids $INSTANCE_ID \
  --region $REGION

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text \
  --region $REGION)
echo "Instance running. Public IP: $PUBLIC_IP"
echo "Verify Apache: http://$PUBLIC_IP (allow 60 seconds for user-data to complete)"

# ------------------------------------------------------------------------------
# STEP 8: Create Custom AMI (Golden Image)
# --no-reboot keeps the instance running during AMI creation
# ------------------------------------------------------------------------------
echo "Creating custom AMI from running instance..."
CUSTOM_AMI=$(aws ec2 create-image \
  --instance-id $INSTANCE_ID \
  --name "$AMI_NAME" \
  --description "AMI created from $INSTANCE_NAME via CLI" \
  --no-reboot \
  --region $REGION \
  --query "ImageId" \
  --output text)
echo "Custom AMI ID: $CUSTOM_AMI"

echo "Waiting for AMI to become available..."
aws ec2 wait image-available \
  --image-ids $CUSTOM_AMI \
  --region $REGION
echo "AMI available: $CUSTOM_AMI"

# ------------------------------------------------------------------------------
# STEP 9: Launch Instance from Custom AMI
# No --user-data flag needed — Apache is already baked into the golden image
# ------------------------------------------------------------------------------
echo "Launching instance from custom AMI..."
INSTANCE_ID_2=$(aws ec2 run-instances \
  --image-id $CUSTOM_AMI \
  --instance-type t2.micro \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}-from-ami}]" \
  --count 1 \
  --region $REGION \
  --query "Instances[0].InstanceId" \
  --output text)
echo "Instance 2 ID: $INSTANCE_ID_2"

# ------------------------------------------------------------------------------
# STEP 10: Wait and Verify
# ------------------------------------------------------------------------------
echo "Waiting for instance 2 to reach running state..."
aws ec2 wait instance-running \
  --instance-ids $INSTANCE_ID_2 \
  --region $REGION

PUBLIC_IP_2=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID_2 \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text \
  --region $REGION)
echo "Instance 2 running. Public IP: $PUBLIC_IP_2"
echo "Verify Apache: http://$PUBLIC_IP_2"

# ------------------------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "DEPLOYMENT COMPLETE"
echo "============================================================"
echo "Security Group:      $SG_ID"
echo "Base AMI:            $BASE_AMI"
echo "Custom AMI:          $CUSTOM_AMI"
echo "Instance 1 (script): $INSTANCE_ID — http://$PUBLIC_IP"
echo "Instance 2 (AMI):    $INSTANCE_ID_2 — http://$PUBLIC_IP_2"
echo ""
echo "CLEANUP (run when done):"
echo "  aws ec2 terminate-instances --instance-ids $INSTANCE_ID $INSTANCE_ID_2"
echo "  aws ec2 deregister-image --image-id $CUSTOM_AMI"
echo "  aws ec2 delete-security-group --group-id $SG_ID"
echo "  (Also delete the AMI snapshot from EC2 > Snapshots in console)"
echo "============================================================"
