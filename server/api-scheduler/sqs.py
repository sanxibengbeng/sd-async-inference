import boto3
import os
import sd_api
import sd_task_detail
import sd_dynamodb

def process_message(message_body):
    print("Processing:", message_body)
    task = sd_task_detail.get(message_body)
    if task["errno"] != 200:
        raise Exception(task["error"])
    res = sd_api.process_sd_request(task["taskId"], task["requestData"])
    if res['error'] == '':
        sd_dynamodb.finishTask(task["taskId"], res)
    else:
        raise Exception(res['error'])

    

# test request {"api":"/sdapi/v1/txt2img","payload":{"prompt":"puppy dog","steps":5}}
# sqs message  { "storage": "dynamodb", "taskId": "e0185dde-3814-4ce5-9c22-c9a318d19e0b" }


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
                    #process_message(message['Body'])
                    # 从队列中 删除消息
                    sqs.delete_message(
                        QueueUrl=queue_url,
                        ReceiptHandle=message['ReceiptHandle']
                    )
                except Exception as e:
                    print("process message  error", e)
        else:
            print("No messages received. Waiting for next poll...")


if __name__ == "__main__":
    receiveAndProcess()
    #message = '{"storage": "dynamodb", "taskId": "e0185dde-3814-4ce5-9c22-c9a318d19e0b" }'
    #ret = process_message(message)
    #print(f"process ret [{ret}]")
