import { DynamoDBClient, PutItemCommand, GetItemCommand } from "@aws-sdk/client-dynamodb";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { v4 as uuidv4 } from 'uuid';

// 初始化客户端
const dynamoClient = new DynamoDBClient();
const sqsClient = new SQSClient();

// 从环境变量获取配置
const TABLE_NAME = process.env.DYNAMODB_TABLE || 'sd_tasks';
const QUEUE_URL = process.env.QUEUE_URL;

/**
 * 提交新任务
 * @param {Object} event - API Gateway 事件对象
 * @returns {Object} - 包含任务ID的响应
 */
const submitTask = async (event) => {
  try {
    // 生成任务ID
    const taskId = uuidv4();
    console.log("生成任务ID:", taskId);

    // 准备DynamoDB参数
    const dbParams = {
      TableName: TABLE_NAME,
      Item: {
        'taskId': { S: taskId },
        'requestData': { S: event.body },
        'taskStatus': { S: 'waiting' },
        'submitTime': { S: new Date().toISOString() }
      }
    };

    // 准备SQS参数
    const taskInfo = {
      taskId: taskId,
      storage: "dynamodb"
    };
    
    const sqsParams = {
      MessageBody: JSON.stringify(taskInfo),
      QueueUrl: QUEUE_URL
    };

    // 写入DynamoDB
    const dbCommand = new PutItemCommand(dbParams);
    await dynamoClient.send(dbCommand);

    // 发送到SQS
    const sqsCommand = new SendMessageCommand(sqsParams);
    await sqsClient.send(sqsCommand);

    // 返回成功响应
    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      },
      body: JSON.stringify({ taskId: taskId })
    };
  } catch (error) {
    console.error("提交任务失败:", error);
    return {
      statusCode: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      },
      body: JSON.stringify({ error: "提交任务失败", message: error.message })
    };
  }
};

/**
 * 查询任务信息
 * @param {Object} event - API Gateway 事件对象
 * @returns {Object} - 包含任务信息的响应
 */
const getTaskInfo = async (event) => {
  try {
    const taskId = event.queryStringParameters?.taskId;
    
    if (!taskId) {
      return {
        statusCode: 400,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        body: JSON.stringify({ error: "缺少taskId参数" })
      };
    }

    // 查询DynamoDB
    const params = {
      Key: { taskId: { S: taskId } },
      TableName: TABLE_NAME,
    };
    
    const command = new GetItemCommand(params);
    const result = await dynamoClient.send(command);

    if (!result.Item) {
      return {
        statusCode: 404,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        body: JSON.stringify({ error: "任务不存在" })
      };
    }

    // 返回任务信息
    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      },
      body: JSON.stringify(result.Item)
    };
  } catch (error) {
    console.error("查询任务失败:", error);
    return {
      statusCode: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      },
      body: JSON.stringify({ error: "查询任务失败", message: error.message })
    };
  }
};

/**
 * Lambda 处理函数
 * @param {Object} event - API Gateway 事件对象
 * @returns {Object} - API Gateway 响应对象
 */
export const handler = async (event) => {
  console.log("接收到请求:", JSON.stringify(event));
  
  // 根据HTTP方法路由到不同的处理函数
  if (event.httpMethod === 'POST') {
    return await submitTask(event);
  } else if (event.httpMethod === 'GET') {
    return await getTaskInfo(event);
  } else {
    // 不支持的HTTP方法
    return {
      statusCode: 405,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      },
      body: JSON.stringify({ error: "方法不允许" })
    };
  }
};
