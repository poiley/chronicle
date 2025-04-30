import React from "react";
import { Job } from "../types/job";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

type JobDetailsProps = {
  job: Job;
  onClose: () => void;
};

export function JobDetails({ job, onClose }: JobDetailsProps) {
  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4">
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
            <Badge variant={statusColor(job.status)}>
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
    case "COMPLETED":
      return "olive";
    case "FAILED":
      return "red";
    default:
      return "gray";
  }
}
