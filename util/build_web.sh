#!/usr/bin/env bash
set -euo pipefail

# Build & export the Next.js app in ./web
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$BASE_DIR/web"
OUT_DIR="$WEB_DIR/out"

echo "🔨 Installing dependencies..."
cd "$WEB_DIR"
npm ci

echo "🏗  Building Next.js app..."
npm run build

echo "📁 Exporting static site to '$OUT_DIR'..."
npm run export

echo "✅ Done. Static files are in $OUT_DIR"
