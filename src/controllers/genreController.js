import { select } from "../utils/db.js";

export const listGenres = async (req, res) => {
  const rows = await select(req.db, "SELECT genre FROM vw_genre ORDER BY genre");
  res.json({ data: rows.map((r) => r.genre) });
};
