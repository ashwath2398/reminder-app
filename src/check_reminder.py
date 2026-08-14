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
        # 7 days to expire
        today = datetime.now()
        today_str = today.strftime('%Y-%m-%d')
        target_date = (today + timedelta(days=7)).strftime('%Y-%m-%d')

        #fetch tasks due in exactly 7 days
        response = table.scan()
        tasks = response.get('Items', [])

        reminders = []
        for task in tasks:
            due_date = task.get('due_date')
            if due_date and today_str < due_date <= target_date:
                message = f"Reminder: '{task['task_name']}' is due on {due_date}."
                sns_client.publish(TopicArn=topic_arn, Subject='Task Reminder', Message=message)
                reminders.append(task)
                return {
                    'statusCode': 200,
                    'body': f"Sent reminders for {len(reminders)} tasks."
                }
    except Exception as e:
        print(f"Error occurred: {str(e)}")
        return {"statusCode": 500, "body": str(e)}