import boto3
import json
import os

dynamodb = boto3.resource('dynamodb')
iam = boto3.client('iam')
sns = boto3.client('sns')

# Environment Variables
TABLE_NAME = os.environ['DYNAMODB_TABLE_NAME']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
ACCOUNT_ID = os.environ['ACCOUNT_ID']

# DynamoDB Table Reference
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    # Fetch all IAM roles
    response = iam.list_roles()
    roles = response['Roles']
    
    print(f"Found {len(roles)} roles")
    
    # Process each role to check if it has an external principal
    for role in roles:
        role_name = role['RoleName']
        assume_role_policy = role.get('AssumeRolePolicyDocument', {})
        
        for statement in assume_role_policy.get('Statement', []):
            if statement['Effect'] == 'Allow' and 'Principal' in statement:
                principal = statement['Principal']
                
                # Check if the principal is an external account
                if 'AWS' in principal:
                    external_account = principal['AWS']
                    
                    if isinstance(external_account, list):
                        for account in external_account:
                            process_external_account(role_name, account)
                    else:
                        process_external_account(role_name, external_account)

def process_external_account(role_name, external_account):
    print(f"Processing external account: {external_account} for role: {role_name}")
    
    # Query DynamoDB to check if this external account is known
    response = table.get_item(
        Key={
            'RoleName': role_name,
            'Principal': external_account
        }
    )
    
    if 'Item' not in response:
        print(f"Unknown external account detected: {external_account} for role: {role_name}")
        send_alert(role_name, external_account)
        table.put_item(
            Item={
                'RoleName': role_name,
                'Principal': external_account
            }
        )
    else:
        print(f"External account already known: {external_account} for role: {role_name}")


def send_alert(role_name, external_account):
    message = (f"New externally assumable role detected!\n"
               f"Role: {role_name}\n"
               f"External Account: {external_account}")
    
    try:
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=message,
            Subject="New Externally Assumable Role Alert"
        )
        print(f"Alert sent for role: {role_name} and external account: {external_account}")
        print(f"SNS Response: {response}")
    except Exception as e:
        print(f"Failed to send alert: {str(e)}")
