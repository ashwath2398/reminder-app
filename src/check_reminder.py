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

        #check for 7 days
        today = datetime.now()
        today_str = today.strftime('%Y-%m-%d')
        target_date = (today + timedelta(days=7)).strftime('%Y-%m-%d')

        response = table.scan()
        tasks = response.get('Items', [])
        
        email_groups = {}
        
        for task in tasks:
            due_date = task.get('due_date')
            user_email = task.get('user_email')
            
            if due_date and user_email and today_str <= due_date <= target_date:
                
                task_msg = f"Reminder: '{task.get('task_name', 'Unnamed task')}' is due on {due_date}."

                #if new id then create new list for that email
                if user_email not in email_groups:
                    email_groups[user_email] = []
                email_groups[user_email].append(task_msg)

        emails_sent = 0
        #if single mail has multiple reminders then send them in one mail
        for email, user_reminders in email_groups.items():
            message_body = "Upcoming Tasks:\n\n" + "\n".join(user_reminders)
            subject = "Task Reminder"
            
            sns_client.publish(
                TopicArn=topic_arn,
                Message=message_body, 
                Subject=subject,
                MessageAttributes={
                    'email': {
                        'DataType': 'String',
                        'StringValue': email
                    }
                }
            )
            emails_sent += 1
            
       
        if emails_sent > 0:
            return {"statusCode": 200, "body": f"Sent {emails_sent} reminder emails."}
        else:
            return {"statusCode": 200, "body": "No reminders to send."}

    except Exception as e:
        print(f"Error occurred: {str(e)}")
        return {"statusCode": 500, "body": str(e)}