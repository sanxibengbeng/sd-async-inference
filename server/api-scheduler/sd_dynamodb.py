import boto3
import os
import json
from datetime import datetime

table_name = 'sd_tasks'
# 替换为您的cloudfront host 需要配置好s3回援
os.environ['AWS_DEFAULT_REGION'] = 'ap-southeast-1'

def finishTask(taskId, processRes):
    dynamodb = boto3.client('dynamodb')
    response = dynamodb.update_item(
        TableName=table_name,
        Key={ 'taskId': {'S': taskId} },
        UpdateExpression="SET taskStatus = :val1, processRes = :val2, processTime = :val3",
        ExpressionAttributeValues={
            ':val1': {'S': 'finished'},
            ':val2': {'S': json.dumps(processRes)},
            ':val3': {'S': datetime.now().isoformat()},
        },
        ReturnValues="UPDATED_NEW"  # 返回更新后的值
    )
    return response
def getTask(taskId):
    # 初始化DynamoDB客户端
    dynamodb = boto3.client('dynamodb')
    res = {}

    try :
        response = dynamodb.get_item(
            TableName=table_name,
            Key={
                'taskId': {'S': taskId}
            }
        )
        item = response.get('Item')
        print(f"got item [{item}]")
        if item is None:
            res = {
                "errno":404,
                "error": f"no data by key [{taskId}]"
            }
        else :
            res = {
                "errno":200,
                "taskId": item['taskId']['S'],
                "requestData":  item['requestData']['S']
            }
    except Exception as e:
        res = {
            "errno":500,
            "error": f"e"
        }
    return res
    

# 使用方法
if __name__ == "__main__":
    res = getTask("e0185dde-3814-4ce5-9c22-c9a318d19e0b")
    print(f"got info {res}")
    res = getTask("abc")
    print(f"got info {res}")