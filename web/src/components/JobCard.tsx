import React from "react";
import { Job } from "../types/job";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

type JobCardProps = {
  job: Job;
  onClick: (jobId: string) => void;
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

export function JobCard({ job, onClick }: JobCardProps) {
  return (
    <Card
      onClick={() => onClick(job.jobId)}
      className="cursor-pointer hover:shadow-lg transition"
    >
      <CardHeader className="flex justify-between items-center">
        <CardTitle className="truncate">{job.filename}</CardTitle>
        <Badge variant="outline" className={getBadgeStyle(job.status)}>
          {job.status}
        </Badge>
      </CardHeader>
      <CardContent className="space-y-1">
        <p className="text-sm truncate">URL: {job.url}</p>
        {job.lastHeartbeat && (
          <p className="text-xs text-muted-foreground">
            Last heartbeat: {new Date(job.lastHeartbeat).toLocaleTimeString()}
          </p>
        )}
        {job.bytesDownloaded != null && (
          <p className="text-xs text-muted-foreground">
            Downloaded: {job.bytesDownloaded.toLocaleString()} bytes
          </p>
        )}
        {job.torrentFile && (
          <p className="text-xs text-muted-foreground">
            Torrent available
          </p>
        )}
        <div className="text-right">
          <Button size="sm">Details</Button>
        </div>
      </CardContent>
    </Card>
  );
}
