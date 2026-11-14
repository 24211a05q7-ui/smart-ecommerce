const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const config = require('../src/config/env');
const { pool } = require('../src/config/db');

// Any fixed number works. All runners of this project must use the same one,
// so they compete for the same lock.
const ADVISORY_LOCK_KEY = 727001;

// Default folder is backend/migrations. Tests can point elsewhere:
//   npm run migrate -- --dir=C:\some\folder
function getMigrationsDir() {
  const arg = process.argv.find((a) => a.startsWith('--dir='));
  return arg ? path.resolve(arg.slice('--dir='.length)) : path.join(__dirname, '..', 'migrations');
}

// Line endings are normalised first, so Windows (CRLF) and Linux (LF)
// produce the same checksum for the same file.
function checksum(sql) {
  return crypto.createHash('sha256').update(sql.replace(/\r\n/g, '\n')).digest('hex');
}

async function run() {
  const dir = getMigrationsDir();
  if (!fs.existsSync(dir)) {
    throw new Error(`Migrations folder not found: ${dir}`);
  }

  // Only files named like 001_something.sql, applied in name order.
  const files = fs.readdirSync(dir).filter((f) => /^\d+_.+\.sql$/.test(f)).sort();

  console.log(`Database: ${config.db.database}`);
  console.log(`Folder:   ${dir}`);

  // A dedicated connection. Advisory locks belong to one database session,
  // so we must keep using the same connection until we unlock.
  const client = await pool.connect();
  let locked = false;

  try {
    const lockResult = await client.query('SELECT pg_try_advisory_lock($1) AS locked', [
      ADVISORY_LOCK_KEY,
    ]);
    if (!lockResult.rows[0].locked) {
      throw new Error('Another migration run is already in progress. Exiting without changes.');
    }
    locked = true;

    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename   TEXT PRIMARY KEY,
        checksum   TEXT NOT NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    const appliedRows = (await client.query('SELECT filename, checksum FROM schema_migrations')).rows;
    const applied = new Map(appliedRows.map((r) => [r.filename, r.checksum]));

    // Safety checks on migrations that were already applied.
    for (const name of applied.keys()) {
      if (!files.includes(name)) {
        throw new Error(`Applied migration is missing from the folder: ${name}`);
      }
    }
    for (const file of files) {
      if (applied.has(file)) {
        const sql = fs.readFileSync(path.join(dir, file), 'utf8');
        if (checksum(sql) !== applied.get(file)) {
          throw new Error(
            `${file} has been modified since it was applied. ` +
              'Never edit an applied migration; create a new one instead.'
          );
        }
      }
    }

    // Apply the pending ones, one transaction each.
    let count = 0;
    for (const file of files) {
      if (applied.has(file)) continue;

      const sql = fs.readFileSync(path.join(dir, file), 'utf8');
      try {
        await client.query('BEGIN');
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (filename, checksum) VALUES ($1, $2)', [
          file,
          checksum(sql),
        ]);
        await client.query('COMMIT');
        console.log(`Applied: ${file}`);
        count += 1;
      } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw new Error(`Migration ${file} failed and was rolled back: ${err.message}`);
      }
    }

    console.log(count === 0 ? 'No pending migrations.' : `Done. Applied ${count} migration(s).`);
  } finally {
    if (locked) {
      await client.query('SELECT pg_advisory_unlock($1)', [ADVISORY_LOCK_KEY]).catch(() => {});
    }
    client.release();
  }
}

run()
  .catch((err) => {
    console.error(`Migration error: ${err.message}`);
    process.exitCode = 1; // non-zero exit code = "failed" for scripts and CI
  })
  .finally(() => pool.end());