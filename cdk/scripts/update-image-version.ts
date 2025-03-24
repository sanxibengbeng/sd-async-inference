import * as AWS from 'aws-sdk';
import * as fs from 'fs';
import * as path from 'path';

// This script updates the image version in SSM Parameter Store and triggers an instance refresh

async function updateImageVersion() {
  // Get command line arguments
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: npm run update-image-version <deployment-id> <new-version>');
    process.exit(1);
  }

  const deploymentId = args[0];
  const newVersion = args[1];
  const region = process.env.AWS_REGION || 'us-east-1';

  console.log(`Updating image version for deployment ${deploymentId} to ${newVersion} in region ${region}`);

  // Initialize AWS SDK clients
  const ssm = new AWS.SSM({ region });
  const autoscaling = new AWS.AutoScaling({ region });

  try {
    // Update SSM parameter with new version
    const paramName = `/sd-inference/${deploymentId}/image-version`;
    await ssm.putParameter({
      Name: paramName,
      Value: newVersion,
      Type: 'String',
      Overwrite: true
    }).promise();
    
    console.log(`Updated SSM parameter ${paramName} to ${newVersion}`);

    // Get Auto Scaling Group name
    const asgName = `sd-inference-${deploymentId}`;
    
    // Start instance refresh
    const refreshResponse = await autoscaling.startInstanceRefresh({
      AutoScalingGroupName: asgName,
      Strategy: 'Rolling',
      Preferences: {
        MinHealthyPercentage: 90,
        InstanceWarmup: 300
      }
    }).promise();
    
    console.log(`Started instance refresh for ASG ${asgName}, RefreshId: ${refreshResponse.InstanceRefreshId}`);
    console.log('The new version will be gradually rolled out to all instances.');
    
  } catch (error) {
    console.error('Error updating image version:', error);
    process.exit(1);
  }
}

updateImageVersion();
