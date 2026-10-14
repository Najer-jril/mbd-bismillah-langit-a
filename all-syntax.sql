USE perpustakaan;

-- 1. FUNCTIONS
DROP FUNCTION IF EXISTS fn_ambil_setting;
DROP FUNCTION IF EXISTS fn_hash_password;
DROP FUNCTION IF EXISTS fn_verifikasi_password;
DROP FUNCTION IF EXISTS fn_current_user_id;
DROP FUNCTION IF EXISTS fn_cek_akses;
DROP FUNCTION IF EXISTS fn_jumlah_pinjaman_aktif;
DROP FUNCTION IF EXISTS fn_sisa_kuota_pinjam;
DROP FUNCTION IF EXISTS fn_buku_tersedia;
DROP FUNCTION IF EXISTS fn_hari_terlambat;
DROP FUNCTION IF EXISTS fn_hitung_denda;
DROP FUNCTION IF EXISTS fn_total_denda_belum_bayar;
DROP FUNCTION IF EXISTS fn_jumlah_terlambat;
DROP FUNCTION IF EXISTS fn_pinjaman_valid;
DROP FUNCTION IF EXISTS fn_penulis_valid;

DELIMITER //

-- FN-1 Konstanta bisnis (hardcode, terpusat di satu tempat).
CREATE FUNCTION fn_ambil_setting(p_key VARCHAR(30))
RETURNS INT
DETERMINISTIC NO SQL
BEGIN
    RETURN CASE p_key
        WHEN 'MAX_PINJAM_AKTIF' THEN 3        -- pending + borrowed
        WHEN 'LAMA_PINJAM_HARI' THEN 7        -- dihitung sejak di-ACC
        WHEN 'TARIF_DENDA_HARI' THEN 1000     -- Rp per hari terlambat
        WHEN 'MAX_DENDA' THEN 50000    -- plafon denda per pinjaman
        WHEN 'MIN_PASSWORD' THEN 8        -- panjang minimal password
        ELSE NULL
    END;
END//

-- FN-2 Hash password: salt$SHA2(salt + password). Salt dibuat di SP (RANDOM_BYTES).
CREATE FUNCTION fn_hash_password(p_plain VARCHAR(255), p_salt CHAR(32))
RETURNS VARCHAR(255)
DETERMINISTIC NO SQL
BEGIN
    RETURN CONCAT(p_salt, '$', SHA2(CONCAT(p_salt, p_plain), 256));
END//

-- FN-3 Verifikasi password terhadap hash tersimpan. 1 = cocok.
CREATE FUNCTION fn_verifikasi_password(p_plain VARCHAR(255), p_stored VARCHAR(255))
RETURNS TINYINT
DETERMINISTIC NO SQL
BEGIN
    IF p_plain IS NULL OR p_stored IS NULL OR LOCATE('$', p_stored) = 0 THEN
        RETURN 0;
    END IF;
    RETURN IF(p_stored = fn_hash_password(p_plain, SUBSTRING_INDEX(p_stored, '$', 1)), 1, 0);
END//

-- FN-4 User yang sedang login di koneksi ini (NULL = belum login / akun inactive).
CREATE FUNCTION fn_current_user_id()
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_id INT DEFAULT NULL;
    SELECT s.user_id INTO v_id
      FROM user_sessions s
      JOIN users u ON u.id = s.user_id
     WHERE s.connection_id = CONNECTION_ID()
       AND u.status <> 'inactive';
    RETURN v_id;
END//

-- FN-5 User login berstatus active DAN role-nya ada di daftar CSV ('staff,admin').
CREATE FUNCTION fn_cek_akses(p_roles VARCHAR(50))
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_ok TINYINT DEFAULT 0;
    SELECT 1 INTO v_ok
      FROM user_sessions s
      JOIN users u ON u.id = s.user_id
     WHERE s.connection_id = CONNECTION_ID()
       AND u.status = 'active'
       AND FIND_IN_SET(u.role, p_roles) > 0;
    RETURN v_ok;
END//

-- FN-6 Jumlah pinjaman aktif (pending ikut dihitung karena stoknya sudah di-reserve).
CREATE FUNCTION fn_jumlah_pinjaman_aktif(p_user_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_jml INT DEFAULT 0;
    SELECT COUNT(*) INTO v_jml
      FROM loans
     WHERE user_id = p_user_id
       AND status IN ('pending','borrowed');          -- idx_loans_user_status
    RETURN v_jml;
END//

-- FN-7 Sisa kuota pinjam (UC: melihat cek limit pinjam buku).
CREATE FUNCTION fn_sisa_kuota_pinjam(p_user_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    RETURN GREATEST(fn_ambil_setting('MAX_PINJAM_AKTIF') - fn_jumlah_pinjaman_aktif(p_user_id), 0);
END//

-- FN-8 Buku bisa dipinjam? 1 = ada, tidak dihapus, stok > 0 (UC: cek ketersediaan stok).
CREATE FUNCTION fn_buku_tersedia(p_book_id INT)
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_oke TINYINT DEFAULT 0;
    SELECT 1 INTO v_oke
      FROM books
     WHERE id = p_book_id
       AND deleted_at IS NULL
       AND available_stock > 0;
    RETURN v_oke;
END//

-- FN-9 Hari terlambat (kalkulasi murni).
CREATE FUNCTION fn_hari_terlambat(p_due_date DATE, p_return_date DATE)
RETURNS INT
DETERMINISTIC NO SQL
BEGIN
    IF p_due_date IS NULL OR p_return_date IS NULL THEN
        RETURN 0;
    END IF;
    RETURN GREATEST(DATEDIFF(p_return_date, p_due_date), 0);
END//

-- FN-10 Denda = hari terlambat x tarif, dibatasi plafon (UC: menghitung denda keterlambatan).
CREATE FUNCTION fn_hitung_denda(p_due_date DATE, p_return_date DATE)
RETURNS DECIMAL(10,2)
DETERMINISTIC NO SQL
BEGIN
    RETURN LEAST(fn_hari_terlambat(p_due_date, p_return_date) * fn_ambil_setting('TARIF_DENDA_HARI'),
                 fn_ambil_setting('MAX_DENDA'));
END//

-- FN-11 Total denda belum dibayar milik user.
CREATE FUNCTION fn_total_denda_belum_bayar(p_user_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT 0;
    SELECT COALESCE(SUM(f.amount), 0) INTO v_total
      FROM loans l
      JOIN fines f ON f.loan_id = l.id
     WHERE l.user_id = p_user_id
       AND f.payment_status = 'unpaid';
    RETURN v_total;
END//

-- FN-12 Jumlah buku yang sedang dipinjam dan sudah lewat jatuh tempo.
CREATE FUNCTION fn_jumlah_terlambat(p_user_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_jml INT DEFAULT 0;
    SELECT COUNT(*) INTO v_jml
      FROM loans
     WHERE user_id = p_user_id
       AND status = 'borrowed'
       AND due_date < CURDATE();
    RETURN v_jml;
END//

-- FN-13 GATE pinjam untuk user yang SEDANG LOGIN. 'OK' atau alasan penolakan.
--       Dipakai UI ("langsung cek ui") DAN di dalam sp_meminjam_buku -> 1 sumber aturan.
CREATE FUNCTION fn_pinjaman_valid(p_book_id INT)
RETURNS VARCHAR(100)
READS SQL DATA
BEGIN
    DECLARE v_uid INT DEFAULT NULL;
    DECLARE v_role VARCHAR(10);
    DECLARE v_status VARCHAR(10);
    DECLARE v_book INT DEFAULT NULL;

    SET v_uid = fn_current_user_id();
    IF v_uid IS NULL THEN RETURN 'Belum login'; END IF;

    SELECT role, status INTO v_role, v_status FROM users WHERE id = v_uid;
    IF v_role <> 'member' THEN RETURN 'Hanya member yang dapat meminjam buku'; END IF;
    IF v_status = 'suspended' THEN RETURN 'Akun sedang disuspend'; END IF;
    IF fn_sisa_kuota_pinjam(v_uid) = 0 THEN
        RETURN CONCAT('Kuota pinjam habis (maks ', fn_ambil_setting('MAX_PINJAM_AKTIF'), ' aktif)');
    END IF;
    IF fn_total_denda_belum_bayar(v_uid) > 0 THEN RETURN 'Masih ada denda yang belum dibayar'; END IF;
    IF fn_jumlah_terlambat(v_uid) > 0 THEN RETURN 'Masih ada buku yang terlambat dikembalikan'; END IF;

    SELECT id INTO v_book FROM books WHERE id = p_book_id AND deleted_at IS NULL;
    IF v_book IS NULL THEN RETURN 'Buku tidak ditemukan'; END IF;

    IF EXISTS (SELECT 1 FROM loans
                WHERE user_id = v_uid AND book_id = p_book_id
                  AND status IN ('pending','borrowed')) THEN
        RETURN 'Judul ini sedang Anda pinjam / ajukan';
    END IF;
    IF fn_buku_tersedia(p_book_id) = 0 THEN RETURN 'Stok buku habis'; END IF;

    RETURN 'OK';
END//

-- FN-14 Validasi daftar penulis (JSON array id): tidak kosong, semua ada, tidak duplikat.
CREATE FUNCTION fn_penulis_valid(p_author_ids JSON)
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_input INT DEFAULT 0;
    DECLARE v_unik  INT DEFAULT 0;
    DECLARE v_ada   INT DEFAULT 0;

    IF p_author_ids IS NULL OR JSON_TYPE(p_author_ids) <> 'ARRAY' OR JSON_LENGTH(p_author_ids) = 0 THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*), COUNT(DISTINCT jt.aid), COUNT(a.id)
      INTO v_input, v_unik, v_ada
      FROM JSON_TABLE(p_author_ids, '$[*]' COLUMNS (aid INT PATH '$')) jt
      LEFT JOIN authors a ON a.id = jt.aid;

    RETURN IF(v_input = v_unik AND v_input = v_ada, 1, 0);
END//

DELIMITER ;

-- 2. TRIGGERS
-- Trigger = aturan data yang berlaku untuk SEMUA jalur (SP maupun DML
-- langsung). Alur bisnis tetap di SP.
DROP TRIGGER IF EXISTS trg_users_before_insert_guard;
DROP TRIGGER IF EXISTS trg_users_before_update_guard;
DROP TRIGGER IF EXISTS trg_users_before_delete_block;
DROP TRIGGER IF EXISTS trg_authors_after_update_sync;
DROP TRIGGER IF EXISTS trg_book_authors_after_insert_sync;
DROP TRIGGER IF EXISTS trg_book_authors_after_delete_sync;
DROP TRIGGER IF EXISTS trg_books_before_insert_stock;
DROP TRIGGER IF EXISTS trg_books_before_update_stock;
DROP TRIGGER IF EXISTS trg_books_before_delete_block;
DROP TRIGGER IF EXISTS trg_loans_before_insert_guard;
DROP TRIGGER IF EXISTS trg_loans_before_update_status;
DROP TRIGGER IF EXISTS trg_loans_after_update_fine;
DROP TRIGGER IF EXISTS trg_loans_after_update_stock;
DROP TRIGGER IF EXISTS trg_loans_before_delete_block;
DROP TRIGGER IF EXISTS trg_fines_before_insert_guard;
DROP TRIGGER IF EXISTS trg_fines_before_update_lock;
DROP TRIGGER IF EXISTS trg_fines_before_delete_block;

DELIMITER //

-- ------------------------------------------------------------- USERS
-- TRG-1 Normalisasi email, password wajib ter-hash, suspended khusus member.
CREATE TRIGGER trg_users_before_insert_guard
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    SET NEW.email = LOWER(TRIM(NEW.email));
    IF NEW.password NOT REGEXP '^[0-9a-f]{32}[$][0-9a-f]{64}$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Password harus disimpan dalam format hash (salt$sha256)';
    END IF;
    IF NEW.status = 'suspended' AND NEW.role <> 'member' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status suspended hanya untuk member';
    END IF;
END//

-- TRG-2 Role permanen, admin aktif terakhir dilindungi, aturan status & password.
CREATE TRIGGER trg_users_before_update_guard
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    SET NEW.email = LOWER(TRIM(NEW.email));

    IF NEW.role <> OLD.role THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Role akun tidak dapat diubah setelah dibuat';
    END IF;
    IF NEW.password <> OLD.password AND NEW.password NOT REGEXP '^[0-9a-f]{32}[$][0-9a-f]{64}$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Password harus disimpan dalam format hash (salt$sha256)';
    END IF;
    IF NEW.status = 'suspended' AND NEW.role <> 'member' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status suspended hanya untuk member';
    END IF;
    IF OLD.role = 'admin' AND OLD.status = 'active' AND NEW.status <> 'active'
       AND NOT EXISTS (SELECT 1 FROM users
                        WHERE role = 'admin' AND status = 'active' AND id <> OLD.id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admin aktif terakhir tidak boleh dinonaktifkan';
    END IF;
END//

-- TRG-3 User tidak boleh dihapus permanen (gunakan status inactive).
CREATE TRIGGER trg_users_before_delete_block
BEFORE DELETE ON users
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User tidak boleh dihapus, gunakan status inactive';
END//

-- ------------------------------------------------------------- AUTHORS
-- TRG-4 Nama penulis berubah -> refresh books.author semua bukunya.
CREATE TRIGGER trg_authors_after_update_sync
AFTER UPDATE ON authors
FOR EACH ROW
BEGIN
    IF NEW.name <> OLD.name THEN
        UPDATE books b
           SET b.author = (SELECT LEFT(GROUP_CONCAT(a.name ORDER BY ba.author_order SEPARATOR ', '), 200)
                             FROM book_authors ba JOIN authors a ON a.id = ba.author_id
                            WHERE ba.book_id = b.id)
         WHERE b.id IN (SELECT book_id FROM book_authors WHERE author_id = NEW.id);
    END IF;
END//

-- TRG-5 Penulis ditautkan ke buku -> refresh books.author.
CREATE TRIGGER trg_book_authors_after_insert_sync
AFTER INSERT ON book_authors
FOR EACH ROW
BEGIN
    UPDATE books
       SET author = (SELECT LEFT(GROUP_CONCAT(a.name ORDER BY ba.author_order SEPARATOR ', '), 200)
                       FROM book_authors ba JOIN authors a ON a.id = ba.author_id
                      WHERE ba.book_id = NEW.book_id)
     WHERE id = NEW.book_id;
END//

-- TRG-6 Penulis dilepas dari buku -> refresh books.author.
CREATE TRIGGER trg_book_authors_after_delete_sync
AFTER DELETE ON book_authors
FOR EACH ROW
BEGIN
    UPDATE books
       SET author = COALESCE((SELECT LEFT(GROUP_CONCAT(a.name ORDER BY ba.author_order SEPARATOR ', '), 200)
                                FROM book_authors ba JOIN authors a ON a.id = ba.author_id
                               WHERE ba.book_id = OLD.book_id), '')
     WHERE id = OLD.book_id;
END//

-- ------------------------------------------------------------- BOOKS
-- TRG-7 Buku baru: semua eksemplar tersedia (nilai available_stock dari input diabaikan).
CREATE TRIGGER trg_books_before_insert_stock
BEFORE INSERT ON books
FOR EACH ROW
BEGIN
    IF NEW.total_stock < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'total_stock tidak boleh negatif';
    END IF;
    SET NEW.available_stock = NEW.total_stock;
    SET NEW.deleted_at      = NULL;
END//

-- TRG-8 total_stock berubah -> available_stock ikut bergeser sebesar delta.
--       Buku yang sudah dihapus dibekukan (kecuali refresh nama penulis).
CREATE TRIGGER trg_books_before_update_stock
BEFORE UPDATE ON books
FOR EACH ROW
BEGIN
    IF OLD.deleted_at IS NOT NULL
       AND (NEW.deleted_at IS NULL
            OR NEW.total_stock <> OLD.total_stock OR NEW.available_stock <> OLD.available_stock
            OR NEW.title <> OLD.title OR NEW.isbn <> OLD.isbn) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Buku sudah dihapus dan tidak dapat diubah';
    END IF;

    IF NEW.total_stock <> OLD.total_stock THEN
        SET NEW.available_stock = OLD.available_stock + (NEW.total_stock - OLD.total_stock);
        IF NEW.available_stock < 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Stok total tidak boleh kurang dari eksemplar yang sedang dipinjam/diajukan';
        END IF;
    END IF;
END//

-- TRG-9 Hapus permanen dilarang -> wajib sp_delete_book (soft delete).
CREATE TRIGGER trg_books_before_delete_block
BEFORE DELETE ON books
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Buku tidak boleh dihapus permanen, gunakan sp_delete_book';
END//

-- ------------------------------------------------------------- LOANS
-- TRG-10 Pinjaman baru wajib lahir sebagai pengajuan pending milik member.
CREATE TRIGGER trg_loans_before_insert_guard
BEFORE INSERT ON loans
FOR EACH ROW
BEGIN
    IF NEW.status <> 'pending' OR NEW.processed_by IS NOT NULL OR NEW.return_date IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Pinjaman baru harus berstatus pending tanpa processed_by & return_date';
    END IF;
    IF (SELECT role FROM users WHERE id = NEW.user_id) <> 'member' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Peminjam harus akun member';
    END IF;
END//

-- TRG-11 State machine:  pending -> borrowed | rejected,  borrowed -> returned.
CREATE TRIGGER trg_loans_before_update_status
BEFORE UPDATE ON loans
FOR EACH ROW
BEGIN
    IF NEW.user_id <> OLD.user_id OR NEW.book_id <> OLD.book_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'user_id/book_id pinjaman tidak boleh diubah';
    END IF;

    IF NEW.status <> OLD.status AND NOT (
           (OLD.status = 'pending'  AND NEW.status IN ('borrowed','rejected'))
        OR (OLD.status = 'borrowed' AND NEW.status = 'returned')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Transisi status tidak valid (pending->borrowed/rejected, borrowed->returned)';
    END IF;

    IF OLD.status = 'pending' AND NEW.status IN ('borrowed','rejected') THEN
        IF NEW.processed_by IS NULL
           OR (SELECT role FROM users WHERE id = NEW.processed_by) NOT IN ('staff','admin') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACC/penolakan wajib diproses staff/admin (processed_by)';
        END IF;
    END IF;

    IF NEW.status = 'returned' AND NEW.return_date IS NULL THEN
        SET NEW.return_date = CURDATE();
    END IF;
    IF NEW.status <> 'returned' AND NEW.return_date IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'return_date hanya boleh diisi saat status returned';
    END IF;
END//

-- TRG-12 <<include>> update stok buku: stok +1 saat pengajuan ditolak / buku dikembalikan.
CREATE TRIGGER trg_loans_after_update_stock
AFTER UPDATE ON loans
FOR EACH ROW
BEGIN
    IF (OLD.status = 'pending'  AND NEW.status = 'rejected')
    OR (OLD.status = 'borrowed' AND NEW.status = 'returned') THEN
        UPDATE books SET available_stock = available_stock + 1 WHERE id = NEW.book_id;
    END IF;
END//

-- TRG-13 <<extend>> menghitung denda: catat denda jika kembali terlambat.
CREATE TRIGGER trg_loans_after_update_fine
AFTER UPDATE ON loans
FOR EACH ROW
FOLLOWS trg_loans_after_update_stock
BEGIN
    DECLARE v_denda DECIMAL(10,2);
    IF OLD.status = 'borrowed' AND NEW.status = 'returned' THEN
        SET v_denda = fn_hitung_denda(NEW.due_date, NEW.return_date);
        IF v_denda > 0 THEN
            INSERT INTO fines (loan_id, amount, payment_status) VALUES (NEW.id, v_denda, 'unpaid');
        END IF;
    END IF;
END//

-- TRG-14 Riwayat peminjaman tidak boleh dihapus.
CREATE TRIGGER trg_loans_before_delete_block
BEFORE DELETE ON loans
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Data peminjaman tidak boleh dihapus';
END//

-- ------------------------------------------------------------- FINES
-- TRG-15 Denda hanya lahir dari pinjaman yang sudah dikembalikan, selalu mulai unpaid.
CREATE TRIGGER trg_fines_before_insert_guard
BEFORE INSERT ON fines
FOR EACH ROW
BEGIN
    IF COALESCE((SELECT status FROM loans WHERE id = NEW.loan_id), '') <> 'returned' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Denda hanya untuk pinjaman yang sudah dikembalikan';
    END IF;
    SET NEW.payment_status = 'unpaid';
END//

-- TRG-16 Nominal denda tidak bisa diubah manual; denda lunas bersifat final.
CREATE TRIGGER trg_fines_before_update_lock
BEFORE UPDATE ON fines
FOR EACH ROW
BEGIN
    IF OLD.payment_status = 'paid' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Denda sudah lunas dan tidak dapat diubah';
    END IF;
    IF NEW.amount <> OLD.amount OR NEW.loan_id <> OLD.loan_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nominal / pinjaman pada denda tidak boleh diubah';
    END IF;
END//

-- TRG-17 Denda tidak boleh dihapus (= memutihkan utang).
CREATE TRIGGER trg_fines_before_delete_block
BEFORE DELETE ON fines
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Data denda tidak boleh dihapus';
END//

DELIMITER ;

-- SP
DROP PROCEDURE IF EXISTS sp_login;
DROP PROCEDURE IF EXISTS sp_logout;
DROP PROCEDURE IF EXISTS sp_create_user;
DROP PROCEDURE IF EXISTS sp_update_user_status;
DROP PROCEDURE IF EXISTS sp_add_author;
DROP PROCEDURE IF EXISTS sp_add_book;
DROP PROCEDURE IF EXISTS sp_update_book;
DROP PROCEDURE IF EXISTS sp_delete_book;
DROP PROCEDURE IF EXISTS sp_meminjam_buku;
DROP PROCEDURE IF EXISTS sp_update_loan_status;
DROP PROCEDURE IF EXISTS sp_pengembalian_buku;
DROP PROCEDURE IF EXISTS sp_pay_fine;

DELIMITER //

-- ============================== AUTENTIKASI ============================

-- SP-1 (UC: login) Verifikasi password di DB, lalu buat sesi untuk koneksi ini.
--      Login ulang di koneksi yang sama = ganti akun.
--      Akun suspended BOLEH login (lihat denda/riwayat), inactive TIDAK.
CREATE PROCEDURE sp_login(
    IN p_email    VARCHAR(100),
    IN p_password VARCHAR(255)
)
BEGIN
    DECLARE v_id     INT DEFAULT NULL;
    DECLARE v_hash   VARCHAR(255);
    DECLARE v_status VARCHAR(10);
    DECLARE v_msg    TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_login] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5001;
    END;

    START TRANSACTION;
        -- bersihkan sesi milik koneksi yang sudah terputus tanpa logout
        DELETE FROM user_sessions
         WHERE connection_id NOT IN (SELECT processlist_id FROM performance_schema.threads
                                      WHERE processlist_id IS NOT NULL);

        SELECT id, password, status INTO v_id, v_hash, v_status
          FROM users WHERE email = LOWER(TRIM(p_email));

        -- pesan sengaja disamakan agar tidak membocorkan email mana yang terdaftar
        IF v_id IS NULL OR fn_verifikasi_password(p_password, v_hash) = 0 OR v_status = 'inactive' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Email atau password salah';
        END IF;

        REPLACE INTO user_sessions (connection_id, user_id, login_at)
        VALUES (CONNECTION_ID(), v_id, NOW());
    COMMIT;

    SELECT id AS user_id, name, email, role, status, 'Login berhasil' AS message
      FROM users WHERE id = v_id;
END//

-- SP-2 (UC: logout)
CREATE PROCEDURE sp_logout()
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_logout] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5002;
    END;

    START TRANSACTION;
        DELETE FROM user_sessions WHERE connection_id = CONNECTION_ID();
        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
    COMMIT;
    SELECT 'Logout berhasil' AS message;
END//

-- ================================ AKUN ================================

-- SP-3 (UC: membuat akun <<include>> menetapkan akses akun) - khusus admin.
--      Role ditetapkan saat pembuatan (staff/member) dan permanen.
CREATE PROCEDURE sp_create_user(
    IN  p_name     VARCHAR(100),
    IN  p_email    VARCHAR(100),
    IN  p_password VARCHAR(255),       -- plain text, di-hash di sini
    IN  p_role     VARCHAR(10),        -- 'staff' | 'member'
    OUT p_user_id  INT
)
BEGIN
    DECLARE v_admin INT;
    DECLARE v_salt  CHAR(32);
    DECLARE v_msg   TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_user_id = NULL;
        SET v_msg = LEFT(CONCAT('[sp_create_user] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5003;
    END;

    SET p_user_id = NULL;
    START TRANSACTION;
        SET v_admin = fn_current_user_id();
        IF v_admin IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF fn_cek_akses('admin') = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akses ditolak: khusus admin';
        END IF;
        IF TRIM(COALESCE(p_name, '')) = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nama wajib diisi';
        END IF;
        IF LOWER(TRIM(COALESCE(p_email, ''))) NOT REGEXP '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Format email tidak valid';
        END IF;
        IF CHAR_LENGTH(COALESCE(p_password, '')) < fn_ambil_setting('MIN_PASSWORD') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Password minimal 8 karakter';
        END IF;
        IF p_role IS NULL OR p_role NOT IN ('staff','member') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Role harus staff atau member';
        END IF;

        SET v_salt = LOWER(HEX(RANDOM_BYTES(16)));
        INSERT INTO users (name, email, password, role, status)
        VALUES (TRIM(p_name), p_email, fn_hash_password(p_password, v_salt), p_role, 'active');
        SET p_user_id = LAST_INSERT_ID();               -- email duplikat -> error 1062 -> handler
    COMMIT;
END//

-- SP-4 (UC: menetapkan akses akun -> status) - khusus admin.
--      active <-> suspended (member saja), active <-> inactive, suspended -> inactive.
--      Efek samping:
--        * member -> suspended/inactive : semua pengajuan pending otomatis rejected (stok kembali)
--        * -> inactive                  : sesi login user tsb dihapus (paksa logout)
--        * member -> inactive ditolak jika masih ada buku yang dipinjam
CREATE PROCEDURE sp_update_user_status(
    IN  p_user_id         INT,          -- akun TARGET (bukan pelaku)
    IN  p_status          VARCHAR(10),  -- 'active' | 'suspended' | 'inactive'
    OUT p_pending_ditolak INT
)
BEGIN
    DECLARE v_admin      INT;
    DECLARE v_role       VARCHAR(10) DEFAULT NULL;
    DECLARE v_old_status VARCHAR(10);
    DECLARE v_msg        TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_pending_ditolak = NULL;
        SET v_msg = LEFT(CONCAT('[sp_update_user_status] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5004;
    END;

    SET p_pending_ditolak = 0;
    START TRANSACTION;
        SET v_admin = fn_current_user_id();
        IF v_admin IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF fn_cek_akses('admin') = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akses ditolak: khusus admin';
        END IF;
        IF p_user_id = v_admin THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tidak bisa mengubah status akun sendiri';
        END IF;
        IF p_status IS NULL OR p_status NOT IN ('active','suspended','inactive') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status harus active, suspended, atau inactive';
        END IF;

        SELECT role, status INTO v_role, v_old_status FROM users WHERE id = p_user_id FOR UPDATE;
        IF v_role IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User tidak ditemukan';
        END IF;
        IF v_old_status = p_status THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status akun sudah sama';
        END IF;
        IF p_status = 'suspended' AND v_role <> 'member' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status suspended hanya untuk member';
        END IF;
        IF p_status = 'inactive' AND v_role = 'member'
           AND EXISTS (SELECT 1 FROM loans WHERE user_id = p_user_id AND status = 'borrowed') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Member masih meminjam buku, kembalikan dulu';
        END IF;

        UPDATE users SET status = p_status WHERE id = p_user_id;   -- trigger: lindungi admin terakhir

        IF v_role = 'member' AND p_status <> 'active' THEN
            UPDATE loans
               SET status = 'rejected', processed_by = v_admin       -- trg_loans_after_update_stock: stok +1
             WHERE user_id = p_user_id AND status = 'pending';
            SET p_pending_ditolak = ROW_COUNT();
        END IF;

        IF p_status = 'inactive' THEN
            DELETE FROM user_sessions WHERE user_id = p_user_id;
        END IF;
    COMMIT;
END//

-- ============================ PENULIS & BUKU ===========================

-- SP-5 (UC: menambah penulis)
CREATE PROCEDURE sp_add_author(
    IN  p_name      VARCHAR(150),
    OUT p_author_id INT
)
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_author_id = NULL;
        SET v_msg = LEFT(CONCAT('[sp_add_author] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5005;
    END;

    SET p_author_id = NULL;
    START TRANSACTION;
        IF fn_current_user_id() IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF fn_cek_akses('staff,admin') = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akses ditolak: khusus staff/admin';
        END IF;
        IF TRIM(COALESCE(p_name, '')) = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nama penulis wajib diisi';
        END IF;

        INSERT INTO authors (name) VALUES (TRIM(p_name));         -- nama duplikat -> 1062
        SET p_author_id = LAST_INSERT_ID();
    COMMIT;
END//

-- SP-6 (UC: menambah buku)  p_author_ids = JSON array id penulis sesuai urutan sampul, mis. '[3,7]'
CREATE PROCEDURE sp_add_book(
    IN  p_title       VARCHAR(200),
    IN  p_isbn        VARCHAR(20),
    IN  p_total_stock INT,
    IN  p_genre       JSON,
    IN  p_author_ids  JSON,
    OUT p_book_id     INT
)
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_book_id = NULL;
        SET v_msg = LEFT(CONCAT('[sp_add_book] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5006;
    END;

    SET p_book_id = NULL;
    START TRANSACTION;
        IF fn_current_user_id() IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF fn_cek_akses('staff,admin') = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akses ditolak: khusus staff/admin';
        END IF;
        IF TRIM(COALESCE(p_title, '')) = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Judul wajib diisi';
        END IF;
        IF p_isbn IS NULL OR p_isbn NOT REGEXP '^[0-9Xx-]{10,17}$' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Format ISBN tidak valid';
        END IF;
        IF p_total_stock IS NULL OR p_total_stock < 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stok minimal 1';
        END IF;
        IF p_genre IS NOT NULL AND JSON_TYPE(p_genre) <> 'ARRAY' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Genre harus JSON array, contoh ["fiksi"]';
        END IF;
        IF fn_penulis_valid(p_author_ids) = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Daftar penulis kosong / tidak ditemukan / duplikat';
        END IF;

        INSERT INTO books (title, isbn, total_stock, genre)              -- trg_books_before_insert_stock
        VALUES (TRIM(p_title), p_isbn, p_total_stock, p_genre);          -- ISBN duplikat -> 1062
        SET p_book_id = LAST_INSERT_ID();

        INSERT INTO book_authors (book_id, author_id, author_order)      -- trg_book_authors_after_insert_sync
        SELECT p_book_id, jt.aid, jt.urut
          FROM JSON_TABLE(p_author_ids, '$[*]' COLUMNS (urut FOR ORDINALITY, aid INT PATH '$')) jt;
    COMMIT;
END//

-- SP-7 (UC: mengedit detail buku)  parameter NULL = tidak diubah.
--      Ubah total_stock -> trg_books_before_update_stock menggeser available_stock.
CREATE PROCEDURE sp_update_book(
    IN p_book_id     INT,
    IN p_title       VARCHAR(200),
    IN p_isbn        VARCHAR(20),
    IN p_total_stock INT,
    IN p_genre       JSON,
    IN p_author_ids  JSON
)
BEGIN
    DECLARE v_found   INT DEFAULT NULL;
    DECLARE v_deleted TIMESTAMP DEFAULT NULL;
    DECLARE v_msg     TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_update_book] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5007;
    END;

    START TRANSACTION;
        IF fn_current_user_id() IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF fn_cek_akses('staff,admin') = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akses ditolak: khusus staff/admin';
        END IF;

        SELECT id, deleted_at INTO v_found, v_deleted FROM books WHERE id = p_book_id FOR UPDATE;
        IF v_found IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Buku tidak ditemukan';
        END IF;
        IF v_deleted IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Buku sudah dihapus';
        END IF;
        IF p_title IS NOT NULL AND TRIM(p_title) = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Judul tidak boleh kosong';
        END IF;
        IF p_isbn IS NOT NULL AND p_isbn NOT REGEXP '^[0-9Xx-]{10,17}$' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Format ISBN tidak valid';
        END IF;
        IF p_genre IS NOT NULL AND JSON_TYPE(p_genre) <> 'ARRAY' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Genre harus JSON array, contoh ["fiksi"]';
        END IF;
        IF p_author_ids IS NOT NULL AND fn_penulis_valid(p_author_ids) = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Daftar penulis kosong / tidak ditemukan / duplikat';
        END IF;

        UPDATE books
           SET title       = COALESCE(TRIM(p_title), title),
               isbn        = COALESCE(p_isbn, isbn),
               total_stock = COALESCE(p_total_stock, total_stock),
               genre       = COALESCE(p_genre, genre)
         WHERE id = p_book_id;

        IF p_author_ids IS NOT NULL THEN
            DELETE FROM book_authors WHERE book_id = p_book_id;
            INSERT INTO book_authors (book_id, author_id, author_order)
            SELECT p_book_id, jt.aid, jt.urut
              FROM JSON_TABLE(p_author_ids, '$[*]' COLUMNS (urut FOR ORDINALITY, aid INT PATH '$')) jt;
        END IF;
    COMMIT;
END//

-- SP-8 (UC: menghapus buku) SOFT DELETE. Ditolak jika masih dipinjam / diajukan.
CREATE PROCEDURE sp_delete_book(IN p_book_id INT)
BEGIN
    DECLARE v_found   INT DEFAULT NULL;
    DECLARE v_deleted TIMESTAMP DEFAULT NULL;
    DECLARE v_msg     TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_delete_book] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5008;
    END;

    START TRANSACTION;
        IF fn_current_user_id() IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF fn_cek_akses('staff,admin') = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akses ditolak: khusus staff/admin';
        END IF;

        SELECT id, deleted_at INTO v_found, v_deleted FROM books WHERE id = p_book_id FOR UPDATE;
        IF v_found IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Buku tidak ditemukan';
        END IF;
        IF v_deleted IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Buku sudah dihapus sebelumnya';
        END IF;
        IF EXISTS (SELECT 1 FROM loans WHERE book_id = p_book_id AND status IN ('pending','borrowed')) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Buku masih dipinjam / diajukan';
        END IF;

        UPDATE books SET deleted_at = CURRENT_TIMESTAMP WHERE id = p_book_id;
    COMMIT;
END//

-- ============================== PEMINJAMAN =============================

-- SP-9 (UC: meminjam buku) Member mengajukan pinjaman.
--      Gate fn_pinjaman_valid: cek stok + cek limit + denda + keterlambatan.
--      Stok langsung di-RESERVE (-1) -> staff tidak bisa ACC buku yang sudah habis.
CREATE PROCEDURE sp_meminjam_buku(
    IN  p_book_id INT,
    OUT p_loan_id INT
)
BEGIN
    DECLARE v_uid    INT;
    DECLARE v_lock   INT;
    DECLARE v_alasan VARCHAR(100);
    DECLARE v_msg    TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_loan_id = NULL;
        SET v_msg = LEFT(CONCAT('[sp_meminjam_buku] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5009;
    END;

    SET p_loan_id = NULL;
    START TRANSACTION;
        SET v_uid = fn_current_user_id();
        IF v_uid IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;

        -- Lock 1: baris member -> 2 pengajuan paralel dari member yang sama tidak bisa lolos kuota bersamaan
        SELECT id INTO v_lock FROM users WHERE id = v_uid FOR UPDATE;
        -- Lock 2: baris buku   -> 2 member tidak bisa mengambil eksemplar terakhir bersamaan
        SELECT id INTO v_lock FROM books WHERE id = p_book_id FOR UPDATE;

        SET v_alasan = fn_pinjaman_valid(p_book_id);
        IF v_alasan <> 'OK' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_alasan;
        END IF;

        INSERT INTO loans (user_id, book_id, processed_by, loan_date, due_date, status)
        VALUES (v_uid, p_book_id, NULL, CURDATE(),
                CURDATE() + INTERVAL fn_ambil_setting('LAMA_PINJAM_HARI') DAY, 'pending');
        SET p_loan_id = LAST_INSERT_ID();

        UPDATE books SET available_stock = available_stock - 1 WHERE id = p_book_id;
    COMMIT;
END//

-- SP-10 (UC: mengedit status peminjaman -> ACC / tolak pengajuan)
--       processed_by = staff yang sedang login.
--       approve : loan_date & due_date dihitung ulang dari hari ACC
--       reject  : trg_loans_after_update_stock mengembalikan stok reservasi
CREATE PROCEDURE sp_update_loan_status(
    IN p_loan_id INT,
    IN p_action  VARCHAR(10)          -- 'approve' | 'reject'
)
BEGIN
    DECLARE v_staff     INT;
    DECLARE v_status    VARCHAR(10) DEFAULT NULL;
    DECLARE v_member    INT;
    DECLARE v_mem_stat  VARCHAR(10);
    DECLARE v_msg       TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_update_loan_status] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5010;
    END;

    START TRANSACTION;
        SET v_staff = fn_current_user_id();
        IF v_staff IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF fn_cek_akses('staff,admin') = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akses ditolak: khusus staff/admin';
        END IF;
        IF p_action IS NULL OR p_action NOT IN ('approve','reject') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Aksi harus approve atau reject';
        END IF;

        SELECT status, user_id INTO v_status, v_member FROM loans WHERE id = p_loan_id FOR UPDATE;
        IF v_status IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pengajuan tidak ditemukan';
        END IF;
        IF v_status <> 'pending' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Hanya pengajuan berstatus pending yang bisa diproses';
        END IF;

        IF p_action = 'approve' THEN
            SELECT status INTO v_mem_stat FROM users WHERE id = v_member;
            IF v_mem_stat <> 'active' THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akun member tidak aktif, pengajuan harus ditolak';
            END IF;

            UPDATE loans
               SET status       = 'borrowed',
                   processed_by = v_staff,
                   loan_date    = CURDATE(),
                   due_date     = CURDATE() + INTERVAL fn_ambil_setting('LAMA_PINJAM_HARI') DAY
             WHERE id = p_loan_id;
        ELSE
            UPDATE loans
               SET status = 'rejected', processed_by = v_staff
             WHERE id = p_loan_id;
        END IF;
    COMMIT;
END//

-- SP-11 (UC: mengedit status peminjaman -> pengembalian)
--       <<include>> update stok buku   : trg_loans_after_update_stock
--       <<extend>>  hitung denda       : trg_loans_after_update_fine
--       Pelunasan opsional langsung di loket (p_bayar_denda = 1).
--       processed_by TIDAK diubah (tetap staff yang meng-ACC).
CREATE PROCEDURE sp_pengembalian_buku(
    IN  p_loan_id     INT,
    IN  p_bayar_denda TINYINT,
    OUT p_denda       DECIMAL(10,2)
)
BEGIN
    DECLARE v_status VARCHAR(10) DEFAULT NULL;
    DECLARE v_due    DATE;
    DECLARE v_msg    TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_denda = NULL;
        SET v_msg = LEFT(CONCAT('[sp_pengembalian_buku] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5011;
    END;

    SET p_denda = 0;
    START TRANSACTION;
        IF fn_current_user_id() IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF fn_cek_akses('staff,admin') = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akses ditolak: khusus staff/admin';
        END IF;

        SELECT status, due_date INTO v_status, v_due FROM loans WHERE id = p_loan_id FOR UPDATE;
        IF v_status IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Peminjaman tidak ditemukan';
        END IF;
        IF v_status <> 'borrowed' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Hanya pinjaman berstatus borrowed yang bisa dikembalikan';
        END IF;

        UPDATE loans SET status = 'returned', return_date = CURDATE()
         WHERE id = p_loan_id;                      -- trigger: stok +1, INSERT fines jika telat

        SET p_denda = fn_hitung_denda(v_due, CURDATE());
        IF p_denda > 0 AND COALESCE(p_bayar_denda, 0) = 1 THEN
            UPDATE fines SET payment_status = 'paid' WHERE loan_id = p_loan_id;
        END IF;
    COMMIT;
END//

-- SP-12 Pelunasan denda (di loket, oleh staff).
CREATE PROCEDURE sp_pay_fine(IN p_fine_id INT)
BEGIN
    DECLARE v_pay VARCHAR(10) DEFAULT NULL;
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_pay_fine] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5012;
    END;

    START TRANSACTION;
        IF fn_current_user_id() IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF fn_cek_akses('staff,admin') = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Akses ditolak: khusus staff/admin';
        END IF;

        SELECT payment_status INTO v_pay FROM fines WHERE id = p_fine_id FOR UPDATE;
        IF v_pay IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Denda tidak ditemukan';
        END IF;
        IF v_pay = 'paid' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Denda sudah lunas';
        END IF;

        UPDATE fines SET payment_status = 'paid' WHERE id = p_fine_id;
    COMMIT;
END//

DELIMITER ;

-- 4. VIEWS  (baca data; otomatis tersaring sesi login)
--   * Filter sesi memakai SUBQUERY ke user_sessions (bukan JOIN) ->
--     batas "maks 2 tabel JOIN" tetap terpenuhi, dan optimizer tetap
--     memakai index (ref/const). Function NOT DETERMINISTIC di WHERE
--     justru memaksa full scan, jadi sengaja tidak dipakai.
--   * Tanpa GROUP BY/DISTINCT/aggregate -> MySQL otomatis me-MERGE view,
--     sehingga WHERE tambahan dari luar ikut memakai index.
--   * Belum login / role tidak berhak -> view mengembalikan 0 baris.
--   * Kolom password tidak pernah muncul di view mana pun.
--
--   Role      | View
--   ----------+------------------------------------------------------
--   semua     | v_sesi_saya, v_book_catalog, v_book_authors
--   member    | v_riwayat_saya, v_denda_saya, v_kuota_saya
--   staff+adm | v_users, v_book_status, v_loan_details, v_fine_details,
--             | v_stock_audit
DROP VIEW IF EXISTS v_sesi_saya, v_book_catalog, v_book_authors,
                    v_riwayat_saya, v_denda_saya, v_kuota_saya,
                    v_users, v_book_status, v_loan_details, v_fine_details, v_stock_audit;

-- ------------------------------------------------------------ SEMUA ROLE
-- VW-1 Siapa yang sedang login di koneksi ini.
CREATE VIEW v_sesi_saya AS
SELECT u.id AS user_id, u.name, u.email, u.role, u.status, s.login_at
FROM user_sessions s
JOIN users u ON u.id = s.user_id
WHERE s.connection_id = CONNECTION_ID()
  AND u.status <> 'inactive';

-- VW-2 (UC: melihat katalog buku) buku yang belum dihapus. Wajib login.
CREATE VIEW v_book_catalog AS
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

-- VW-3 Penulis per buku (detail buku / form edit). Wajib login.
CREATE VIEW v_book_authors AS
SELECT ba.book_id, ba.author_order, a.id AS author_id, a.name AS author_name
FROM book_authors ba
JOIN authors a ON a.id = ba.author_id
WHERE EXISTS (SELECT 1 FROM user_sessions s JOIN users su ON su.id = s.user_id
               WHERE s.connection_id = CONNECTION_ID() AND su.status <> 'inactive');

-- ------------------------------------------------------------ MEMBER
-- VW-4 (UC: melihat riwayat peminjaman) HANYA milik user yang login.
CREATE VIEW v_riwayat_saya AS
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

-- VW-5 (UC: melihat denda) HANYA milik user yang login.
CREATE VIEW v_denda_saya AS
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

-- VW-6 (UC: melihat cek limit pinjam buku) ringkasan gate pinjam milik user login.
CREATE VIEW v_kuota_saya AS
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

-- ------------------------------------------------------------ STAFF + ADMIN
-- VW-7 (UC: melihat akun user) tanpa password.
CREATE VIEW v_users AS
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

-- VW-8 (UC: melihat status buku) termasuk buku terhapus & eksemplar terpakai.
CREATE VIEW v_book_status AS
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

-- VW-9 Semua peminjaman: antrian ACC (status='pending'), monitoring, terlambat.
CREATE VIEW v_loan_details AS
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

-- VW-10 Semua denda (pelunasan di loket).
CREATE VIEW v_fine_details AS
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

-- VW-11 Audit konsistensi stok. Normal = 0 baris. (pakai GROUP BY -> tidak di-merge; bukan hot path)
CREATE VIEW v_stock_audit AS
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