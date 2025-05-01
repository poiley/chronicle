export type JobStatus =
  | "PENDING"
  | "STARTED"
  | "RECORDING"
  | "UPLOADING"
  | "COMPLETED"
  | "FAILED";

export interface Job {
  jobId:            string;
  url:              string;
  filename:         string;
  s3Key:            string;
  status:           JobStatus;
  createdAt:        string;
  startedAt?:       string;
  recordingAt?:     string;
  lastHeartbeat?:   string;
  bytesDownloaded?: number;
  uploadingAt?:     string;
  finishedAt?:      string;
  errorDetail?:     string;
  errorMessage?:    string;
  progress?:        number;  // Percentage of download/recording progress
  size?:            number;  // Size in bytes
}
