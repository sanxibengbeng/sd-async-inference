import boto3
import os

from scheduler.conf import schedulerConfig

os.environ['AWS_DEFAULT_REGION'] = schedulerConfig.get('aws', 'region')

bucket_name = schedulerConfig.get('aws', 'bucket_name')  # 替换为您的S3桶名
# 替换为您的cloudfront host 需要配置好s3回援
cloudfront = schedulerConfig.get('aws', 'cloudfront')

s3 = boto3.client('s3')

def put_object_to_s3(key, data, content_type):
    try:
        # Put the object
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=data,
            ContentType=content_type
        )
        print(f"Successfully put object {key} in bucket {bucket_name}.")
        uri = f"{cloudfront}{key}"
        return uri
    except Exception as e:
        print("put object exception", e)
        return False

def put_file_to_s3(file_name, bucket, object_name):
    # 如果S3 object_name未指定，则使用file_name作为默认值
    if object_name is None:
        object_name = file_name

    try:
        s3.upload_file(file_name, bucket, object_name)
        print(f"Upload successful: {file_name} to {bucket}/{object_name}")
        return True
    except FileNotFoundError:
        print(f"The file {file_name} was not found.")
        return False
    except NoCredentialsError:
        print("Credentials not available")
        return False
    except Exception as e:
        print("exception", e)
        return False



# 使用方法
if __name__ == "__main__":
    key = 'test/cute_girl.png'  # S3中对象的键名
    # 读取文件作为二进制数据
    with open('test_data/cute-girl.png', 'rb') as f:
        file_data = f.read()

    uri = put_object_to_s3(key, file_data, 'image/png')
    if uri != False:
        print("file upload res ", uri)
    else:
        print("file upload fail ", uri)