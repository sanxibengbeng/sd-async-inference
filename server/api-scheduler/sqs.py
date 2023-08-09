import boto3
import os
import sd_api

def process_message(message_body):
    # 在这里添加处理消息的逻辑
    print("Processing:", message_body)
    raise Exception("test exception")

# test request {"api":"/sdapi/v1/txt2img","payload":{"prompt":"puppy dog","steps":5}}


def receiveAndProcess():

    # 你的 SQS 队列URL
    os.environ['AWS_DEFAULT_REGION'] = 'ap-southeast-1'
    queue_url = 'https://sqs.ap-southeast-1.amazonaws.com/873543029686/sd_task_queue'

    # 创建 SQS 客户端
    sqs = boto3.client('sqs')

    while True:
        # 从 SQS 获取消息
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=1,   # 调整为每次读取的消息数量
            WaitTimeSeconds=10        # 使用长轮询以等待消息到来
        )

        messages = response.get('Messages')
        if messages:
            for message in messages:
                try:
                    # 处理消息
                    process_message(message['Body'])
                    print(message)
                                  # 删除消息从队列中
                    sqs.delete_message(
                        QueueUrl=queue_url,
                        ReceiptHandle=message['ReceiptHandle']
                    )
                except Exception as e:
                    print("process message  error", e)
        else:
            print("No messages received. Waiting for next poll...")
        # todo test logic
        break;
if __name__ == "__main__":
    receiveAndProcess()