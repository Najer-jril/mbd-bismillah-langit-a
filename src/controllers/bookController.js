import { callProc, select, listView } from "../utils/db.js";
import { body, requireString, requireInt, requireIntArray, optionalStringArray, parseId, queryString, queryFlag, likeParam } from "../utils/validate.js";
import { notFound, badRequest } from "../utils/httpError.js";

export const listBooks = async (req, res) => {
  const q = queryString(req.query, "q");
  const genre = queryString(req.query, "genre");
  const available = queryFlag(req.query, "available");

  const where = [];
  const params = [];
  if (q) {
    if (q.length >= 3) {
      where.push("MATCH(title, author) AGAINST (? IN NATURAL LANGUAGE MODE)");
      params.push(q);
    } else {
      where.push("(title LIKE ? OR author LIKE ?)");
      params.push(likeParam(q), likeParam(q));
    }
  }
  if (genre) { where.push("? MEMBER OF (genre)"); params.push(genre); }
  if (available) { where.push("available_stock > 0"); }

  const { rows, meta } = await listView(req.db, "vw_katalog_buku", { where, params, orderBy: "title", query: req.query });
  res.json({ data: rows, meta });
};

export const getBook = async (req, res) => {
  const id = parseId(req.params.id, "id");
  const rows = await select(req.db, "SELECT * FROM vw_katalog_buku WHERE book_id = ?", [id]);
  if (!rows.length) throw notFound("Buku tidak ditemukan");
  const authors = await select(
    req.db,
    "SELECT author_id, author_name, author_order FROM vw_penulis_buku WHERE book_id = ? ORDER BY author_order",
    [id]
  );
  res.json({ data: { ...rows[0], authors } });
};

export const getBookEligibility = async (req, res) => {
  const id = parseId(req.params.id, "id");
  const [[row]] = await req.db.query("SELECT fn_pinjaman_valid(?) AS result", [id]);
  const result = row.result;
  res.json({ data: { book_id: id, eligible: result === "OK", reason: result === "OK" ? null : result } });
};

export const createBook = async (req, res) => {
  const b = body(req);
  const title = requireString(b, "title");
  const isbn = requireString(b, "isbn");
  const total_stock = requireInt(b, "total_stock");
  const genre = optionalStringArray(b, "genre");
  const author_ids = requireIntArray(b, "author_ids");

  const { out } = await callProc(req.db, "sp_menambah_buku", [title, isbn, total_stock, genre, author_ids], ["book_id"]);
  res.status(201).json({ data: { book_id: out.book_id } });
};

export const updateBook = async (req, res) => {
  const id = parseId(req.params.id, "id");
  const b = body(req);
  const title = b.title === undefined ? null : requireString(b, "title");
  const isbn = b.isbn === undefined ? null : requireString(b, "isbn");
  const total_stock = b.total_stock === undefined ? null : requireInt(b, "total_stock");
  const genre = b.genre === undefined ? null : optionalStringArray(b, "genre") ?? [];
  const author_ids = b.author_ids === undefined ? null : requireIntArray(b, "author_ids");

  if (title === null && isbn === null && total_stock === null && genre === null && author_ids === null) {
    throw badRequest("Setidaknya satu field wajib diisi");
  }

  await callProc(req.db, "sp_mengedit_detail_buku", [id, title, isbn, total_stock, genre, author_ids]);
  res.json({ message: "Buku berhasil diubah" });
};

export const deleteBook = async (req, res) => {
  const id = parseId(req.params.id, "id");
  await callProc(req.db, "sp_menghapus_buku", [id]);
  res.json({ message: "Buku berhasil dihapus" });
};
