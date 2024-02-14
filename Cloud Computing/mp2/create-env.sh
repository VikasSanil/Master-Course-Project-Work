#!/bin/bash

# Values from arguments.txt.
IMAGE_ID=$1
INSTANCE_TYPE=$2
KEY_NAME=$3
SECURITY_GROUP_IDS=$4
COUNT=$5
AVALABILITY_ZONE=$6
ELB_NAME=$7
TARGET_GROUP_NAME=$8
AUTO_SCALING_GRP=$9
LAUNCH_CONFIG_NAME=${10}
MYDBINSTANCE=${11}
MYDBINSREPLICA=${12}
MIN_SIZE=${13}
MAX_SIZE=${14}
DESIRED_CAPACITY=${15}
DB_ENGINE=${16}
DB_NAME=${17}
S3_RAW_BUCKET_NAME=${18}
S3_FINISHED_BUCKET_NAME=${19}
AWS_SECRET_NAME=${20}
IAM_INSTANCE_PROFILE=${21}
SNS_TOPIC=${22}

# Values already available in environment.
SUBNET_ID=$(aws ec2 describe-subnets --query 'Subnets[*].SubnetId')
SUBNET_ID_ARRAY=($SUBNET_ID)
VPCID=$(aws ec2 describe-vpcs --output=text --query 'Vpcs[*].VpcId')
aws secretsmanager create-secret --name $AWS_SECRET_NAME --secret-string file://maria.json
SECRET_ID=$(aws secretsmanager list-secrets --filters Key=name,Values=$AWS_SECRET_NAME --query 'SecretList[*].ARN')
USERVALUE=$(aws secretsmanager get-secret-value --secret-id $SECRET_ID --output=json | jq '.SecretString' | tr -s , ' ' | tr -s ['"'] ' ' | awk {'print $6'} |  tr -d '\\')
PASSVALUE=$(aws secretsmanager get-secret-value --secret-id $SECRET_ID --output=json | jq '.SecretString' | tr -s } ' ' | tr -s ['"'] ' ' | awk {'print $12'} | tr -d '\\')

echo "New Target Group creation: STARTED."
# Creating a new Target group
aws elbv2 create-target-group \
--name $TARGET_GROUP_NAME \
--protocol HTTP \
--port 80 \
--target-type instance \
--vpc-id $VPCID \
--no-cli-pager  

echo "New Target Group creation: COMPLETED."

echo "New Load Balancer creation: STARTED."

aws elbv2 create-load-balancer \
--name $ELB_NAME \
--subnets ${SUBNET_ID_ARRAY[0]} ${SUBNET_ID_ARRAY[1]} \
--security-groups $SECURITY_GROUP_IDS \
--no-cli-pager


# Waiting for load balancer to be available.
aws elbv2 wait load-balancer-available \
--load-balancer-arns $LOAD_BALANCER_ARN \
--no-cli-pager

echo "New Load Balancer creation: COMPLETED."

LOAD_BALANCER_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerArn")
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --query "TargetGroups[*].TargetGroupArn")

echo "New Listener to Load Balancer creation: STARTED."

# Creating listener for load balancer
aws elbv2 create-listener \
--load-balancer-arn $LOAD_BALANCER_ARN \
--protocol HTTP \
--port 80 \
--default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
--no-cli-pager

# Waiting for load balancer to be available.
aws elbv2 wait load-balancer-available \
--load-balancer-arns $LOAD_BALANCER_ARN \
--no-cli-pager

echo "New Listener to Load Balancer creation: COMPLETED."

# Create launch configuration
aws autoscaling create-launch-configuration \
--launch-configuration-name $LAUNCH_CONFIG_NAME \
--image-id $IMAGE_ID \
--instance-type $INSTANCE_TYPE \
--key-name $KEY_NAME \
--security-groups $SECURITY_GROUP_IDS \
--iam-instance-profile $IAM_INSTANCE_PROFILE \
--no-cli-pager   \
--user-data file://install-env.sh 

echo "New Launch Configuration creation: COMPLETED."

# Create auto scaling group
aws autoscaling create-auto-scaling-group \
--auto-scaling-group-name $AUTO_SCALING_GRP \
--launch-configuration-name $LAUNCH_CONFIG_NAME \
--min-size $MIN_SIZE \
--max-size $MAX_SIZE \
--desired-capacity $DESIRED_CAPACITY \
--target-group-arns $TARGET_GROUP_ARN \
--health-check-type ELB \
--health-check-grace-period 600 \
--vpc-zone-identifier "${SUBNET_ID_ARRAY[0]}, ${SUBNET_ID_ARRAY[1]}" \
--no-cli-pager

echo "New Autoscaling Group creation: COMPLETED."

# Create DB instance
aws rds create-db-instance \
--db-instance-identifier $MYDBINSTANCE \
--db-instance-class db.t3.micro \
--engine $DB_ENGINE \
--master-username $USERVALUE \
--master-user-password $PASSVALUE \
--allocated-storage 20 \
--vpc-security-group-ids $SECURITY_GROUP_IDS \
--no-cli-pager

aws rds wait db-instance-available \
--db-instance-identifier $MYDBINSTANCE  \
--no-cli-pager
echo "New DB instance creation: COMPLETED."

# Create DB instance replica
aws rds create-db-instance-read-replica \
--db-instance-identifier "$MYDBINSREPLICA-rpl" \
--source-db-instance-identifier $MYDBINSTANCE \
--no-cli-pager

echo "New DB instance replica creation: COMPLETED."

# Fetching RDS address
RDS_Address=$(aws rds describe-db-instances --db-instance-identifier $MYDBINSTANCE --query "DBInstances[*].Endpoint.Address")

sudo mysql --user $USERVALUE --password=$PASSVALUE --host $RDS_Address < create.sql

# Create S3 Raw buckets
aws s3api create-bucket \
--bucket $S3_RAW_BUCKET_NAME \
--region us-east-1 \
--no-cli-pager 
    
aws s3api create-bucket \
--bucket $S3_FINISHED_BUCKET_NAME \
--region us-east-1 \
--no-cli-pager

aws s3api wait bucket-exists \
--bucket $S3_RAW_BUCKET_NAME \
--no-cli-pager
aws s3api wait bucket-exists \
--bucket $S3_FINISHED_BUCKET_NAME \
--no-cli-pager
echo "New S3 buckets creation: COMPLETED"


echo "New SNS topic created: STARTED"
aws sns create-topic \
--name $SNS_TOPIC \
--no-cli-pager
echo "New SNS topic created: COMPLETED"

TOPIC_ARN=$(aws sns list-topics --query 'Topics[*].TopicArn')

aws sns subscribe \
    --topic-arn $TOPIC_ARN \
    --protocol email \
    --notification-endpoint vsanil1@hawk.iit.edu\
    --no-cli-pager

# Retrieving ELBV2 URL
ELBV2_URL=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].DNSName")
echo $ELBV2_URL