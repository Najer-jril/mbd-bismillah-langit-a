import { HttpError } from "../utils/httpError.js";

const RULES = [
    [401, /^(Belum login|Sesi tidak valid|Email atau password salah)/],
    [403, /^(Akses ditolak|Hanya member yang dapat|Akun sedang disuspend|Tidak bisa mengubah status akun sendiri)/],
    [422, /^(Daftar penulis|Status suspended hanya)/],
    [404, /tidak ditemukan/i],
    [409, /(Duplicate entry|sudah|masih|Masih|^Kuota|^Stok buku habis|^Stok total|^Judul ini|^Hanya pengajuan|^Hanya pinjaman|^Transisi|Check constraint|pengajuan harus ditolak)/],
    [422, /(wajib|^Format|minimal|harus|tidak boleh kosong)/],
];

const DB_ERRNO = (n) => (n >= 5001 && n <= 5099) || n === 1644 || n === 3819;

const cleanMessage = (msg) =>
    msg
        .replace(/^\[[a-z_]+\]\s*/, "")
        .replace(/ for key '[^']+'/, "");

export function notFoundRoute(req, res) {
    res.status(404).json({ message: `Endpoint ${req.method} ${req.originalUrl} tidak ditemukan` });
}

export function errorHandler(err, req, res, next) {
    if (err instanceof HttpError) {
        return res.status(err.status).json({ message: err.message });
    }
    if (err.type === "entity.parse.failed") {
        return res.status(400).json({ message: "Body JSON tidak valid" });
    }
    if (err.type === "entity.too.large") {
        return res.status(413).json({ message: "Body terlalu besar" });
    }
    if (DB_ERRNO(err.errno) && err.sqlMessage) {
        const message = cleanMessage(err.sqlMessage);
        const rule = RULES.find(([, re]) => re.test(message));
        return res.status(rule ? rule[0] : 409).json({ message }); // sisa = pelanggaran aturan bisnis
    }

    console.error(err);
    return res.status(500).json({ message: "Terjadi kesalahan pada server" });
}