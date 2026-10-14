import { callProc, select, listView } from "../utils/db.js";
import { parseId, queryEnum, queryId, likeParam, queryString } from "../utils/validate.js";
import { requireStaff } from "../utils/guard.js";
import { notFound } from "../utils/httpError.js";

export const listFines = async (req, res) => {
  await requireStaff(req.db);
  const status = queryEnum(req.query, "status", ["unpaid", "paid"]);
  const user_id = queryId(req.query, "user_id");
  const q = queryString(req.query, "q");

  const where = [];
  const params = [];
  if (status) { where.push("payment_status = ?"); params.push(status); }
  if (user_id) { where.push("user_id = ?"); params.push(user_id); }
  if (q) { where.push("member_name LIKE ?"); params.push(likeParam(q)); }

  const { rows, meta } = await listView(req.db, "vw_detail_denda", { where, params, orderBy: "fine_id DESC", query: req.query });
  res.json({ data: rows, meta });
};

export const getFine = async (req, res) => {
  await requireStaff(req.db);
  const id = parseId(req.params.id, "id");
  const rows = await select(req.db, "SELECT * FROM vw_detail_denda WHERE fine_id = ?", [id]);
  if (!rows.length) throw notFound("Denda tidak ditemukan");
  res.json({ data: rows[0] });
};

export const payFine = async (req, res) => {
  const id = parseId(req.params.id, "id");
  await callProc(req.db, "sp_membayar_denda", [id]);
  const rows = await select(req.db, "SELECT * FROM vw_detail_denda WHERE fine_id = ?", [id]);
  res.json({ message: "Denda berhasil dibayar", data: rows[0] });
};
