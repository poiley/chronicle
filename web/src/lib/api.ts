import axios from "axios";
import { Job } from "../types/job";

const API_URL = process.env.NEXT_PUBLIC_API_URL!;
const POLL_INTERVAL = parseInt(process.env.NEXT_PUBLIC_POLL_INTERVAL || "5000", 10);

/**
 * Fetch the list of jobs.
 */
export async function listJobs(): Promise<Job[]> {
  const res = await axios.get<Job[]>(`${API_URL}?path=/jobs`);
  return res.data;
}

/**
 * Fetch a single job by ID.
 */
export async function getJob(jobId: string): Promise<Job> {
  const res = await axios.get<Job>(`${API_URL}?path=/jobs/${jobId}`);
  return res.data;
}

/**
 * Create a new job. Generates a UUID in the client.
 */
export async function createJob(url: string, filename: string): Promise<Job> {
  // generate a client-side UUID
  const jobId = crypto.randomUUID();
  await axios.post(`${API_URL}?path=/jobs`, {
    jobId,
    url,
    filename,
  });
  // Immediately fetch and return the newly created job record
  return getJob(jobId);
}

/**
 * Simple helper to poll listJobs every POLL_INTERVAL ms.
 */
export function pollJobs(onUpdate: (jobs: Job[]) => void): () => void {
  let timer: NodeJS.Timeout;

  async function tick() {
    try {
      const jobs = await listJobs();
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
