#takes data from my webpage and adds it to the database
from datetime import datetime, timedelta
import json
import boto3
import os
import uuid

dynamodb = boto3.resource('dynamodb')
sns_client = boto3.client('sns')
table = dynamodb.Table(os.environ.get('TABLE_NAME'))
table_name = os.environ.get('TABLE_NAME')
topic_arn = os.environ.get('SNS_TOPIC_ARN')

def lambda_handler(event, context):
    try:
        #determines if post, get or delete
        method = event.get('requestContext', {}).get('http', {}).get('method')

        #cors
        headers = {
            'access-control-allow-origin': '*',
            'access-control-allow-methods': 'OPTIONS,POST,GET,DELETE',
            'access-control-allow-headers': 'Content-Type'
        }
        if method == 'POST':
            body = json.loads(event['body'])
            task_id = str(uuid.uuid4())
            due_date_str = body.get('due_date')
            user_email = body.get('user_email')
            if user_email and topic_arn:
                filter_policy = json.dumps({"email": [user_email]})
                #subscribe the user to the SNS topic
                sns_client.subscribe(
                    TopicArn=topic_arn,
                    Protocol='email',
                    Endpoint=user_email,
                    Attributes={'FilterPolicy': filter_policy}
                )

             #calculate expiry time after 24 hours of due date
            expiration_time = None
            if due_date_str:
                due_date = datetime.strptime(due_date_str, '%Y-%m-%d')
                expire_obj = due_date + timedelta(days=1)
                expiration_time = int((due_date + timedelta(days=1)).timestamp())
                
            task_item = {
                'task_id': task_id,
                'task_name': body['task_name'],
                'task_description': body.get('task_description'),
                'due_date': body.get('due_date'),
                'expiry': expiration_time,
                'user_email': user_email
            }
            table.put_item(Item=task_item)
            return {'statusCode': 200, 'body': json.dumps({'message': 'Task added', 'task_id': task_id}), 'headers': headers}
        
        elif method == 'GET':
            response = table.scan()
            tasks = response.get('Items', [])
            tasks.sort(key=lambda x: x.get('due_date', '9999-12-31'))  # Sort by due_date, default to a far future date if missing
            return {'statusCode': 200, 'body': json.dumps(tasks), 'headers': headers}

        elif method == 'DELETE':
            task_id = event.get('pathParameters', {}).get('task_id')
            if task_id:
                table.delete_item(Key={'task_id': task_id})
                return {'statusCode': 200, 'body': json.dumps({'message': 'Task deleted'}), 'headers': headers}
            else:
                return {'statusCode': 400, 'body': json.dumps({'message': 'Cant delete, missing task!'}), 'headers': headers}

        else:
            return {'statusCode': 400, 'body': json.dumps({'message': 'Invalid request method'}), 'headers': headers}

    except Exception as e:
        print(f"Error occurred: {str(e)}")
        return {
        'statusCode': 500, 'body': str(e), 'headers': headers}