# Base image for all stages
FROM node:18-alpine AS base
WORKDIR /app

# Development dependencies stage
FROM base AS deps
# Install dependencies for node-gyp (if needed)
RUN apk add --no-cache libc6-compat

# Copy package files
COPY web/package.json web/package-lock.json ./

# Install dependencies
RUN npm ci

# Development stage
FROM base AS development
WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
# Copy application code
COPY web .

# Expose port
EXPOSE 3000

# Command to run development server
CMD ["npm", "run", "dev"]

# Build stage
FROM base AS builder
WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
# Copy application code
COPY web .

# Set production environment
ENV NEXT_TELEMETRY_DISABLED 1
ENV NODE_ENV production

# Build the application
RUN npm run build

# Production stage
FROM base AS production
WORKDIR /app

# Set production environment
ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

# Copy necessary files from builder stage
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# Expose port
EXPOSE 3000

# Command to run production server
CMD ["node", "server.js"] 