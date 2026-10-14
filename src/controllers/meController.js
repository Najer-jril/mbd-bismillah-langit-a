import { select, listView } from "../utils/db.js";
import { parseId, queryEnum, queryFlag } from "../utils/validate.js";
import { HttpError } from "../utils/httpError.js";

export const getMyQuota = async (req, res) => {
  const rows = await select(req.db, "SELECT * FROM vw_kuota_saya");
  if (!rows.length) throw new HttpError(403, "Hanya member yang memiliki kuota pinjam");
  res.json({ data: rows[0] });
};

export const listMyLoans = async (req, res) => {
  const status = queryEnum(req.query, "status", ["pending", "borrowed", "returned", "rejected"]);
  const late = queryFlag(req.query, "late");

  const where = [];
  const params = [];
  if (status) { where.push("status = ?"); params.push(status); }
  if (late) { where.push("is_late = 1"); }

  const { rows, meta } = await listView(req.db, "vw_riwayat_saya", {
    where, params, orderBy: "requested_at DESC, loan_id DESC", query: req.query,
  });
  res.json({ data: rows, meta });
};

export const getMyLoan = async (req, res) => {
  const id = parseId(req.params.id, "id");
  const rows = await select(req.db, "SELECT * FROM vw_riwayat_saya WHERE loan_id = ?", [id]);
  if (!rows.length) throw new HttpError(404, "Pinjaman tidak ditemukan");
  res.json({ data: rows[0] });
};

export const listMyFines = async (req, res) => {
  const status = queryEnum(req.query, "status", ["unpaid", "paid"]);

  const where = [];
  const params = [];
  if (status) { where.push("payment_status = ?"); params.push(status); }

  const { rows, meta } = await listView(req.db, "vw_denda_saya", { where, params, orderBy: "fine_id DESC", query: req.query });
  res.json({ data: rows, meta });
};
