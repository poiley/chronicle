import "../styles/globals.css";
import React from "react";

export const metadata = {
  title: "chronicle",
  description: "Monitor and submit livestream recording jobs",
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
