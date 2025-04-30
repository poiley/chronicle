import axios from 'axios';
import AWS from 'aws-sdk';

export default async function handler(req, res) {
  try {
    const apiUrl = process.env.LOCALSTACK_API_URL;
    const { method, query, body } = req;
    const path = query.path || '';
    
    // Configure AWS clients
    const awsConfig = {
      endpoint: apiUrl,
      region: 'us-east-1',
      accessKeyId: 'test',
      secretAccessKey: 'test'
    };
    
    // Handle job list request
    if (path === '/jobs') {
      const dynamoDB = new AWS.DynamoDB.DocumentClient(awsConfig);
      
      if (method === 'GET') {
        // List all jobs
        const result = await dynamoDB.scan({ TableName: 'jobs' }).promise();
        return res.status(200).json(result.Items || []);
      } 
      
      if (method === 'POST') {
        // Create new job
        const jobId = body.jobId;
        const date = new Date();
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const s3Key = `recordings/${year}/${month}/${day}/${body.filename}`;
        
        // Create job in DynamoDB
        const jobItem = {
          jobId: jobId,
          url: body.url,
          filename: body.filename,
          s3Key: s3Key,
          status: 'QUEUED',
          createdAt: new Date().toISOString()
        };
        
        await dynamoDB.put({
          TableName: 'jobs',
          Item: jobItem
        }).promise();
        
        // Send job to SQS
        const sqs = new AWS.SQS(awsConfig);
        
        await sqs.sendMessage({
          QueueUrl: `${apiUrl}/000000000000/yt-jobs.fifo`,
          MessageBody: JSON.stringify({
            jobId: jobId,
            url: body.url,
            filename: body.filename,
            s3Key: s3Key
          }),
          MessageGroupId: 'default'
        }).promise();
        
        return res.status(200).json(jobItem);
      }
    }
    
    // Handle single job request - matches paths like /jobs/123-456-789
    if (path.match(/^\/jobs\/[a-zA-Z0-9-]+$/)) {
      const jobId = path.split('/').pop();
      const dynamoDB = new AWS.DynamoDB.DocumentClient(awsConfig);
      
      const result = await dynamoDB.get({
        TableName: 'jobs',
        Key: { jobId }
      }).promise();
      
      if (result.Item) {
        return res.status(200).json(result.Item);
      } else {
        return res.status(404).json({ error: 'Job not found' });
      }
    }
    
    // Default proxy behavior for other endpoints
    const response = await axios({
      method,
      url: `${apiUrl}${path}`,
      params: Object.keys(query).filter(key => key !== 'path').reduce((obj, key) => {
        obj[key] = query[key];
        return obj;
      }, {}),
      data: body,
    });
    
    res.status(response.status).json(response.data);
  } catch (error) {
    console.error('API Proxy error:', error);
    res.status(error.response?.status || 500).json({
      error: error.message,
      details: error.response?.data,
    });
  }
}
