// Calls the API through the same origin: nginx proxies /api/* to the api Service.
const API = '/api/products';

const $ = (id) => document.getElementById(id);
const form = $('product-form');
const rows = $('rows');
const status = $('status');

function setStatus(text, isError = false) {
  status.textContent = text;
  status.style.color = isError ? 'var(--danger)' : 'var(--muted)';
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

async function request(url, options = {}) {
  const res = await fetch(url, { headers: { 'Content-Type': 'application/json' }, ...options });
  if (!res.ok && res.status !== 204) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `HTTP ${res.status}`);
  }
  return res.status === 204 ? null : res.json();
}

async function load() {
  try {
    const products = await request(API);
    rows.innerHTML = products.length
      ? products.map((p) => `
        <tr>
          <td>${p.id}</td>
          <td>${escapeHtml(p.name)}</td>
          <td>${escapeHtml(p.category)}</td>
          <td class="num">Q${Number(p.price).toFixed(2)}</td>
          <td class="num">${p.stock}</td>
          <td>
            <button class="small secondary" data-edit="${p.id}">Edit</button>
            <button class="small danger" data-delete="${p.id}">Delete</button>
          </td>
        </tr>`).join('')
      : '<tr><td colspan="6">No products yet</td></tr>';
    rows.dataset.products = JSON.stringify(products);
  } catch (err) {
    rows.innerHTML = '<tr><td colspan="6">Could not reach the API</td></tr>';
    setStatus(err.message, true);
  }
}

function resetForm() {
  form.reset();
  $('product-id').value = '';
  $('form-title').textContent = 'Add product';
  $('cancel').hidden = true;
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const id = $('product-id').value;
  const body = JSON.stringify({
    name: $('name').value,
    category: $('category').value,
    price: $('price').value,
    stock: $('stock').value,
  });
  try {
    await request(id ? `${API}/${id}` : API, { method: id ? 'PUT' : 'POST', body });
    setStatus(id ? 'Product updated' : 'Product created');
    resetForm();
    load();
  } catch (err) {
    setStatus(err.message, true);
  }
});

$('cancel').addEventListener('click', resetForm);

rows.addEventListener('click', async (e) => {
  const editId = e.target.dataset.edit;
  const deleteId = e.target.dataset.delete;
  if (editId) {
    const p = JSON.parse(rows.dataset.products).find((x) => String(x.id) === editId);
    $('product-id').value = p.id;
    $('name').value = p.name;
    $('category').value = p.category;
    $('price').value = p.price;
    $('stock').value = p.stock;
    $('form-title').textContent = `Edit product #${p.id}`;
    $('cancel').hidden = false;
  }
  if (deleteId && confirm('Delete this product?')) {
    try {
      await request(`${API}/${deleteId}`, { method: 'DELETE' });
      setStatus('Product deleted');
      load();
    } catch (err) {
      setStatus(err.message, true);
    }
  }
});

fetch('/pod').then((r) => r.text()).then((name) => { $('pod').textContent = name.trim(); }).catch(() => {});
load();
