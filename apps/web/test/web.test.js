const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('index.html loads the app script and stylesheet', () => {
  const html = read('public/index.html');
  assert.match(html, /<script src="app\.js"><\/script>/);
  assert.match(html, /<link rel="stylesheet" href="styles\.css">/);
  assert.match(html, /id="product-form"/);
});

test('app.js is valid JavaScript and calls the proxied API', () => {
  const js = read('public/app.js');
  assert.doesNotThrow(() => new vm.Script(js));
  assert.match(js, /\/api\/products/);
  for (const method of ['POST', 'PUT', 'DELETE']) assert.match(js, new RegExp(`'${method}'`));
});

test('nginx proxies /api/ to the api Service and exposes /healthz', () => {
  const conf = read('nginx.conf');
  assert.match(conf, /listen 8080;/);
  assert.match(conf, /location \/api\//);
  assert.match(conf, /api\.inventory\.svc\.cluster\.local/);
  assert.match(conf, /location = \/healthz/);
});
