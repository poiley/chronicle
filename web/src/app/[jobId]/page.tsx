// web/src/app/jobs/[jobId]/page.tsx

"use client";

import React, { useState, useEffect } from "react";
import { useParams, useRouter } from "next/navigation";
import { getJob } from "../../lib/api";
import { Job } from "../../types/job";
import { JobDetails } from "../../components/JobDetails";

export default function JobPage() {
  const { jobId } = useParams();
  const router = useRouter();
  const [job, setJob] = useState<Job | null>(null);

  useEffect(() => {
    if (!jobId) return;
    getJob(jobId)
      .then(setJob)
      .catch((err) => {
        console.error("Failed to load job:", err);
        // Optionally, navigate back on 404:
        // router.push("/");
      });
  }, [jobId, router]);

  if (!job) {
    return (
      <div className="p-6 text-center text-gray-400">
        Loading job details...
      </div>
    );
  }

  return (
    <JobDetails
      job={job}
      onClose={() => {
        router.push("/");
      }}
    />
  );
}
