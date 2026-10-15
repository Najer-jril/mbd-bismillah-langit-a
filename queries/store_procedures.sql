USE mbd_uts;

DROP PROCEDURE IF EXISTS sp_login;
DROP PROCEDURE IF EXISTS sp_logout;
DROP PROCEDURE IF EXISTS sp_token_buat;
DROP PROCEDURE IF EXISTS sp_token_pasang;
DROP PROCEDURE IF EXISTS sp_token_lepas;
DROP PROCEDURE IF EXISTS sp_membuat_akun;
DROP PROCEDURE IF EXISTS sp_ubah_status_akun;
DROP PROCEDURE IF EXISTS sp_menambah_penulis;
DROP PROCEDURE IF EXISTS sp_menambah_buku;
DROP PROCEDURE IF EXISTS sp_mengedit_detail_buku;
DROP PROCEDURE IF EXISTS sp_menghapus_buku;
DROP PROCEDURE IF EXISTS sp_meminjam_buku;
DROP PROCEDURE IF EXISTS sp_mengedit_status_peminjaman;
DROP PROCEDURE IF EXISTS sp_pengembalian_buku;
DROP PROCEDURE IF EXISTS sp_membayar_denda;

-- sp_login untuk login, cek email & password, simpan session (suspended boleh login, inactive gaboleh login)
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
        SELECT id, password, status INTO v_id, v_hash, v_status
          FROM users WHERE email = LOWER(TRIM(p_email));

        -- message inactive kek salah email/pw
        IF v_id IS NULL OR fn_verifikasi_password(p_password, v_hash) = 0 OR v_status = 'inactive' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Email atau password salah';
        END IF;

        REPLACE INTO user_sessions (connection_id, user_id, login_at)
        VALUES (CONNECTION_ID(), v_id, NOW());
    COMMIT;

    SELECT id AS user_id, name, email, role, status, 'Login berhasil' AS message
      FROM users WHERE id = v_id;
END;

-- sp_logout untuk logout dengan hapus session + cabut token
CREATE PROCEDURE sp_logout(IN p_token_hash CHAR(64))
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
        DELETE FROM auth_tokens WHERE token_hash = p_token_hash;
    COMMIT;
    SELECT 'Logout berhasil' AS message;
END;

-- sp_token_buat buat token dan simpan hash token exp 24 jam + hapus token yang expire
CREATE PROCEDURE sp_token_buat(IN p_token_hash CHAR(64))
BEGIN
    DECLARE v_uid INT;
    DECLARE v_exp DATETIME;
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_token_buat] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5013;
    END;
 
    START TRANSACTION;
        SET v_uid = fn_current_user_id();
        IF v_uid IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Belum login';
        END IF;
        IF p_token_hash IS NULL OR p_token_hash NOT REGEXP '^[0-9a-f]{64}$' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Format token tidak valid';
        END IF;
 
        SET v_exp = NOW() + INTERVAL 24 HOUR;
        DELETE FROM auth_tokens WHERE user_id = v_uid AND expires_at <= NOW();   -- bersih-bersih malas
        INSERT INTO auth_tokens (token_hash, user_id, expires_at)
        VALUES (p_token_hash, v_uid, v_exp);
    COMMIT;
 
    SELECT v_exp AS expires_at;
END;
 
-- sp_token_pasang, steiap awal rekues dan token valid + belum kedaluwarsa + akun tidak inactive boleh akses yang mau diakses
CREATE PROCEDURE sp_token_pasang(IN p_token_hash CHAR(64))
BEGIN
    DECLARE v_uid INT DEFAULT NULL;
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        DELETE FROM user_sessions WHERE connection_id = CONNECTION_ID();
        SET v_msg = LEFT(CONCAT('[sp_token_pasang] ', v_msg), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 5014;
    END;
 
    DELETE FROM user_sessions WHERE connection_id = CONNECTION_ID();
 
    START TRANSACTION;
        SELECT t.user_id INTO v_uid
          FROM auth_tokens t
          JOIN users u ON u.id = t.user_id
         WHERE t.token_hash = p_token_hash
           AND t.expires_at > NOW()
           AND u.status <> 'inactive';
        IF v_uid IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sesi tidak valid atau kedaluwarsa';
        END IF;
 
        UPDATE auth_tokens SET last_used_at = NOW() WHERE token_hash = p_token_hash;
        REPLACE INTO user_sessions (connection_id, user_id, login_at)
        VALUES (CONNECTION_ID(), v_uid, NOW());
    COMMIT;
END;
 
-- sp_token_lepas di awal request buat ke 1 tokken user aja, dan hapus kalo udah kelar requset
CREATE PROCEDURE sp_token_lepas()
BEGIN
    DELETE FROM user_sessions WHERE connection_id = CONNECTION_ID();
END;

-- sp_membuat_akun, admin membuat akun baru + useace include menetapkan role staff atau member
CREATE PROCEDURE sp_membuat_akun(
    IN  p_name     VARCHAR(100),
    IN  p_email    VARCHAR(100),
    IN  p_password VARCHAR(255),
    IN  p_role     VARCHAR(10),
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
        SET v_msg = LEFT(CONCAT('[sp_membuat_akun] ', v_msg), 128);
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
        SET p_user_id = LAST_INSERT_ID(); -- email duplikat -> error
    COMMIT;
END;

-- sp_ubah_status_akun : admin ubah status akun; kalo user ada pengajuan pinjaman pas diupdate status jadi suspend/nonaktif yang masih pending jadi rejected,kalo user diubah jadi inactive langsung logout
CREATE PROCEDURE sp_ubah_status_akun(
    IN  p_user_id INT, -- akun target yang mo diganti statusnya
    IN  p_status VARCHAR(10),
    OUT p_pending_ditolak INT
)
BEGIN
    DECLARE v_admin INT;
    DECLARE v_role VARCHAR(10) DEFAULT NULL;
    DECLARE v_old_status VARCHAR(10);
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_pending_ditolak = NULL;
        SET v_msg = LEFT(CONCAT('[sp_ubah_status_akun] ', v_msg), 128);
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
END;

-- sp_menambah_penulis, staff n admin bisa nambah penulis
CREATE PROCEDURE sp_menambah_penulis(
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
        SET v_msg = LEFT(CONCAT('[sp_menambah_penulis] ', v_msg), 128);
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

        INSERT INTO authors (name) VALUES (TRIM(p_name)); -- nama dupe ke error 1062
        SET p_author_id = LAST_INSERT_ID();
    COMMIT;
END;

-- sp_menambah_buku, staff n admin bisa nambah buku dan penulisnya jadi format json array karena bisa lebih dari 1 orang contoh '[3,7]' dan genre juga bisa lebih dari 1
CREATE PROCEDURE sp_menambah_buku(
    IN  p_title VARCHAR(200),
    IN  p_isbn VARCHAR(20),
    IN  p_total_stock INT,
    IN  p_genre JSON,
    IN  p_author_ids JSON,
    OUT p_book_id INT
)
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_book_id = NULL;
        SET v_msg = LEFT(CONCAT('[sp_menambah_buku] ', v_msg), 128);
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

        INSERT INTO books (title, isbn, total_stock, genre) -- trg_books_before_insert_stock
        VALUES (TRIM(p_title), p_isbn, p_total_stock, p_genre);-- ISBN dupe eror 1062
        SET p_book_id = LAST_INSERT_ID();

        INSERT INTO book_authors (book_id, author_id, author_order) -- trg_book_authors_after_insert_sync
        SELECT p_book_id, jt.aid, jt.urut
          FROM JSON_TABLE(p_author_ids, '$[*]' COLUMNS (urut FOR ORDINALITY, aid INT PATH '$')) jt;
    COMMIT;
END;

-- sp_mengedit_detail_buku, staff n admin bisa edit detail buku (NULL = tidak diubah)
CREATE PROCEDURE sp_mengedit_detail_buku(
    IN p_book_id INT,
    IN p_title VARCHAR(200),
    IN p_isbn VARCHAR(20),
    IN p_total_stock INT,
    IN p_genre JSON,
    IN p_author_ids JSON
)
BEGIN
    DECLARE v_found   INT DEFAULT NULL;
    DECLARE v_deleted TIMESTAMP DEFAULT NULL;
    DECLARE v_msg     TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_mengedit_detail_buku] ', v_msg), 128);
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
           SET title = COALESCE(TRIM(p_title), title),
               isbn = COALESCE(p_isbn, isbn),
               total_stock = COALESCE(p_total_stock, total_stock),
               genre = COALESCE(p_genre, genre)
         WHERE id = p_book_id;

        IF p_author_ids IS NOT NULL THEN
            DELETE FROM book_authors WHERE book_id = p_book_id;
            INSERT INTO book_authors (book_id, author_id, author_order)
            SELECT p_book_id, jt.aid, jt.urut
              FROM JSON_TABLE(p_author_ids, '$[*]' COLUMNS (urut FOR ORDINALITY, aid INT PATH '$')) jt;
        END IF;
    COMMIT;
END;

-- sp_menghapus_buku, staff n admin bisa soft delete buku, gabisa delete buku kalomasih dipinjam/diajukan
CREATE PROCEDURE sp_menghapus_buku(IN p_book_id INT)
BEGIN
    DECLARE v_found   INT DEFAULT NULL;
    DECLARE v_deleted TIMESTAMP DEFAULT NULL;
    DECLARE v_msg     TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_menghapus_buku] ', v_msg), 128);
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
END;

-- sp_meminjam_buku, member bisa mengajukan pinjaman: cek gate, buat pending, reserve stok -1
CREATE PROCEDURE sp_meminjam_buku(
    IN  p_book_id INT,
    OUT p_loan_id INT
)
BEGIN
    DECLARE v_uid INT;
    DECLARE v_lock INT;
    DECLARE v_active INT DEFAULT 0;
    DECLARE v_avail  INT DEFAULT 0;
    DECLARE v_alasan VARCHAR(100);
    DECLARE v_msg TEXT;
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

        -- kunci data member buat cegah 2 pengajuan bersamaan melewati kuota
        SELECT id INTO v_lock FROM users WHERE id = v_uid FOR UPDATE;
        -- kunci data buku buat cegah 2 member mengambil unit terakhir bersamaan
        SELECT id INTO v_lock FROM books WHERE id = p_book_id FOR UPDATE;

        SET v_alasan = fn_pinjaman_valid(p_book_id);
        IF v_alasan <> 'OK' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_alasan;
        END IF;

        -- Re-cek kuota dengan locking read: fn_jumlah_pinjaman_aktif (dipakai fn_pinjaman_valid)
        -- baca non-locking, jadi lock user row di atas tidak melindungi hitungan baris baru
        -- di tabel loans dari transaksi lain. FOR SHARE memaksa baca data terkomit terbaru.
        SELECT COUNT(*) INTO v_active
          FROM loans
         WHERE user_id = v_uid AND status IN ('pending','borrowed')
         FOR SHARE;
        IF v_active >= fn_ambil_setting('MAX_PINJAM_AKTIF') THEN
            SET v_msg = CONCAT('Kuota pinjam habis (maks ', fn_ambil_setting('MAX_PINJAM_AKTIF'), ' aktif)');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        -- Re-cek stok dengan locking read: fn_buku_tersedia (dipakai fn_pinjaman_valid) baca
        -- non-locking, jadi 2 member bisa lolos sekaligus mengambil unit terakhir yang sama.
        SELECT available_stock INTO v_avail FROM books WHERE id = p_book_id FOR UPDATE;
        IF v_avail <= 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stok buku habis';
        END IF;

        INSERT INTO loans (user_id, book_id, processed_by, loan_date, due_date, status)
        VALUES (v_uid, p_book_id, NULL, CURDATE(),
                CURDATE() + INTERVAL fn_ambil_setting('LAMA_PINJAM_HARI') DAY, 'pending');
        SET p_loan_id = LAST_INSERT_ID();

        UPDATE books SET available_stock = available_stock - 1 WHERE id = p_book_id;
    COMMIT;
END;

-- sp_mengedit_status_peminjaman, staff n admin approve / reject pengajuan
CREATE PROCEDURE sp_mengedit_status_peminjaman(
    IN p_loan_id INT,
    IN p_action  VARCHAR(10)
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
        SET v_msg = LEFT(CONCAT('[sp_mengedit_status_peminjaman] ', v_msg), 128);
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
               SET status = 'borrowed',
                   processed_by = v_staff,
                   loan_date = CURDATE(),
                   due_date = CURDATE() + INTERVAL fn_ambil_setting('LAMA_PINJAM_HARI') DAY
             WHERE id = p_loan_id;
        ELSE
            UPDATE loans
               SET status = 'rejected', processed_by = v_staff
             WHERE id = p_loan_id;
        END IF;
    COMMIT;
END;

-- sp_pengembalian_buku, staff/admin terima pengembalian buku, update stok & denda via trigger, kalo p_bayar_denda=1 langsung lunas
CREATE PROCEDURE sp_pengembalian_buku(
    IN  p_loan_id INT,
    IN  p_bayar_denda TINYINT,
    OUT p_denda DECIMAL(10,2)
)
BEGIN
    DECLARE v_status VARCHAR(10) DEFAULT NULL;
    DECLARE v_due DATE;
    DECLARE v_msg TEXT;
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
         WHERE id = p_loan_id; -- trigger stok +1, INSERT fines jika telat

        SET p_denda = fn_hitung_denda(v_due, CURDATE());
        IF p_denda > 0 AND COALESCE(p_bayar_denda, 0) = 1 THEN
            UPDATE fines SET payment_status = 'paid' WHERE loan_id = p_loan_id;
        END IF;
    COMMIT;
END;

-- sp_membayar_denda, staff/admin melunasi denda
CREATE PROCEDURE sp_membayar_denda(IN p_fine_id INT)
BEGIN
    DECLARE v_pay VARCHAR(10) DEFAULT NULL;
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET v_msg = LEFT(CONCAT('[sp_membayar_denda] ', v_msg), 128);
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
END;