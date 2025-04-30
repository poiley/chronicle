import React from "react";
import { Job } from "../types/job";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

type JobCardProps = {
  job: Job;
  onClick: (jobId: string) => void;
};

const statusColor = (status: Job["status"]) => {
  switch (status) {
    case "PENDING":
      return "gray";
    case "STARTED":
      return "blue";
    case "RECORDING":
      return "green";
    case "UPLOADING":
      return "yellow";
    case "COMPLETED":
      return "olive";
    case "FAILED":
      return "red";
    default:
      return "gray";
  }
};

export function JobCard({ job, onClick }: JobCardProps) {
  return (
    <Card
      onClick={() => onClick(job.jobId)}
      className="cursor-pointer hover:shadow-lg transition"
    >
      <CardHeader className="flex justify-between items-center">
        <CardTitle className="truncate">{job.filename}</CardTitle>
        <Badge variant={statusColor(job.status)}>
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
        <div className="text-right">
          <Button size="sm">Details</Button>
        </div>
      </CardContent>
    </Card>
  );
}
