import { callProc, select, listView } from "../utils/db.js";
import { body, requireString, parseId, queryString, queryEnum, likeParam } from "../utils/validate.js";
import { requireStaff } from "../utils/guard.js";
import { notFound } from "../utils/httpError.js";

export const createUser = async (req, res) => {
  const b = body(req);
  const name = requireString(b, "name");
  const email = requireString(b, "email");
  const password = requireString(b, "password");
  const role = requireString(b, "role");

  const { out } = await callProc(req.db, "sp_membuat_akun", [name, email, password, role], ["user_id"]);
  res.status(201).json({ data: { user_id: out.user_id } });
};

export const updateUserStatus = async (req, res) => {
  const id = parseId(req.params.id, "id");
  const status = requireString(body(req), "status");

  const { out } = await callProc(req.db, "sp_ubah_status_akun", [id, status], ["pending_ditolak"]);
  res.json({ data: { user_id: id, status, pending_rejected: out.pending_ditolak } });
};

export const listUsers = async (req, res) => {
  await requireStaff(req.db);
  const role = queryEnum(req.query, "role", ["admin", "staff", "member"]);
  const status = queryEnum(req.query, "status", ["active", "suspended", "inactive"]);
  const q = queryString(req.query, "q");

  const where = [];
  const params = [];
  if (role) { where.push("role = ?"); params.push(role); }
  if (status) { where.push("status = ?"); params.push(status); }
  if (q) { where.push("(name LIKE ? OR email LIKE ?)"); params.push(likeParam(q), likeParam(q)); }

  const { rows, meta } = await listView(req.db, "vw_akun_user", { where, params, orderBy: "user_id", query: req.query });
  res.json({ data: rows, meta });
};

export const getUser = async (req, res) => {
  await requireStaff(req.db);
  const id = parseId(req.params.id, "id");
  const rows = await select(req.db, "SELECT * FROM vw_akun_user WHERE user_id = ?", [id]);
  if (!rows.length) throw notFound("User tidak ditemukan");
  res.json({ data: rows[0] });
};
