import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as path from 'path';

export class SdInferenceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique ID for this deployment
    const deploymentId = cdk.Names.uniqueId(this).toLowerCase().substring(0, 8);
    
    // Create DynamoDB table with unique name
    const tasksTable = new dynamodb.Table(this, 'SdTasksTable', {
      tableName: `sd-tasks-${deploymentId}`,
      partitionKey: {
        name: 'taskId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // NOT recommended for production
    });

    // Create SQS Queue with unique name
    const taskQueue = new sqs.Queue(this, 'SdTaskQueue', {
      queueName: `sd-task-queue-${deploymentId}`,
      visibilityTimeout: cdk.Duration.seconds(300),
    });

    // Create S3 Bucket for storing images with unique name
    const imageBucket = new s3.Bucket(this, 'SdImageBucket', {
      bucketName: `sd-images-${deploymentId}-${this.account.substring(0, 5)}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // NOT recommended for production
      autoDeleteObjects: true, // NOT recommended for production
      cors: [
        {
          allowedMethods: [
            s3.HttpMethods.GET,
            s3.HttpMethods.PUT,
            s3.HttpMethods.POST,
          ],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
        },
      ],
    });

    // Create CloudFront Distribution
    const distribution = new cloudfront.Distribution(this, 'SdImageDistribution', {
      defaultBehavior: {
        origin: new origins.S3BucketOrigin(imageBucket, {
          originAccessIdentity: new cloudfront.OriginAccessIdentity(this, 'SdImageOAI')
        }),
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
    });

    // Create combined Lambda function for task handling
    const taskHandlerLambda = new lambda.Function(this, 'TaskHandlerFunction', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../server/lambda/task_handler')),
      timeout: cdk.Duration.seconds(30),
      environment: {
        DYNAMODB_TABLE: tasksTable.tableName,
        QUEUE_URL: taskQueue.queueUrl,
        CLOUDFRONT_DOMAIN: distribution.distributionDomainName,
      },
    });

    // Grant permissions
    tasksTable.grantReadWriteData(taskHandlerLambda);
    taskQueue.grantSendMessages(taskHandlerLambda);
    imageBucket.grantRead(taskHandlerLambda);

    // Create API Gateway with unique name
    const api = new apigateway.RestApi(this, 'SdApi', {
      restApiName: `sdapi-${deploymentId}`,
      description: 'Stable Diffusion API',
      deployOptions: {
        stageName: 'prod',
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
      },
    });

    // Create API resources and methods
    const taskResource = api.root.addResource('task');
    
    // POST /task - Submit task and GET /task - Get task info
    taskResource.addMethod('POST', new apigateway.LambdaIntegration(taskHandlerLambda));
    taskResource.addMethod('GET', new apigateway.LambdaIntegration(taskHandlerLambda));

    // Create IAM Role for EC2 instances with unique name
    const ec2Role = new iam.Role(this, 'SdInferenceEc2Role', {
      roleName: `sd-inference-ec2-role-${deploymentId}`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
    });

    // Add policies to the role
    ec2Role.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSQSFullAccess'));
    ec2Role.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonDynamoDBFullAccess'));
    ec2Role.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3FullAccess'));

    // Output important information
    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'URL of the API Gateway endpoint',
    });

    new cdk.CfnOutput(this, 'CloudFrontDomain', {
      value: distribution.distributionDomainName,
      description: 'CloudFront domain name for accessing images',
    });

    new cdk.CfnOutput(this, 'TaskQueueUrl', {
      value: taskQueue.queueUrl,
      description: 'URL of the SQS task queue',
    });

    new cdk.CfnOutput(this, 'ImageBucketName', {
      value: imageBucket.bucketName,
      description: 'Name of the S3 bucket for storing images',
    });

    new cdk.CfnOutput(this, 'Ec2RoleName', {
      value: ec2Role.roleName,
      description: 'Name of the IAM role for EC2 instances',
    });
  }
}
