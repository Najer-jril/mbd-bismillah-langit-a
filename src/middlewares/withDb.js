import pool from "../../config/db.js";
import { sha256 } from "../utils/token.js";

export const withDb = (handler, { auth = true } = {}) => async (req, res, next) => {
  let conn;
  try {
    conn = await pool.getConnection();
    await conn.query("CALL sp_token_lepas()");

    if (auth) {
      const [type, token] = (req.headers.authorization || "").split(" ");
      if (type !== "Bearer" || !token) {
        return res.status(401).json({ message: "Belum login" });
      }
      req.tokenHash = sha256(token);
      await conn.query("CALL sp_token_pasang(?)", [req.tokenHash]);
    }

    req.db = conn;
    return await handler(req, res, next);
  } catch (err) {
    return next(err);
  } finally {
    if (conn) {
      try {
        await conn.query("CALL sp_token_lepas()");
        conn.release();
      } catch {
        conn.destroy();
      }
    }
  }
};