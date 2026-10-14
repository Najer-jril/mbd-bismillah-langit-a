import { select, listView } from "../utils/db.js";
import { parseId, queryString, queryEnum, likeParam } from "../utils/validate.js";
import { requireStaff } from "../utils/guard.js";
import { notFound } from "../utils/httpError.js";

export const listBookStatus = async (req, res) => {
  await requireStaff(req.db);
  const state = queryEnum(req.query, "state", ["tersedia", "habis", "dihapus"]);
  const q = queryString(req.query, "q");

  const where = [];
  const params = [];
  if (state) { where.push("book_state = ?"); params.push(state); }
  if (q) { where.push("(title LIKE ? OR author LIKE ?)"); params.push(likeParam(q), likeParam(q)); }

  const { rows, meta } = await listView(req.db, "vw_status_buku", { where, params, orderBy: "book_id", query: req.query });
  res.json({ data: rows, meta });
};

export const getBookStatusAudit = async (req, res) => {
  await requireStaff(req.db);
  const rows = await select(req.db, "SELECT * FROM vw_audit_stok");
  res.json({ data: rows });
};

export const getBookStatus = async (req, res) => {
  await requireStaff(req.db);
  const id = parseId(req.params.id, "id");
  const rows = await select(req.db, "SELECT * FROM vw_status_buku WHERE book_id = ?", [id]);
  if (!rows.length) throw notFound("Buku tidak ditemukan");
  res.json({ data: rows[0] });
};
