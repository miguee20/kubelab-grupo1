const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../src/app');

// In-memory repository with the same interface as the PostgreSQL one
function memoryRepo() {
  let items = [];
  let nextId = 1;
  return {
    async ping() {},
    async list() { return items; },
    async get(id) { return items.find((p) => p.id === id) || null; },
    async create(p) { const item = { id: nextId++, ...p }; items.push(item); return item; },
    async update(id, p) {
      const i = items.findIndex((x) => x.id === id);
      if (i < 0) return null;
      items[i] = { id, ...p };
      return items[i];
    },
    async remove(id) {
      const before = items.length;
      items = items.filter((p) => p.id !== id);
      return items.length < before;
    },
  };
}

let server;
let base;

before(async () => {
  server = createApp(memoryRepo()).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

const json = (method, body) => ({ method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

test('GET /health returns okas and the build version', async () => {
  const res = await fetch(`${base}/health`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, 'okas');
  assert.equal(body.version, process.env.APP_VERSION || 'dev');
});

test('products CRUD lifecycle', async () => {
  let res = await fetch(`${base}/products`, json('POST', { name: 'Rice 1 lb', category: 'Grains', price: 6.5, stock: 40 }));
  assert.equal(res.status, 201);
  const created = await res.json();
  assert.equal(created.name, 'Rice 1 lb');

  res = await fetch(`${base}/products`);
  assert.equal((await res.json()).length, 1);

  res = await fetch(`${base}/products/${created.id}`, json('PUT', { name: 'Rice 1 lb', category: 'Grains', price: 7, stock: 35 }));
  assert.equal(res.status, 200);
  assert.equal((await res.json()).stock, 35);

  res = await fetch(`${base}/products/${created.id}`, { method: 'DELETE' });
  assert.equal(res.status, 204);

  res = await fetch(`${base}/products/${created.id}`);
  assert.equal(res.status, 404);
});

test('POST /products validates input', async () => {
  const res = await fetch(`${base}/products`, json('POST', { name: '', price: -1 }));
  assert.equal(res.status, 400);
});

test('/api prefix is supported for the web proxy', async () => {
  const res = await fetch(`${base}/api/products`);
  assert.equal(res.status, 200);
});

test('GET /metrics exposes Prometheus metrics', async () => {
  const res = await fetch(`${base}/metrics`);
  const body = await res.text();
  assert.equal(res.status, 200);
  assert.match(body, /http_requests_total/);
  assert.match(body, /process_cpu_seconds_total/);
});
