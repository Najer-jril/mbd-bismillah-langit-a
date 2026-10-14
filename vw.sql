USE mbd_uts;

DROP VIEW IF EXISTS vw_sesi_saya, vw_katalog_buku, vw_penulis_buku,
                    vw_riwayat_saya, vw_denda_saya, vw_kuota_saya,
                    vw_akun_user, vw_status_buku, vw_detail_peminjaman, vw_detail_denda, vw_audit_stok;

-- all role
-- vw_sesi_saya untuk melihat siapa yang sedang login di koneksi ini
CREATE VIEW vw_sesi_saya AS
SELECT u.id AS user_id, u.name, u.email, u.role, u.status, s.login_at
FROM user_sessions s
JOIN users u ON u.id = s.user_id
WHERE s.connection_id = CONNECTION_ID()
  AND u.status <> 'inactive';

-- vw_katalog_buku untuk melihat katalog buku yang belum dihapus (semua role, wajib login)
CREATE VIEW vw_katalog_buku AS
SELECT b.id AS book_id,
       b.title,
       b.author,
       b.isbn,
       b.genre,
       b.available_stock,
       IF(b.available_stock > 0, 'tersedia', 'habis') AS availability
FROM books b
WHERE b.deleted_at IS NULL
  AND EXISTS (SELECT 1 FROM user_sessions s JOIN users su ON su.id = s.user_id
               WHERE s.connection_id = CONNECTION_ID() AND su.status <> 'inactive');

-- vw_penulis_buku untuk melihat daftar penulis per buku beserta urutannya (semua role, wajib login)
CREATE VIEW vw_penulis_buku AS
SELECT ba.book_id, ba.author_order, a.id AS author_id, a.name AS author_name
FROM book_authors ba
JOIN authors a ON a.id = ba.author_id
WHERE EXISTS (SELECT 1 FROM user_sessions s JOIN users su ON su.id = s.user_id
               WHERE s.connection_id = CONNECTION_ID() AND su.status <> 'inactive');

-- member only
-- vw_riwayat_saya untuk member melihat riwayat peminjaman miliknya user sendiri (+ status terlambat & estimasi denda)
CREATE VIEW vw_riwayat_saya AS
SELECT l.id AS loan_id,
       b.title,
       b.author,
       l.created_at AS requested_at,
       l.loan_date,
       l.due_date,
       l.return_date,
       l.status,
       (l.status = 'borrowed' AND l.due_date < CURDATE()) AS is_late,
       fn_hari_terlambat(l.due_date, IF(l.status = 'borrowed', CURDATE(), l.return_date)) AS days_late,
       fn_hitung_denda (l.due_date, IF(l.status = 'borrowed', CURDATE(), l.return_date)) AS fine_estimate
FROM loans l
JOIN books b ON b.id = l.book_id
WHERE l.user_id = (SELECT s.user_id FROM user_sessions s WHERE s.connection_id = CONNECTION_ID());

-- vw_denda_saya untuk member melihat denda miliknya user sendiri
CREATE VIEW vw_denda_saya AS
SELECT f.id AS fine_id,
       f.loan_id,
       l.book_id,
       l.due_date,
       l.return_date,
       fn_hari_terlambat(l.due_date, l.return_date) AS days_late,
       f.amount,
       f.payment_status,
       f.created_at AS fined_at
FROM fines f
JOIN loans l ON l.id = f.loan_id
WHERE l.user_id = (SELECT s.user_id FROM user_sessions s WHERE s.connection_id = CONNECTION_ID());

-- vw_kuota_saya untuk member melihat limit pinjam: pinjaman aktif, sisa kuota, jumlah terlambat, total denda belum dibayar
CREATE VIEW vw_kuota_saya AS
SELECT u.id AS user_id,
       u.name,
       u.status,
       fn_jumlah_pinjaman_aktif(u.id)   AS active_loans,
       fn_ambil_setting('MAX_PINJAM_AKTIF') AS max_loans,
       fn_sisa_kuota_pinjam(u.id)       AS remaining_quota,
       fn_jumlah_terlambat(u.id)        AS late_loans,
       fn_total_denda_belum_bayar(u.id) AS unpaid_fines
FROM users u
WHERE u.role = 'member'
  AND u.id = (SELECT s.user_id FROM user_sessions s WHERE s.connection_id = CONNECTION_ID());

-- staff n admin
-- vw_akun_user untuk staff/admin melihat semua akun (tanpa password)
CREATE VIEW vw_akun_user AS
SELECT u.id AS user_id,
       u.name,
       u.email,
       u.role,
       u.status,
       IF(u.role = 'member', fn_jumlah_pinjaman_aktif(u.id),   NULL) AS active_loans,
       IF(u.role = 'member', fn_total_denda_belum_bayar(u.id), NULL) AS unpaid_fines,
       u.created_at
FROM users u
WHERE EXISTS (SELECT 1 FROM user_sessions s JOIN users su ON su.id = s.user_id
               WHERE s.connection_id = CONNECTION_ID()
                 AND su.status = 'active' AND su.role IN ('staff','admin'));

-- vw_status_buku untuk staff/admin melihat stok semua buku, termasuk yang sudah dihapus
CREATE VIEW vw_status_buku AS
SELECT b.id AS book_id,
       b.title,
       b.author,
       b.isbn,
       b.total_stock,
       b.available_stock,
       b.total_stock - b.available_stock AS in_use,          -- dipinjam + di-reserve (pending)
       CASE
           WHEN b.deleted_at IS NOT NULL THEN 'dihapus'
           WHEN b.available_stock = 0    THEN 'habis'
           ELSE 'tersedia'
       END AS book_state,
       b.deleted_at
FROM books b
WHERE EXISTS (SELECT 1 FROM user_sessions s JOIN users su ON su.id = s.user_id
               WHERE s.connection_id = CONNECTION_ID()
                 AND su.status = 'active' AND su.role IN ('staff','admin'));

-- vw_detail_peminjaman untuk staff/admin melihat semua peminjaman: antrian ACC (status = 'pending'),
-- monitoring, dan yang terlambat
CREATE VIEW vw_detail_peminjaman AS
SELECT l.id AS loan_id,
       l.user_id,
       l.book_id,
       b.title,
       l.processed_by,
       l.created_at AS requested_at,
       l.loan_date,
       l.due_date,
       l.return_date,
       l.status,
       (l.status = 'borrowed' AND l.due_date < CURDATE()) AS is_late,
       fn_hari_terlambat(l.due_date, IF(l.status = 'borrowed', CURDATE(), l.return_date)) AS days_late,
       fn_hitung_denda (l.due_date, IF(l.status = 'borrowed', CURDATE(), l.return_date)) AS fine_estimate
FROM loans l
JOIN books b ON b.id = l.book_id
WHERE EXISTS (SELECT 1 FROM user_sessions s JOIN users su ON su.id = s.user_id
               WHERE s.connection_id = CONNECTION_ID()
                 AND su.status = 'active' AND su.role IN ('staff','admin'));

-- vw_detail_denda untuk staff/admin melihat semua denda (untuk pelunasan di loket)
CREATE VIEW vw_detail_denda AS
SELECT f.id AS fine_id,
       f.loan_id,
       l.user_id,
       l.book_id,
       l.due_date,
       l.return_date,
       fn_hari_terlambat(l.due_date, l.return_date) AS days_late,
       f.amount,
       f.payment_status,
       f.created_at AS fined_at,
       f.updated_at AS last_update
FROM fines f
JOIN loans l ON l.id = f.loan_id
WHERE EXISTS (SELECT 1 FROM user_sessions s JOIN users su ON su.id = s.user_id
               WHERE s.connection_id = CONNECTION_ID()
                 AND su.status = 'active' AND su.role IN ('staff','admin'));

-- vw_audit_stok untuk staff/admin mengecek konsistensi stok; normalnya 0 baris
CREATE VIEW vw_audit_stok AS
SELECT b.id AS book_id,
       b.title,
       b.total_stock,
       b.available_stock,
       b.total_stock - b.available_stock AS in_use_by_stock,
       COALESCE(x.active_loans, 0)       AS in_use_by_loans
FROM books b
LEFT JOIN (SELECT book_id, COUNT(*) AS active_loans
             FROM loans
            WHERE status IN ('pending','borrowed')
            GROUP BY book_id) x ON x.book_id = b.id
WHERE b.total_stock - b.available_stock <> COALESCE(x.active_loans, 0)
  AND EXISTS (SELECT 1 FROM user_sessions s JOIN users su ON su.id = s.user_id
               WHERE s.connection_id = CONNECTION_ID()
                 AND su.status = 'active' AND su.role IN ('staff','admin'));