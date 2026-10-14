import { callProc, select } from "../utils/db.js";
import { body, requireString } from "../utils/validate.js";
import { generateToken, sha256 } from "../utils/token.js";

export const login = async (req, res) => {
  const b = body(req);
  const email = requireString(b, "email");
  const password = requireString(b, "password");

  const { rows } = await callProc(req.db, "sp_login", [email, password]);
  const { message, ...user } = rows[0];

  const token = generateToken();
  const { rows: tokenRows } = await callProc(req.db, "sp_token_buat", [sha256(token)]);

  res.json({
    message: "Login berhasil",
    data: { token, expires_at: tokenRows[0].expires_at, user },
  });
};

export const logout = async (req, res) => {
  await callProc(req.db, "sp_logout", [req.tokenHash]);
  res.json({ message: "Logout berhasil" });
};

export const me = async (req, res) => {
  const rows = await select(req.db, "SELECT * FROM vw_sesi_saya");
  res.json({ data: rows[0] });
};
