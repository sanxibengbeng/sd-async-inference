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
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as fs from 'fs';
import * as path from 'path';

export class SdInferenceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Extract the deployment ID from the stack name
    const stackName = cdk.Stack.of(this).stackName;
    const deploymentId = stackName.split('-').slice(-1)[0].toLowerCase();
    
    // Create DynamoDB table with unique name
    const tasksTable = new dynamodb.Table(this, 'SdTasksTable', {
      tableName: `sd-tasks-${deploymentId}`,
      partitionKey: {
        name: 'taskId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // NOT recommended for production
      pointInTimeRecoverySpecification: {
        pointInTimeRecoveryEnabled: true, // Enable point-in-time recovery for data protection
      },
    });

    // Add GSI for efficient queries by status
    tasksTable.addGlobalSecondaryIndex({
      indexName: 'status-index',
      partitionKey: {
        name: 'status',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'createdAt',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Create SQS Queue with unique name
    const deadLetterQueue = new sqs.Queue(this, 'SdTaskDeadLetterQueue', {
      queueName: `sd-task-dlq-${deploymentId}`,
      retentionPeriod: cdk.Duration.days(14), // Keep failed messages for 14 days
    });

    const taskQueue = new sqs.Queue(this, 'SdTaskQueue', {
      queueName: `sd-task-queue-${deploymentId}`,
      visibilityTimeout: cdk.Duration.seconds(600), // Increased timeout for processing
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3, // After 3 failed attempts, send to DLQ
      },
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
      encryption: s3.BucketEncryption.S3_MANAGED, // Enable server-side encryption
      versioned: true, // Enable versioning for recovery
      lifecycleRules: [
        {
          id: 'ExpireOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
          expiredObjectDeleteMarker: true,
        },
      ],
    });

    // Create CloudFront Distribution
    const oai = new cloudfront.OriginAccessIdentity(this, 'SdImageOAI');
    
    // Grant the OAI read access to the bucket
    imageBucket.grantRead(oai);
    
    // Create log bucket for CloudFront
    const cfLogBucket = new s3.Bucket(this, 'CloudFrontLogsBucket', {
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      objectOwnership: s3.ObjectOwnership.BUCKET_OWNER_PREFERRED, // Enable ACLs for CloudFront logs
      lifecycleRules: [
        {
          expiration: cdk.Duration.days(90),
        },
      ],
    });
    
    const distribution = new cloudfront.Distribution(this, 'SdImageDistribution', {
      defaultBehavior: {
        origin: new origins.HttpOrigin(`${imageBucket.bucketRegionalDomainName}`),
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
      enableLogging: true, // Enable access logs
      logBucket: cfLogBucket,
      logFilePrefix: 'cf-logs/',
    });

    // Create CloudWatch Log Group for Lambda
    const lambdaLogGroup = new logs.LogGroup(this, 'TaskHandlerLogGroup', {
      logGroupName: `/aws/lambda/sd-task-handler-${deploymentId}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create combined Lambda function for task handling
    const taskHandlerLambda = new lambda.Function(this, 'TaskHandlerFunction', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../server/lambda/task_handler')),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256, // Increased memory for better performance
      environment: {
        DYNAMODB_TABLE: tasksTable.tableName,
        QUEUE_URL: taskQueue.queueUrl,
        CLOUDFRONT_DOMAIN: distribution.distributionDomainName,
        DEPLOYMENT_ID: deploymentId,
      },
      logGroup: lambdaLogGroup,
      tracing: lambda.Tracing.ACTIVE, // Enable X-Ray tracing
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
        tracingEnabled: true, // Enable X-Ray tracing
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
        maxAge: cdk.Duration.seconds(300),
      },
    });

    // Create API resources and methods
    const taskResource = api.root.addResource('task');
    
    // POST /task - Submit task and GET /task - Get task info
    taskResource.addMethod('POST', new apigateway.LambdaIntegration(taskHandlerLambda));
    taskResource.addMethod('GET', new apigateway.LambdaIntegration(taskHandlerLambda));

    // Add health check endpoint
    const healthResource = api.root.addResource('health');
    healthResource.addMethod('GET', new apigateway.MockIntegration({
      integrationResponses: [
        {
          statusCode: '200',
          responseTemplates: {
            'application/json': '{"status": "healthy"}',
          },
        },
      ],
      passthroughBehavior: apigateway.PassthroughBehavior.NEVER,
      requestTemplates: {
        'application/json': '{"statusCode": 200}',
      },
    }), {
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL,
          },
        },
      ],
    });

    // Create IAM Role for EC2 instances with unique name
    const ec2Role = new iam.Role(this, 'SdInferenceEc2Role', {
      roleName: `sd-inference-ec2-role-${deploymentId}`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'), // For SSM Session Manager
      ],
    });

    // Add specific permissions instead of full access policies
    ec2Role.addToPolicy(new iam.PolicyStatement({
      actions: [
        'sqs:ReceiveMessage',
        'sqs:DeleteMessage',
        'sqs:GetQueueAttributes',
        'sqs:ChangeMessageVisibility',
      ],
      resources: [taskQueue.queueArn],
    }));

    ec2Role.addToPolicy(new iam.PolicyStatement({
      actions: [
        'dynamodb:GetItem',
        'dynamodb:UpdateItem',
        'dynamodb:PutItem',
      ],
      resources: [tasksTable.tableArn],
    }));

    ec2Role.addToPolicy(new iam.PolicyStatement({
      actions: [
        's3:PutObject',
        's3:GetObject',
      ],
      resources: [`${imageBucket.bucketArn}/*`],
    }));

    ec2Role.addToPolicy(new iam.PolicyStatement({
      actions: [
        'ec2:DescribeTags',
        'ec2:DescribeInstances',
        'autoscaling:SetInstanceHealth',
      ],
      resources: ['*'],
    }));

    ec2Role.addToPolicy(new iam.PolicyStatement({
      actions: [
        'ssm:GetParameter',
      ],
      resources: [
        `arn:aws:ssm:${this.region}:${this.account}:parameter/sd-inference/${deploymentId}/*`,
      ],
    }));

    ec2Role.addToPolicy(new iam.PolicyStatement({
      actions: [
        'ecr:GetAuthorizationToken',
        'ecr:BatchCheckLayerAvailability',
        'ecr:GetDownloadUrlForLayer',
        'ecr:BatchGetImage',
      ],
      resources: ['*'],
    }));

    // Create SSM Parameters for image version tracking
    const imageVersionParam = new ssm.StringParameter(this, 'ImageVersionParameter', {
      parameterName: `/sd-inference/${deploymentId}/image-version`,
      stringValue: '1.0.0', // Initial version
      description: 'Current version of the SD inference image',
      tier: ssm.ParameterTier.STANDARD,
    });
    
    // Parameter for tracking the previous stable version (for rollback)
    const previousVersionParam = new ssm.StringParameter(this, 'PreviousVersionParameter', {
      parameterName: `/sd-inference/${deploymentId}/previous-version`,
      stringValue: '1.0.0', // Initial version
      description: 'Previous stable version of the SD inference image',
      tier: ssm.ParameterTier.STANDARD,
    });
    
    // Parameter for deployment status tracking
    const deploymentStatusParam = new ssm.StringParameter(this, 'DeploymentStatusParameter', {
      parameterName: `/sd-inference/${deploymentId}/deployment-status`,
      stringValue: 'stable', // Initial status: stable, in-progress, rolling-back
      description: 'Current deployment status',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Create VPC for the EC2 instances
    const vpc = new ec2.Vpc(this, 'SdInferenceVpc', {
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
      gatewayEndpoints: {
        S3: {
          service: ec2.GatewayVpcEndpointAwsService.S3,
        },
      },
    });

    // Add VPC endpoints to reduce NAT gateway costs and improve security
    vpc.addInterfaceEndpoint('EcrDockerEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.ECR_DOCKER,
    });

    vpc.addInterfaceEndpoint('EcrApiEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.ECR,
    });

    vpc.addInterfaceEndpoint('CloudWatchLogsEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
    });

    vpc.addInterfaceEndpoint('SsmEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.SSM,
    });

    vpc.addInterfaceEndpoint('SqsEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.SQS,
    });

    // Create security group for the EC2 instances
    const securityGroup = new ec2.SecurityGroup(this, 'SdInferenceSecurityGroup', {
      vpc,
      description: 'Security group for SD inference instances',
      allowAllOutbound: true,
    });

    // Allow SSH access (for debugging purposes)
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access'
    );

    // Allow health check port
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(8080),
      'Allow health check access'
    );

    // Read user data script
    const userDataScript = fs.readFileSync(path.join(__dirname, 'user-data.sh'), 'utf8');
    
    // Create launch template
    const launchTemplate = new ec2.LaunchTemplate(this, 'SdInferenceLaunchTemplate', {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.G4DN, ec2.InstanceSize.XLARGE), // GPU instance for inference
      machineImage: ec2.MachineImage.latestAmazonLinux2({
        cpuType: ec2.AmazonLinuxCpuType.X86_64,
      }),
      userData: ec2.UserData.custom(userDataScript),
      securityGroup,
      role: ec2Role,
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(100, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            deleteOnTermination: true,
            encrypted: true, // Enable EBS encryption
          }),
        },
      ],
      detailedMonitoring: true,
      requireImdsv2: true, // Require IMDSv2 for improved security
    });

    // Create Auto Scaling Group
    const asg = new autoscaling.AutoScalingGroup(this, 'SdInferenceASG', {
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      launchTemplate,
      minCapacity: 1,
      maxCapacity: 10,
      desiredCapacity: 2,
      healthChecks: autoscaling.HealthChecks.ec2({
        gracePeriod: cdk.Duration.minutes(5),
      }),
      updatePolicy: autoscaling.UpdatePolicy.rollingUpdate({
        maxBatchSize: 1,
        minInstancesInService: 1,
        pauseTime: cdk.Duration.minutes(10),
        suspendProcesses: [
          autoscaling.ScalingProcess.ALARM_NOTIFICATION,
          autoscaling.ScalingProcess.SCHEDULED_ACTIONS,
        ],
        waitOnResourceSignals: true,
      }),
      signals: autoscaling.Signals.waitForAll({
        timeout: cdk.Duration.minutes(15),
      }),
      cooldown: cdk.Duration.seconds(300),
    });

    // Add tags to instances
    cdk.Tags.of(asg).add('DeploymentId', deploymentId);
    cdk.Tags.of(asg).add('Name', `sd-inference-${deploymentId}`);
    cdk.Tags.of(asg).add('Service', 'StableDiffusion');
    cdk.Tags.of(asg).add('Environment', deploymentId);

    // Add scaling policies based on SQS queue metrics
    asg.scaleOnMetric('ScaleOnQueueDepth', {
      metric: taskQueue.metricApproximateNumberOfMessagesVisible({
        period: cdk.Duration.minutes(1),
        statistic: 'Average',
      }),
      scalingSteps: [
        { upper: 10, change: 0 },
        { lower: 10, upper: 50, change: 1 },
        { lower: 50, upper: 100, change: 2 },
        { lower: 100, change: 3 },
      ],
      adjustmentType: autoscaling.AdjustmentType.CHANGE_IN_CAPACITY,
      estimatedInstanceWarmup: cdk.Duration.minutes(5),
    });

    // Scale in when queue is empty
    asg.scaleOnMetric('ScaleInOnEmptyQueue', {
      metric: taskQueue.metricApproximateNumberOfMessagesVisible({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      scalingSteps: [
        { upper: 1, change: -1 },
        { lower: 1, change: 0 },
      ],
      adjustmentType: autoscaling.AdjustmentType.CHANGE_IN_CAPACITY,
      cooldown: cdk.Duration.minutes(10),
    });

    // Add CPU utilization based scaling
    asg.scaleOnCpuUtilization('ScaleOnCpuUtilization', {
      targetUtilizationPercent: 70,
      cooldown: cdk.Duration.minutes(5),
    });

    // Create CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'SdInferenceDashboard', {
      dashboardName: `sd-inference-${deploymentId}`,
    });

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'SQS Queue Metrics',
        left: [
          taskQueue.metricApproximateNumberOfMessagesVisible(),
          taskQueue.metricApproximateNumberOfMessagesNotVisible(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'ASG Instance Count',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/AutoScaling',
            metricName: 'GroupInServiceInstances',
            dimensionsMap: {
              AutoScalingGroupName: asg.autoScalingGroupName,
            },
            statistic: 'Average',
          }),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'CPU Utilization',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'CPUUtilization',
            dimensionsMap: {
              AutoScalingGroupName: asg.autoScalingGroupName,
            },
            statistic: 'Average',
          }),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Memory Utilization',
        left: [
          new cloudwatch.Metric({
            namespace: 'CWAgent',
            metricName: 'mem_used_percent',
            dimensionsMap: {
              AutoScalingGroupName: asg.autoScalingGroupName,
            },
            statistic: 'Average',
          }),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'API Gateway Requests',
        left: [
          api.metricCount(),
          api.metricLatency(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Errors',
        left: [
          taskHandlerLambda.metricErrors(),
        ],
        width: 12,
      }),
    );

    // Create CloudWatch Alarms
    const queueDepthAlarm = new cloudwatch.Alarm(this, 'QueueDepthAlarm', {
      metric: taskQueue.metricApproximateNumberOfMessagesVisible({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 100,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'Alarm if queue depth is too high for too long',
    });

    const deadLetterQueueAlarm = new cloudwatch.Alarm(this, 'DeadLetterQueueAlarm', {
      metric: deadLetterQueue.metricApproximateNumberOfMessagesVisible({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      alarmDescription: 'Alarm if any messages appear in the dead letter queue',
    });

    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      metric: taskHandlerLambda.metricErrors({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'Alarm if Lambda has too many errors',
    });

    // Output important information
    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'URL of the API Gateway endpoint',
      exportName: `${deploymentId}-ApiGatewayUrl`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDomain', {
      value: distribution.distributionDomainName,
      description: 'CloudFront domain name for accessing images',
      exportName: `${deploymentId}-CloudFrontDomain`,
    });

    new cdk.CfnOutput(this, 'TaskQueueUrl', {
      value: taskQueue.queueUrl,
      description: 'URL of the SQS task queue',
      exportName: `${deploymentId}-TaskQueueUrl`,
    });

    new cdk.CfnOutput(this, 'ImageBucketName', {
      value: imageBucket.bucketName,
      description: 'Name of the S3 bucket for storing images',
      exportName: `${deploymentId}-ImageBucketName`,
    });

    new cdk.CfnOutput(this, 'Ec2RoleName', {
      value: ec2Role.roleName,
      description: 'Name of the IAM role for EC2 instances',
      exportName: `${deploymentId}-Ec2RoleName`,
    });
    
    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      value: asg.autoScalingGroupName,
      description: 'Name of the Auto Scaling Group',
      exportName: `${deploymentId}-AutoScalingGroupName`,
    });
    
    // 避免重复的构造ID
    new cdk.CfnOutput(this, 'SSMImageVersionParam', {
      value: imageVersionParam.parameterName,
      description: 'SSM Parameter name for image version tracking',
      exportName: `${deploymentId}-ImageVersionParameter`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL of the CloudWatch Dashboard',
      exportName: `${deploymentId}-DashboardUrl`,
    });
  }
}
