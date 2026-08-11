#takes data from my webpage and adds it to the database
import json
import boto3
import os
import uuid

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('task-table')

def lambda_handler(event, context):
    try:
        # Parse the incoming request body
        body = json.loads(event['body'])
    
        # Generate a unique task ID
        task_id = str(uuid.uuid4())
    
        # Create a new task item
        task_item = {
        'task_id': task_id,
        'task_name': body['task_name'],
        'task_description': body['task_description'],
        'due_date': body['due_date'],
        }
    
        # Add the new task to the DynamoDB table

        table = dynamodb.Table(task-table)
        table.put_item(Item=task_item)
    
        # Return a success response
        return {
        'statusCode': 200,
        'headers': {
            'access-control-allow-origin': '*',
            'access-control-allow-methods': 'OPTIONS,POST',
            'access-control-allow-headers': 'Content-Type'
        },
        'body': json.dumps({'message': 'Task added successfully', 'task_id': task_id})
        }
    except Exception as e:
        return {
        'statusCode': 500, 'body': str(e)}