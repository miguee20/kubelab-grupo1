const express = require('express');
const client = require('prom-client');

// Builds the Express app. The repository is injected so tests can run without a database.
function createApp(repo) {
  const app = express();
  app.use(express.json());

  const registry = new client.Registry();
  client.collectDefaultMetrics({ register: registry });

  const httpRequests = new client.Counter({
    name: 'http_requests_total',
    help: 'Total HTTP requests handled by the API',
    labelNames: ['method', 'route', 'status'],
    registers: [registry],
  });
  const httpDuration = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request duration in seconds',
    labelNames: ['method', 'route', 'status'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
    registers: [registry],
  });

  // Request metrics (route template, not the raw URL, to keep label cardinality low)
  app.use((req, res, next) => {
    const end = httpDuration.startTimer();
    res.on('finish', () => {
      const route = req.route ? req.baseUrl + req.route.path : 'unmatched';
      const labels = { method: req.method, route, status: String(res.statusCode) };
      httpRequests.inc(labels);
      end(labels);
    });
    next();
  });

  // CORS so the API can also be called directly from api.grupo1.lab in a browser
  app.use((req, res, next) => {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    next();
  });

  // Liveness: the process is up; also reports the running build, so a deployment can be checked from outside
  app.get('/health', (req, res) => res.json({ status: 'ok', version: process.env.APP_VERSION || 'dev' }));

  // Readiness: the database answers
  app.get('/ready', async (req, res) => {
    try {
      await repo.ping();
      res.json({ status: 'ready' });
    } catch (err) {
      res.status(503).json({ status: 'unavailable', error: err.message });
    }
  });

  app.get('/metrics', async (req, res) => {
    res.set('Content-Type', registry.contentType);
    res.send(await registry.metrics());
  });

  const products = express.Router();

  products.get('/', async (req, res) => res.json(await repo.list()));

  products.get('/:id', async (req, res) => {
    const item = await repo.get(Number(req.params.id));
    if (!item) return res.status(404).json({ error: 'product not found' });
    res.json(item);
  });

  products.post('/', async (req, res) => {
    const error = validate(req.body);
    if (error) return res.status(400).json({ error });
    res.status(201).json(await repo.create(normalize(req.body)));
  });

  products.put('/:id', async (req, res) => {
    const error = validate(req.body);
    if (error) return res.status(400).json({ error });
    const item = await repo.update(Number(req.params.id), normalize(req.body));
    if (!item) return res.status(404).json({ error: 'product not found' });
    res.json(item);
  });

  products.delete('/:id', async (req, res) => {
    const deleted = await repo.remove(Number(req.params.id));
    if (!deleted) return res.status(404).json({ error: 'product not found' });
    res.sendStatus(204);
  });

  // Same routes with and without the /api prefix (the web app proxies /api/*)
  app.use('/products', products);
  app.use('/api/products', products);

  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).json({ error: 'internal server error' });
  });

  return app;
}

function validate(body) {
  if (!body || typeof body !== 'object') return 'body must be a JSON object';
  if (typeof body.name !== 'string' || body.name.trim() === '') return 'name is required';
  if (body.price !== undefined && (isNaN(Number(body.price)) || Number(body.price) < 0)) return 'price must be a number >= 0';
  if (body.stock !== undefined && (!Number.isInteger(Number(body.stock)) || Number(body.stock) < 0)) return 'stock must be an integer >= 0';
  return null;
}

function normalize(body) {
  return {
    name: body.name.trim(),
    category: (body.category || 'General').trim(),
    price: Number(body.price || 0),
    stock: Number(body.stock || 0),
  };
}

module.exports = { createApp };
