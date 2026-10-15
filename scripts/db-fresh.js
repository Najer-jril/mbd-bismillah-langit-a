import "dotenv/config";
import fs from "node:fs";
import mysql from "mysql2/promise";

const DB = process.env.DB_NAME || "mbd_uts";
if (!/^[A-Za-z0-9_]+$/.test(DB)) {
  console.error(`✖ DB_NAME tidak valid: ${JSON.stringify(DB)}. Hanya huruf, angka, dan underscore.`);
  process.exit(1);
}
const FILES = ["schemas", "seeder", "functions", "triggers", "store_procedures", "views"];

if (process.env.NODE_ENV === "production" && !process.argv.includes("--force")) {
  console.error("NODE_ENV=production: db:fresh menghapus seluruh database. Pakai --force bila disengaja.");
  process.exit(1);
}

const fail = (msg) => { console.error(`✖ ${msg}`); process.exit(1); };

const conn = await mysql.createConnection({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.MIGRATE_USER || process.env.DB_USER,
  password: process.env.MIGRATE_PASSWORD ?? process.env.DB_PASSWORD,
  multipleStatements: true,
}).catch((e) => fail(`Tidak bisa terhubung ke MySQL: [${e.code || e.errno}] ${e.sqlMessage || e.message}` +
  (e.errno === 1045 ? "\n  Petunjuk: cek DB_USER/DB_PASSWORD atau MIGRATE_USER/MIGRATE_PASSWORD di .env." : "") +
  (e.code === "ECONNREFUSED" ? "\n  Petunjuk: pastikan MySQL berjalan dan DB_HOST/DB_PORT benar." : "")));

try {
  await conn.query(`DROP DATABASE IF EXISTS \`${DB}\``);
  for (const f of FILES) {
    const sql = fs.readFileSync(new URL(`../queries/${f}.sql`, import.meta.url), "utf8").replace(/\bmbd_uts\b/g, DB);
    try {
      await conn.query(sql);
    } catch (e) {
      const hint = [1419, 1044, 1227].includes(e.errno)
        ? "\n  Petunjuk: isi MIGRATE_USER/MIGRATE_PASSWORD (mis. root) di .env, atau jalankan MySQL dengan --log-bin-trust-function-creators=1."
        : "";
      fail(`queries/${f}.sql: [${e.errno}] ${e.sqlMessage || e.message}${hint}`);
    }
    console.log(`  ${f}.sql done`);
  }
  const [[o]] = await conn.query(
    `SELECT (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=? AND table_type='BASE TABLE') t,
            (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema=? AND routine_type='FUNCTION') f,
            (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema=?) g,
            (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema=? AND routine_type='PROCEDURE') p,
            (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=? AND table_type='VIEW') v,
            (SELECT COUNT(*) FROM \`${DB}\`.users) u, (SELECT COUNT(*) FROM \`${DB}\`.books) b, (SELECT COUNT(*) FROM \`${DB}\`.loans) l`,
    [DB, DB, DB, DB, DB]);
  console.log(`${o.t} tabel, ${o.f} fn, ${o.g} trigger, ${o.p} SP, ${o.v} view, ${o.u} user, ${o.b} buku, ${o.l} pinjaman`);
} finally { await conn.end(); }