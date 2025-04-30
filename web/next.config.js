/** @type {import('next').NextConfig} */
const nextConfig = {
    reactStrictMode: true,
    experimental: {
      appDir: true,
    },
    // No SSR on pages that use `use client`—everything else is static
  };
  
  module.exports = nextConfig;
  