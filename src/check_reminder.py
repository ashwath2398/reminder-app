#check tasks due in exactly 7 days
import boto3
import os
from datetime import datetime, timedelta

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME')
table = dynamodb.Table(table_name)
sns_client = boto3.client('sns')
topic_arn = os.environ.get('SNS_TOPIC_ARN')

def lambda_handler(event, context):
    try:
        # Calculate the date 7 days from now
        target_date = (datetime.now() + timedelta(days=7)).strftime('%Y-%m-%d')

        #fetch tasks due in exactly 7 days
        response = table.scan()
        tasks = response.get('Items', [])

        reminders = []
        for task in tasks:
            if task.get('due_date') == target_date:
                message = f"Reminder: '{task['task_name']}' is due on {task['due_date']}."

                sns_client.publish(
                    TopicArn=topic_arn,
                    Subject='Task Reminder',
                    Message=message
                )
                reminders.append(message)
    except Exception as e:
        print(f"Error occurred: {str(e)}")
        return {"statusCode": 500, "body": str(e)}