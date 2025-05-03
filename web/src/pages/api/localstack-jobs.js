import AWS from 'aws-sdk';

// Configure AWS to use LocalStack
const awsConfig = {
  region: 'us-west-1',
  accessKeyId: 'test',
  secretAccessKey: 'test',
  endpoint: process.env.NODE_ENV === 'production' 
    ? undefined 
    : 'http://chronicle-localstack:4566'
};

// Handler for API routes
export default async function handler(req, res) {
  // Set CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  // Handle OPTIONS requests for CORS preflight
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  // Create AWS service clients
  const dynamoDB = new AWS.DynamoDB.DocumentClient(awsConfig);
  const sqs = new AWS.SQS(awsConfig);
  
  try {
    // GET request - List all jobs
    if (req.method === 'GET') {
      console.log('Scanning DynamoDB table: jobs');
      
      const result = await dynamoDB.scan({
        TableName: 'jobs'
      }).promise();
      
      console.log(`Successfully retrieved ${result.Items?.length || 0} jobs`);
      return res.status(200).json(result.Items || []);
    }
    
    // POST request - Create a new job
    if (req.method === 'POST') {
      const { jobId, url, filename } = req.body;
      
      if (!jobId || !url || !filename) {
        return res.status(400).json({ 
          error: 'Missing required fields', 
          required: ['jobId', 'url', 'filename'] 
        });
      }
      
      console.log(`Creating new job: ${jobId} for URL: ${url}`);
      
      // Generate S3 key with date-based path
      const date = new Date();
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      const s3Key = `recordings/${year}/${month}/${day}/${filename}`;
      
      // Create job in DynamoDB
      const jobItem = {
        jobId,
        url,
        filename,
        s3Key,
        status: 'PENDING',
        createdAt: date.toISOString(),
        progress: 0
      };
      
      await dynamoDB.put({
        TableName: 'jobs',
        Item: jobItem
      }).promise();
      
      // Add to SQS queue
      try {
        await sqs.sendMessage({
          QueueUrl: `${awsConfig.endpoint}/000000000000/chronicle-jobs.fifo`,
          MessageBody: JSON.stringify({
            jobId,
            url,
            filename,
            s3Key
          }),
          MessageGroupId: 'default'
        }).promise();
        console.log(`Job ${jobId} added to SQS queue`);
      } catch (sqsError) {
        console.warn(`Could not add to SQS queue: ${sqsError.message}`);
        // Continue anyway since the job is in DynamoDB
      }
      
      return res.status(201).json(jobItem);
    }
    
    // If we get here, it's an unsupported method
    return res.status(405).json({ error: 'Method not allowed' });
  } catch (error) {
    console.error('API error:', error);
    return res.status(500).json({ 
      error: 'Failed to process request',
      message: error.message,
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
} 