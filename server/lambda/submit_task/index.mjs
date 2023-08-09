import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb"; // ES Modules import
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs"; // ES Modules import

import { v4 as uuidv4 } from 'uuid';

const docClient = new DynamoDBClient();
const sqs= new SQSClient();

export const handler = async (event) => {
    // get conf from env
    let queueUrl = process.env.QUEUE_URL;
    let tableName =  process.env.DYNAMODB_TABLE || 'sd_tasks';

    // taskId generated
    let taskId = uuidv4();
    console.log("taskId", taskId);

    let dbParams = {
        TableName: tableName, 
        Item: {
            'taskId': { S: taskId },
            'requestData': { S: event.body },
            'status': { S: 'waiting' },
            'timestamp': { S: new Date().toISOString() }
        }
    };

    taskInfo = {
        taskId: taskId,
        storage: "dynamodb"
    }
    let sqsParams = {
        MessageBody: JSON.stringify(taskInfo),
        QueueUrl: queueUrl
    };

    let response;
    try{
        // write data to dynamodb
        const dbCommand = new PutItemCommand(dbParams);
        const dbRes = await docClient.send(dbCommand)
        console.log(dbRes)

        const sqsCommand = new SendMessageCommand(sqsParams);
        const sqsRes = await sqs.send(sqsCommand);
        console.log(sqsRes)

        response = {
            statusCode: 200,
            taskId: taskId
        };
    }catch(err){
        console.error(err)
        response = {
            statusCode: 500,
         };
    }
    return response;
};