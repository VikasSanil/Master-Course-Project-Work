#!/bin/bash

LOAD_BALANCER_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerArn")
LISTENERS_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $LOAD_BALANCER_ARN --query "Listeners[*].ListenerArn")
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --query "TargetGroups[*].TargetGroupArn")
LAUNCH_CONFIG=$(aws autoscaling describe-launch-configurations --query "LaunchConfigurations[*].LaunchConfigurationName")
AUTO_SCALING_GRP=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[*].AutoScalingGroupName")
MYDBINSTANCE=$(aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" )
MYDBINSTANCE_ARRAY=($MYDBINSTANCE)
MYS3BUCKETS=$(aws s3api list-buckets --query "Buckets[*].Name")
MYS3BUCKETS_ARRAY=($MYS3BUCKETS)
SECRET_ID=$(aws secretsmanager list-secrets --query 'SecretList[*].ARN')

aws autoscaling update-auto-scaling-group --auto-scaling-group-name $AUTO_SCALING_GRP --min-size 0  --max-size 0 --desired-capacity 0 --no-cli-pager
aws ec2 wait instance-terminated 
echo "EC2 Instances terminated"
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $AUTO_SCALING_GRP
echo "Auto Scaling Group deleted"

aws autoscaling delete-launch-configuration --launch-configuration-name $LAUNCH_CONFIG
echo "Launch configuration deleted"

aws elbv2 delete-listener --listener-arn $LISTENERS_ARN
echo "Listener deleted"

aws elbv2 delete-load-balancer --load-balancer-arn $LOAD_BALANCER_ARN
echo "Load Balancer deleted"

aws elbv2 delete-target-group --target-group-arn $TARGET_GROUP_ARN
echo "Target Group deleted"

for i in "${MYDBINSTANCE_ARRAY[@]}"
do
aws rds delete-db-instance --db-instance-identifier $i --skip-final-snapshot --delete-automated-backups --no-cli-pager
aws rds wait db-instance-deleted --db-instance-identifier $i --no-cli-pager
done
echo "DB deleted"

for j in "${MYS3BUCKETS_ARRAY[@]}"
do
MYKEYS=$(aws s3api list-objects --bucket $j --query 'Contents[*].Key')
MYKEYS_ARRAY=($MYKEYS)
for k in "${MYKEYS_ARRAY[@]}"
do
aws s3api delete-object --bucket $j --key $k --no-cli-pager
aws s3api wait object-not-exists --bucket $j --key $k --no-cli-pager
done
done
echo "S3 Bucket Keys deleted"

for l in "${MYS3BUCKETS_ARRAY[@]}"
do
aws s3api delete-bucket --bucket $l --region us-east-1 --no-cli-pager
aws s3api wait bucket-not-exists --bucket $l --no-cli-pager
done
echo "S3 Bucket deleted"

aws secretsmanager delete-secret --secret-id $SECRET_ID
echo "secret deleted"