import "dotenv/config";
import app from "./app.js";
import pool from "../config/db.js";

const PORT = Number(process.env.PORT || 3000);

const server = app.listen(PORT, () => {
  console.log(`API berjalan di http://localhost:${PORT}/api`);
});

const shutdown = async () => {
  server.close();
  await pool.end();
  process.exit(0);
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);