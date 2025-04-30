import "../styles/globals.css";
import React from "react";

export const metadata = {
  title: "YouTube Live Recorder Dashboard",
  description: "Monitor and submit YouTube Live recording jobs",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body className="min-h-screen bg-black text-white">
        {children}
      </body>
    </html>
  );
}
