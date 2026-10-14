import { callProc, listView } from "../utils/db.js";
import { body, requireString, queryString, likeParam } from "../utils/validate.js";

export const listAuthors = async (req, res) => {
  const q = queryString(req.query, "q");
  const { rows, meta } = await listView(req.db, "vw_penulis", {
    where: q ? ["name LIKE ?"] : [], params: q ? [likeParam(q)] : [],
    orderBy: "name", query: req.query,
  });
  res.json({ data: rows, meta });
};

export const createAuthor = async (req, res) => {
  const name = requireString(body(req), "name");
  const { out } = await callProc(req.db, "sp_menambah_penulis", [name], ["author_id"]);
  res.status(201).json({ message: "Penulis berhasil ditambahkan", data: { author_id: out.author_id } });
};
