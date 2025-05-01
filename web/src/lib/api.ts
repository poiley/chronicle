import axios from "axios";
import { Job } from "../types/job";

const API_URL = process.env.NEXT_PUBLIC_API_URL!;
const POLL_INTERVAL = parseInt(process.env.NEXT_PUBLIC_POLL_INTERVAL || "5000", 10);

// Configure axios with CORS headers
const api = axios.create({
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'x-api-key': 'test', // Add an API key for LocalStack
  }
});

// Determine if we're using LocalStack by checking the API URL
const isLocalStack = API_URL.includes('localhost') || 
                     API_URL.includes('localstack') || 
                     API_URL.includes('host.docker.internal');

// Format the API URLs based on environment
let baseApiUrl = API_URL;
if (isLocalStack && !API_URL.includes('restapis')) {
  // Make sure we use the full correct path for LocalStack API Gateway
  baseApiUrl = `${API_URL}/restapis/vsbwhar1h7/prod/_user_request_`;
  console.log(`Using LocalStack API URL: ${baseApiUrl}`);
}

// Check if we're using mock data
const useMockMode = API_URL === 'mock';

// Use mock data if explicitly set or if LocalStack API is unavailable
let useMockData = useMockMode;

// Track whether we've attempted to use alternative connection options
let triedAlternativeEndpoints = false;

// Possible LocalStack endpoints to try (in order of preference)
const alternativeEndpoints = [
  'http://localstack:4566/restapis/vsbwhar1h7/prod/_user_request_',
  'http://localhost:4566/restapis/vsbwhar1h7/prod/_user_request_',
  'http://172.17.0.1:4566/restapis/vsbwhar1h7/prod/_user_request_', // Common Docker bridge network IP
];

// Mock data for development and testing
const mockJobs: Job[] = [
  {
    jobId: "mock-123",
    url: "https://www.youtube.com/watch?v=mock1",
    filename: "mock-recording.mkv",
    status: "COMPLETED",
    s3Key: "recordings/2023/05/01/mock-recording.mkv",
    createdAt: new Date().toISOString(),
    progress: 100,
    size: 1024000000
  },
  {
    jobId: "mock-456",
    url: "https://www.youtube.com/watch?v=mock2",
    filename: "mock-live.mkv",
    status: "RECORDING",
    s3Key: "recordings/2023/05/02/mock-live.mkv",
    createdAt: new Date().toISOString(),
    progress: 45,
    lastHeartbeat: new Date().toISOString()
  }
];

/**
 * Format the API path correctly based on environment
 */
function getApiPath(path: string): string {
  if (useMockData) {
    return ""; // Mock data mode, URL not needed
  }
  
  if (isLocalStack) {
    // LocalStack path format - Use the correct format to avoid 403 errors
    return `${baseApiUrl}?path=${path}`;
  } else {
    // Production/AWS API Gateway format
    return `${baseApiUrl}${path}`;
  }
}

/**
 * Try to connect to an API endpoint with automatic fallback
 */
async function tryApiEndpoints<T>(apiCall: (endpoint: string) => Promise<T>): Promise<T> {
  if (useMockData) {
    throw new Error("Using mock data");
  }
  
  // First try the configured endpoint
  try {
    return await apiCall(API_URL);
  } catch (error) {
    console.warn(`Connection to ${API_URL} failed, trying alternatives...`);
    
    // If we're using LocalStack, try alternative endpoints
    if (isLocalStack && !triedAlternativeEndpoints) {
      triedAlternativeEndpoints = true;
      
      // Try each alternative endpoint
      for (const endpoint of alternativeEndpoints) {
        try {
          console.log(`Trying alternative endpoint: ${endpoint}...`);
          const result = await apiCall(endpoint);
          console.log(`Success with endpoint: ${endpoint}`);
          return result;
        } catch (endpointError) {
          console.warn(`Failed to connect to ${endpoint}`);
        }
      }
    }
    
    // If we've tried all endpoints and failed, use mock data
    if (isLocalStack) {
      console.warn('All LocalStack connection attempts failed. Using mock data instead.');
      useMockData = true;
      throw error; // Rethrow to trigger mock data fallback
    } else {
      throw error;
    }
  }
}

/**
 * Fetch the list of jobs.
 */
export async function listJobs(): Promise<Job[]> {
  if (useMockData) {
    console.log("Using mock data for job listing");
    return mockJobs;
  }

  try {
    if (isLocalStack) {
      // Use our direct LocalStack integration
      console.log(`Using direct LocalStack integration for jobs`);
      const res = await api.get<Job[]>('/api/localstack-jobs');
      return res.data;
    } else {
      // Direct API call for production
      console.log(`Fetching jobs from: ${getApiPath('/jobs')}`);
      const res = await api.get<Job[]>(getApiPath('/jobs'));
      return res.data;
    }
  } catch (error) {
    console.warn('Error connecting to API, falling back to mock data');
    console.error(error);
    useMockData = true;
    return mockJobs;
  }
}

/**
 * Fetch a single job by ID.
 */
export async function getJob(jobId: string): Promise<Job> {
  if (useMockData) {
    const job = mockJobs.find(j => j.jobId === jobId);
    if (job) return job;
    throw new Error(`Job with ID ${jobId} not found`);
  }

  try {
    if (isLocalStack) {
      // Use our local CORS proxy for LocalStack
      const proxyUrl = `/api/cors-proxy?url=${encodeURIComponent(getApiPath(`/jobs/${jobId}`))}`;
      const res = await api.get<Job>(proxyUrl);
      return res.data;
    } else {
      const res = await api.get<Job>(getApiPath(`/jobs/${jobId}`));
      return res.data;
    }
  } catch (error) {
    console.warn('Error connecting to API, falling back to mock data');
    useMockData = true;
    const job = mockJobs.find(j => j.jobId === jobId);
    if (job) return job;
    throw new Error(`Job with ID ${jobId} not found`);
  }
}

/**
 * Create a new job. Generates a UUID in the client.
 */
export async function createJob(url: string, filename: string): Promise<Job> {
  // generate a client-side UUID
  const jobId = crypto.randomUUID();
  
  if (useMockData) {
    console.log("Creating mock job:", { jobId, url, filename });
    const newJob: Job = {
      jobId,
      url,
      filename,
      status: "PENDING",
      s3Key: `recordings/${new Date().toISOString().split('T')[0]}/${filename}`,
      createdAt: new Date().toISOString(),
      progress: 0
    };
    mockJobs.push(newJob);
    
    // Simulate job progression
    setTimeout(() => {
      const job = mockJobs.find(j => j.jobId === jobId);
      if (job) {
        job.status = "RECORDING";
        job.startedAt = new Date().toISOString();
        job.progress = 10;
      }
    }, 2000);
    
    return newJob;
  }

  try {
    if (isLocalStack) {
      // Use our local CORS proxy for LocalStack
      const proxyUrl = `/api/cors-proxy?url=${encodeURIComponent(getApiPath('/jobs'))}`;
      await api.post(proxyUrl, {
        jobId,
        url,
        filename,
      });
    } else {
      await api.post(getApiPath('/jobs'), {
        jobId,
        url,
        filename,
      });
    }
    
    // Immediately fetch and return the newly created job record
    return getJob(jobId);
  } catch (error) {
    console.warn('Error connecting to API, falling back to mock data');
    useMockData = true;
    return createJob(url, filename);
  }
}

/**
 * Simple helper to poll listJobs every POLL_INTERVAL ms.
 */
export function pollJobs(onUpdate: (jobs: Job[]) => void): () => void {
  let timer: NodeJS.Timeout;

  async function tick() {
    try {
      const jobs = await listJobs();
      
      // For mock mode, simulate progress updates
      if (useMockData) {
        jobs.forEach(job => {
          if (job.status === "RECORDING" && job.progress !== undefined && job.progress < 100) {
            job.progress += 2;
            job.lastHeartbeat = new Date().toISOString();
            
            if (job.progress >= 100) {
              job.status = "COMPLETED";
              job.finishedAt = new Date().toISOString();
            }
          }
        });
      }
      
      onUpdate(jobs);
    } catch (err) {
      console.error("Failed to fetch jobs:", err);
    } finally {
      timer = setTimeout(tick, POLL_INTERVAL);
    }
  }

  tick();

  return () => clearTimeout(timer);
}
