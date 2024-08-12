# Reporting and Alerting System Deployment and Testing Guide

## Before You Begin
- Edit line 117 of the configuration file to add your email address to receive SNS notifications.

## How to Deploy Terraform

1. **Initialize Terraform**:
    ```bash
    terraform init
    ```

2. **Plan the Deployment**:
    ```bash
    terraform plan
    ```

3. **Apply the Configuration**:
    ```bash
    terraform apply
    ```

## Steps to Perform the Test

1. **Create a Test IAM Role**:
    - Use the AWS CLI to create a test IAM role. This action will trigger the CloudWatch Event Rule, which should invoke the Lambda function.
    - Command:
      ```bash
      aws iam create-role --role-name TestAssumableRole --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
          {
              "Effect": "Allow",
              "Principal": {
                  "AWS": "arn:aws:iam::123456789012:root"  # Replace with an account ID other than your own
              },
              "Action": "sts:AssumeRole"
          }
      ]
      }'
      ```

2. **Verify Lambda Execution**:
    - **Check Lambda Logs**:
        - Use AWS CloudWatch Logs to verify if the Lambda function executed successfully.
        - Commands:
          ```bash
          aws logs describe-log-groups
          aws logs describe-log-streams --log-group-name "/aws/lambda/AssumableRoleChecker"
          aws logs get-log-events --log-group-name "/aws/lambda/AssumableRoleChecker" --log-stream-name "<LogStreamName>"
          ```
        - Look for logs indicating that the Lambda function processed the new IAM role.
    
    - **Verify DynamoDB Entry**:
        - Use the AWS CLI to check if the role data has been added to DynamoDB.
        - Command:
          ```bash
          aws dynamodb scan --table-name ExternallyAssumableRoles
          ```
        - Ensure that you see the test role in the results.

    - **Check SNS Notifications**:
        - After subscribing, create a test IAM role (or use the role you created earlier) and verify that you receive an email or SMS notification about the new externally assumable role.

3. **Clean Up**:
    - **Delete Test IAM Role**:
        - After testing, you may want to delete the test role to clean up your environment.
        - Command:
          ```bash
          aws iam delete-role --role-name TestAssumableRole
          ```
    
    - **Remove SNS Subscription**:
        - If you subscribed to SNS via email or SMS for testing, you can unsubscribe.
        - Commands:
          ```bash
          aws sns list-subscriptions
          aws sns unsubscribe --subscription-arn <SubscriptionARN>
          ```
    
    - **Clean Up DynamoDB Entries**:
        - Optionally, clean up the DynamoDB table if necessary.
        - Command:
          ```bash
          aws dynamodb scan --table-name ExternallyAssumableRoles
          ```

## Verification Checklist

- **IAM Role Creation**: Confirm that creating a new IAM role triggers the CloudWatch Event Rule and invokes the Lambda function.
- **Lambda Execution**: Check Lambda logs to verify that the IAM role was processed and that data was correctly added to DynamoDB.
- **DynamoDB Data**: Ensure that the test role's information is present in the DynamoDB table.
- **SNS Notification**: Confirm receipt of the SNS notification if the role is externally assumable.

## Summary

By following this automated test scenario, you can ensure that the entire setup—from role creation detection to processing and notification—is functioning as expected. This will help validate that the reporting and alerting system is working correctly and efficiently.

