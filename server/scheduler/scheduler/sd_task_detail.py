import json
import scheduler.sd_dynamodb

def get(message):
    info = json.loads(message)
    dbRet = None
    # storage 如果是dynamodb 从dynamodb获取数据
    if info["storage"] == "dynamodb":
        dbRet = sd_dynamodb.getTask(info["taskId"])

    return dbRet

if __name__ == "__main__":
    message = '{"storage": "dynamodb", "taskId": "e0185dde-3814-4ce5-9c22-c9a318d19e0b" }'
    dbRet = get(message)
    print(f"got detail[{dbRet}]")