"use client";

import React, { useState, useEffect } from "react";
import { Job } from "../types/job";
import { listJobs, pollJobs } from "../lib/api";
import { JobCard } from "../components/JobCard";
import { JobDetails } from "../components/JobDetails";
import { NewJobModal } from "../components/NewJobModal";

export default function HomePage() {
  const [jobs, setJobs] = useState<Job[]>([]);
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);

  // Initial load + polling
  useEffect(() => {
    let stopped = false;
    async function fetchOnce() {
      const initial = await listJobs();
      if (!stopped) setJobs(initial);
    }
    fetchOnce();
    const stopPolling = pollJobs((latest) => {
      if (!stopped) setJobs(latest);
    });
    return () => {
      stopped = true;
      stopPolling();
    };
  }, []);

  const selectedJob = jobs.find((j) => j.jobId === selectedJobId) || null;

  return (
    <div className="p-6 space-y-6">
      <header className="flex items-center justify-between">
        <h1 className="text-3xl font-bold">YouTube Live Recorder Dashboard</h1>
        <NewJobModal
          onJobCreated={(job) => setJobs((prev) => [job, ...prev])}
        />
      </header>

      <main>
        {jobs.length === 0 ? (
          <p className="text-center text-gray-400">No jobs yet.</p>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
            {jobs.map((job) => (
              <JobCard
                key={job.jobId}
                job={job}
                onClick={(id) => setSelectedJobId(id)}
              />
            ))}
          </div>
        )}
      </main>

      {selectedJob && (
        <JobDetails
          job={selectedJob}
          onClose={() => setSelectedJobId(null)}
        />
      )}
    </div>
  );
}
