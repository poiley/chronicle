// mock/server.js
const jsonServer = require('json-server');
const server = jsonServer.create();
const path = require('path');
const router = jsonServer.router(path.join(__dirname, 'db.json'));
const middlewares = jsonServer.defaults({
  static: './public',
});

// Add CORS headers
server.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  next();
});

// Handle API Gateway path style
server.use((req, res, next) => {
  // Check if path parameter is present (LocalStack style)
  if (req.query.path) {
    req.url = req.query.path;
  }
  next();
});

// Add middlewares
server.use(middlewares);
server.use(jsonServer.bodyParser);

// Default response delay
server.use((req, res, next) => {
  setTimeout(next, 800);
});

// Custom routes
server.post('/jobs', (req, res) => {
  const db = router.db.getState();
  const { jobId, url, filename } = req.body;
  
  // Create a new job
  const newJob = {
    jobId,
    url,
    filename,
    status: 'PENDING',
    s3Key: `recordings/${new Date().toISOString().split('T')[0]}/${filename}`,
    createdAt: new Date().toISOString(),
    progress: 0
  };
  
  // Add to jobs array
  const jobs = db.jobs || [];
  jobs.push(newJob);
  
  // Update db
  router.db.setState({ ...db, jobs });
  router.db.write();
  
  res.status(201).json(newJob);
});

// Use router
server.use(router);

// Start server
const PORT = 3001;
server.listen(PORT, () => {
  console.log(`Mock API server is running on http://localhost:${PORT}`);
  console.log(`To use with the frontend, set NEXT_PUBLIC_API_URL=http://localhost:${PORT}`);
}); 