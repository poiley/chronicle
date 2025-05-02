import React from "react";
import { Job } from "../types/job";
import { Card, CardHeader, CardTitle, CardContent, CardFooter } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Download } from "lucide-react";

type JobDetailsProps = {
  job: Job;
  onClose: () => void;
};

export function JobDetails({ job, onClose }: JobDetailsProps) {
  // Function to handle direct S3 download
  const handleS3Download = () => {
    // Create a presigned URL or redirect to the S3 URL
    const s3Path = `${process.env.NEXT_PUBLIC_S3_URL}/${job.s3Key}/${job.filename}`;
    window.open(s3Path, '_blank');
  };

  // Function to handle torrent download
  const handleTorrentDownload = () => {
    if (job.torrentFile) {
      const torrentPath = `${process.env.NEXT_PUBLIC_S3_URL}/${job.torrentFile}`;
      window.open(torrentPath, '_blank');
    }
  };

  // Get badge style based on status
  const getBadgeStyle = (status: Job["status"]) => {
    const colorMapping = {
      "PENDING": "bg-gray-500",
      "STARTED": "bg-blue-500",
      "RECORDING": "bg-green-500",
      "UPLOADING": "bg-yellow-500",
      "CREATING_TORRENT": "bg-purple-500",
      "SEEDING": "bg-amber-500",
      "COMPLETED": "bg-emerald-500",
      "FAILED": "bg-red-500"
    };
    
    return colorMapping[status] || "bg-gray-500";
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <Card className="w-full max-w-lg">
        <CardHeader className="flex justify-between items-center">
          <CardTitle>Job Details</CardTitle>
          <Button variant="ghost" onClick={onClose}>
            Close
          </Button>
        </CardHeader>
        <CardContent className="space-y-2">
          <div className="flex justify-between">
            <span className="font-medium">Status:</span>
            <Badge variant="outline" className={getBadgeStyle(job.status)}>
              {job.status}
            </Badge>
          </div>
          <dl className="grid grid-cols-2 gap-2 text-sm">
            <dt>Created At</dt>
            <dd>{new Date(job.createdAt).toLocaleString()}</dd>

            {job.startedAt && (
              <>
                <dt>Started At</dt>
                <dd>{new Date(job.startedAt).toLocaleString()}</dd>
              </>
            )}
            {job.recordingAt && (
              <>
                <dt>Recording Started</dt>
                <dd>{new Date(job.recordingAt).toLocaleString()}</dd>
              </>
            )}
            {job.uploadingAt && (
              <>
                <dt>Uploading At</dt>
                <dd>{new Date(job.uploadingAt).toLocaleString()}</dd>
              </>
            )}
            {job.creatingTorrentAt && (
              <>
                <dt>Creating Torrent At</dt>
                <dd>{new Date(job.creatingTorrentAt).toLocaleString()}</dd>
              </>
            )}
            {job.seedingStartedAt && (
              <>
                <dt>Seeding Started At</dt>
                <dd>{new Date(job.seedingStartedAt).toLocaleString()}</dd>
              </>
            )}
            {job.finishedAt && (
              <>
                <dt>Finished At</dt>
                <dd>{new Date(job.finishedAt).toLocaleString()}</dd>
              </>
            )}
            {job.lastHeartbeat && (
              <>
                <dt>Last Heartbeat</dt>
                <dd>{new Date(job.lastHeartbeat).toLocaleTimeString()}</dd>
              </>
            )}
            {job.bytesDownloaded != null && (
              <>
                <dt>Bytes Downloaded</dt>
                <dd>{job.bytesDownloaded.toLocaleString()}</dd>
              </>
            )}
          </dl>

          {job.errorDetail && (
            <div className="mt-4">
              <h3 className="font-medium">Error Detail</h3>
              <pre className="bg-red-900 p-2 rounded text-xs overflow-auto">
                {job.errorDetail}
              </pre>
            </div>
          )}
        </CardContent>
        
        {job.status === "COMPLETED" && (
          <CardFooter className="flex gap-2 justify-end">
            <Button 
              onClick={handleS3Download} 
              variant="outline"
              className="flex items-center gap-1"
            >
              <Download size={16} />
              Direct Download
            </Button>
            
            {job.torrentFile && (
              <Button 
                onClick={handleTorrentDownload}
                className="flex items-center gap-1"
              >
                <Download size={16} />
                Download Torrent
              </Button>
            )}
          </CardFooter>
        )}
      </Card>
    </div>
  );
}

// duplicate of statusColor from JobCard; you could hoist it
function statusColor(status: Job["status"]) {
  switch (status) {
    case "PENDING":
      return "gray";
    case "STARTED":
      return "blue";
    case "RECORDING":
      return "green";
    case "UPLOADING":
      return "yellow";
    case "CREATING_TORRENT":
      return "purple";
    case "SEEDING":
      return "amber";
    case "COMPLETED":
      return "olive";
    case "FAILED":
      return "red";
    default:
      return "gray";
  }
}
