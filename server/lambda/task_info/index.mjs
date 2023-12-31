// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0
import { DynamoDBClient, GetItemCommand } from "@aws-sdk/client-dynamodb";

// const DEFAULT_REGION = "ap-northeast-1";
const TABLE_NAME = process.env.DYNAMODB_TABLE || 'sd_tasks';

const queryDynamoDb = async (taskId) => {
  const client = new DynamoDBClient();
  const params = {
    Key: { taskId: { S: taskId } },
    TableName: TABLE_NAME,
  };
  const command = new GetItemCommand(params);
  console.log("query command", command)
  try {
    const results = await client.send(command);
    console.log(results);
    if (!results.Item) {
      return null;
    } else {
      console.log(results.Item);
      return results.Item;
    }
  } catch (err) {
    console.error(err);
    return null;
  }
};

export const handler = async (event) => {
  //query user in DB
  const taskId = event.queryStringParameters.taskId
  let taskInfo = await queryDynamoDb(taskId);

  let response = {}
  if (!taskInfo) {
    response = {
      statusCode: 404,
      body: "no valid task"
    }
  } else {
    response = {
      statusCode: 200,
      body: JSON.stringify(taskInfo)
    }
  }
  return response
};