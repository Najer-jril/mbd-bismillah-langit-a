import { callProc, select, listView } from "../utils/db.js";
import { body, requireInt, parseId, queryString, queryEnum, queryFlag, queryId, likeParam } from "../utils/validate.js";
import { requireStaff } from "../utils/guard.js";
import { notFound, badRequest } from "../utils/httpError.js";

export const createLoan = async (req, res) => {
  const book_id = requireInt(body(req), "book_id");
  const { out } = await callProc(req.db, "sp_meminjam_buku", [book_id], ["loan_id"]);
  res.status(201).json({ message: "Pengajuan pinjaman dibuat", data: { loan_id: out.loan_id, status: "pending" } });
};

export const listLoans = async (req, res) => {
  await requireStaff(req.db);
  const status = queryEnum(req.query, "status", ["pending", "borrowed", "returned", "rejected"]);
  const late = queryFlag(req.query, "late");
  const user_id = queryId(req.query, "user_id");
  const book_id = queryId(req.query, "book_id");
  const q = queryString(req.query, "q");

  const where = [];
  const params = [];
  if (status) { where.push("status = ?"); params.push(status); }
  if (late) { where.push("is_late = 1"); }
  if (user_id) { where.push("user_id = ?"); params.push(user_id); }
  if (book_id) { where.push("book_id = ?"); params.push(book_id); }
  if (q) { where.push("member_name LIKE ?"); params.push(likeParam(q)); }

  const orderBy = status === "pending" ? "requested_at ASC, loan_id ASC" : "loan_id DESC";

  const { rows, meta } = await listView(req.db, "vw_detail_peminjaman", { where, params, orderBy, query: req.query });
  res.json({ data: rows, meta });
};

export const getLoan = async (req, res) => {
  await requireStaff(req.db);
  const id = parseId(req.params.id, "id");
  const rows = await select(req.db, "SELECT * FROM vw_detail_peminjaman WHERE loan_id = ?", [id]);
  if (!rows.length) throw notFound("Pengajuan tidak ditemukan");
  res.json({ data: rows[0] });
};

export const approveLoan = async (req, res) => {
  const id = parseId(req.params.id, "id");
  await callProc(req.db, "sp_mengedit_status_peminjaman", [id, "approve"]);
  const rows = await select(req.db, "SELECT * FROM vw_detail_peminjaman WHERE loan_id = ?", [id]);
  res.json({ message: "Pengajuan disetujui", data: rows[0] });
};

export const rejectLoan = async (req, res) => {
  const id = parseId(req.params.id, "id");
  await callProc(req.db, "sp_mengedit_status_peminjaman", [id, "reject"]);
  const rows = await select(req.db, "SELECT * FROM vw_detail_peminjaman WHERE loan_id = ?", [id]);
  res.json({ message: "Pengajuan ditolak", data: rows[0] });
};

export const returnLoan = async (req, res) => {
  const id = parseId(req.params.id, "id");
  const b = body(req);
  let pay_fine = false;
  if (b.pay_fine !== undefined) {
    if (typeof b.pay_fine !== "boolean") throw badRequest("Field pay_fine wajib berupa boolean");
    pay_fine = b.pay_fine;
  }

  const { out } = await callProc(req.db, "sp_pengembalian_buku", [id, pay_fine ? 1 : 0], ["denda"]);
  const fine_amount = Number(out.denda);
  res.json({ data: { loan_id: id, fine_amount, fine_paid: pay_fine && fine_amount > 0 } });
};
