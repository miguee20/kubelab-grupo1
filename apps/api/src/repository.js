const { Pool } = require('pg');

// PostgreSQL repository for the products table (schema created by the init Job in k8s/apps/database)
function createRepository(connectionString) {
  const pool = new Pool({ connectionString, max: 5, idleTimeoutMillis: 30000 });
  const columns = 'id, name, category, price::float AS price, stock, updated_at';

  return {
    pool,
    async ping() {
      await pool.query('SELECT 1');
    },
    async list() {
      const { rows } = await pool.query(`SELECT ${columns} FROM products ORDER BY id`);
      return rows;
    },
    async get(id) {
      const { rows } = await pool.query(`SELECT ${columns} FROM products WHERE id = $1`, [id]);
      return rows[0] || null;
    },
    async create(p) {
      const { rows } = await pool.query(
        `INSERT INTO products (name, category, price, stock) VALUES ($1, $2, $3, $4) RETURNING ${columns}`,
        [p.name, p.category, p.price, p.stock],
      );
      return rows[0];
    },
    async update(id, p) {
      const { rows } = await pool.query(
        `UPDATE products SET name = $2, category = $3, price = $4, stock = $5, updated_at = now()
         WHERE id = $1 RETURNING ${columns}`,
        [id, p.name, p.category, p.price, p.stock],
      );
      return rows[0] || null;
    },
    async remove(id) {
      const { rowCount } = await pool.query('DELETE FROM products WHERE id = $1', [id]);
      return rowCount > 0;
    },
  };
}

module.exports = { createRepository };
