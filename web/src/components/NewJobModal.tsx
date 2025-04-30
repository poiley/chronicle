import React, { useState } from "react";
import { createJob } from "../lib/api";
import { Job } from "../types/job";
import { Input }     from "@/components/ui/input";
import { Button }   from "@/components/ui/button";
import { Label }    from "@/components/ui/label";


type NewJobModalProps = {
  onJobCreated: (job: Job) => void;
};

export function NewJobModal({ onJobCreated }: NewJobModalProps) {
  const [open, setOpen] = useState(false);
  const [url, setUrl] = useState("");
  const [filename, setFilename] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      const job = await createJob(url, filename || undefined);
      onJobCreated(job);
      setOpen(false);
      setUrl("");
      setFilename("");
    } catch (err) {
      console.error("Failed to create job", err);
      alert("Error creating job; check console.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <Button onClick={() => setOpen(true)}>New Job</Button>
      {open && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg w-full max-w-md p-6">
            <h2 className="text-lg font-semibold mb-4">Submit New Job</h2>
            <form className="space-y-4" onSubmit={handleSubmit}>
              <div>
                <Label htmlFor="url">YouTube Live URL</Label>
                <Input
                  id="url"
                  type="url"
                  required
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  className="w-full"
                />
              </div>
              <div>
                <Label htmlFor="filename">Output Filename</Label>
                <Input
                  id="filename"
                  type="text"
                  required
                  value={filename}
                  onChange={(e) => setFilename(e.target.value)}
                  placeholder="my_stream.mkv"
                  className="w-full"
                />
              </div>
              <div className="flex justify-end space-x-2">
                <Button
                  variant="secondary"
                  onClick={() => setOpen(false)}
                  disabled={loading}
                >
                  Cancel
                </Button>
                <Button type="submit" disabled={loading}>
                  {loading ? "Submitting..." : "Submit"}
                </Button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  );
}
