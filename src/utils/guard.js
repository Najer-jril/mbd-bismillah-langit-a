import { HttpError } from "./httpError.js";

export async function requireStaff(conn) {
  const [[row]] = await conn.query("SELECT fn_cek_akses('staff,admin') AS ok");
  if (!row.ok) throw new HttpError(403, "Akses ditolak: khusus staff/admin");
}
