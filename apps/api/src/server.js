const { createApp } = require('./app');
const { createRepository } = require('./repository');

const port = Number(process.env.PORT || 3000);
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL is not set');
  process.exit(1);
}

const repo = createRepository(databaseUrl);
const server = createApp(repo).listen(port, () => console.log(`API listening on :${port}`));

// Graceful shutdown so rolling updates do not drop in-flight requests
function shutdown(signal) {
  console.log(`${signal} received, shutting down`);
  server.close(() => repo.pool.end().then(() => process.exit(0)));
  setTimeout(() => process.exit(1), 10000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
