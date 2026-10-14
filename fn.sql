USE mbd_uts;

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

-- fn_ambil_setting untuk settingan hardcode
CREATE FUNCTION fn_ambil_setting(p_key VARCHAR(30))
RETURNS INT
DETERMINISTIC NO SQL
BEGIN
    RETURN CASE p_key
        WHEN 'MAX_PINJAM_AKTIF' THEN 3
        WHEN 'LAMA_PINJAM_HARI' THEN 7
        WHEN 'TARIF_DENDA_HARI' THEN 1000
        WHEN 'MAX_DENDA' THEN 50000
        WHEN 'MIN_PASSWORD' THEN 8
        ELSE NULL
    END;
END;

-- fn_hash_password untuk hasing password
CREATE FUNCTION fn_hash_password(p_plain VARCHAR(255), p_salt CHAR(32))
RETURNS VARCHAR(255)
DETERMINISTIC NO SQL
BEGIN
    RETURN CONCAT(p_salt, '$', SHA2(CONCAT(p_salt, p_plain), 256));
END;

-- fn_verifikasi_password untuk cek pw kalo 1 berarti cocok
CREATE FUNCTION fn_verifikasi_password(p_plain VARCHAR(255), p_stored VARCHAR(255))
RETURNS TINYINT
DETERMINISTIC NO SQL
BEGIN
    IF p_plain IS NULL OR p_stored IS NULL OR LOCATE('$', p_stored) = 0 THEN
        RETURN 0;
    END IF;
    RETURN IF(p_stored = fn_hash_password(p_plain, SUBSTRING_INDEX(p_stored, '$', 1)), 1, 0);
END;

-- fn_current_user_id untuk ngecek id user yang lagi login kalo null berarti belum login / status akun inactive
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
END;

-- fn_cek_akses untuk cek user login berstatus active DAN role-nya ada di daftar CSV ('staff,admin')
CREATE FUNCTION fn_cek_akses(p_roles VARCHAR(50))
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_oke TINYINT DEFAULT 0;
    SELECT 1 INTO v_oke
      FROM user_sessions s
      JOIN users u ON u.id = s.user_id
     WHERE s.connection_id = CONNECTION_ID()
       AND u.status = 'active'
       AND FIND_IN_SET(u.role, p_roles) > 0;
    RETURN v_oke;
END;

-- fn_jumlah_pinjaman_aktif untuk cek jumlah pinjaman ke member
CREATE FUNCTION fn_jumlah_pinjaman_aktif(p_user_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_jumlah INT DEFAULT 0;
    SELECT COUNT(*) INTO v_jumlah
      FROM loans
     WHERE user_id = p_user_id
       AND status IN ('pending','borrowed');
    RETURN v_jumlah;
END;

-- fn_sisa_kuota_pinjam untuk cek sisa kuota pinjaman
CREATE FUNCTION fn_sisa_kuota_pinjam(p_user_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    RETURN GREATEST(fn_ambil_setting('MAX_PINJAM_AKTIF') - fn_jumlah_pinjaman_aktif(p_user_id), 0);
END;

-- fn_buku_tersedia untuk mengecek ketersediaan stok, 1 kalo ada + ga dihapus + stok > 0, 0 kalo gada
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
END;

-- fn_hari_terlambat untuk hitung keterlambatan pengembalian
CREATE FUNCTION fn_hari_terlambat(p_due_date DATE, p_return_date DATE)
RETURNS INT
DETERMINISTIC NO SQL
BEGIN
    IF p_due_date IS NULL OR p_return_date IS NULL THEN
        RETURN 0;
    END IF;
    RETURN GREATEST(DATEDIFF(p_return_date, p_due_date), 0);
END;

-- fn_hitung_denda untuk hitung denda dari hari terlambat x denda per hari
CREATE FUNCTION fn_hitung_denda(p_due_date DATE, p_return_date DATE)
RETURNS DECIMAL(10,2)
DETERMINISTIC NO SQL
BEGIN
    RETURN LEAST(fn_hari_terlambat(p_due_date, p_return_date) * fn_ambil_setting('TARIF_DENDA_HARI'),
                 fn_ambil_setting('MAX_DENDA'));
END;

-- fn_total_denda_belum_bayar untuk ngecek total denda yang belum dibayar
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
END;

-- fn_jumlah_terlambat untuk jumlah buku yang dipinjam dan sudah terlambat dibalikin sama user yang minjam
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
END;

-- fn_pinjaman_valid untuk cek apakah user yang lagi login boleh pinjam buku apa ngga, ngecek buku apakah masih ada stoknya dan ngecek apakah masih ada limit pinjam buku
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
END;

-- fn_penulis_valid untuk nanti add penulis ke buku biar ada isinya, ga duplikat dan penulisnya ada
CREATE FUNCTION fn_penulis_valid(p_author_ids JSON)
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_input INT DEFAULT 0;
    DECLARE v_unik INT DEFAULT 0;
    DECLARE v_ada INT DEFAULT 0;

    IF p_author_ids IS NULL OR JSON_TYPE(p_author_ids) <> 'ARRAY' OR JSON_LENGTH(p_author_ids) = 0 THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*), COUNT(DISTINCT jt.aid), COUNT(a.id)
      INTO v_input, v_unik, v_ada
      FROM JSON_TABLE(p_author_ids, '$[*]' COLUMNS (aid INT PATH '$')) jt
      LEFT JOIN authors a ON a.id = jt.aid;

    RETURN IF(v_input = v_unik AND v_input = v_ada, 1, 0);
END;