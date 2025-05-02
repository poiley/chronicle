export type JobStatus =
  | "PENDING"
  | "STARTED"
  | "RECORDING"
  | "UPLOADING"
  | "CREATING_TORRENT"
  | "SEEDING"
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
  creatingTorrentAt?: string;
  seedingStartedAt?: string;
  finishedAt?:      string;
  errorDetail?:     string;
  errorMessage?:    string;
  progress?:        number;  // Percentage of download/recording progress
  size?:            number;  // Size in bytes
  torrentFile?:     string;  // S3 key for the torrent file
  torrentInfo?:     string;  // Information about the torrent
}
