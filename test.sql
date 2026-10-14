USE mbd_uts;

-- ID referensi, dicari lewat email dan ISBN
SELECT id INTO @admin FROM users WHERE email = 'dimasadmin@perpus.id';
SELECT id INTO @galih FROM users WHERE email = 'galihstaff@perpus.id';
SELECT id INTO @rahmi FROM users WHERE email = 'rahmi@perpus.id';
SELECT id INTO @shadiq FROM users WHERE email = 'shadiq@perpus.id';
SELECT id INTO @irfan FROM users WHERE email = 'irfan@perpus.id';
SELECT id INTO @rizky FROM users WHERE email = 'rizky@perpus.id';
SELECT id INTO @bk_cleancode FROM books WHERE isbn = '978-0132350884'; -- stok 1, sedang dipinjam Adit
SELECT id INTO @bk_bulan FROM books WHERE isbn = '978-6020314112';
SELECT id INTO @bk_laskar FROM books WHERE isbn = '978-9793062792';
SELECT id INTO @bk_supernova FROM books WHERE isbn = '978-6028811125';


-- belum login
SELECT * FROM vw_sesi_saya; -- expected output = 0 baris

SELECT COUNT(*) AS katalog FROM vw_katalog_buku; -- expected output = 0, katalog hanya untuk user yang login

CALL sp_menambah_penulis('Manusia Ular', @x);
-- expected eror = "Belum login"

CALL sp_login('nazril@perpus.id', 'password-salah');
-- expected eror = "Email atau password salah"

CALL sp_login('radit@perpus.id', 'Perpus#2026');
-- expected eror = "Email atau password salah"
-- Password Radit benar, tapi akunnya inactive. Pesannya sengaja disamakan.


-- login akun dimas admin
CALL sp_login('dimasadmin@perpus.id', 'Perpus#2026');

SELECT * FROM vw_sesi_saya; -- expected output = role admin

-- 1.1 Membuat akun <<include>> menetapkan akses (role)
CALL sp_membuat_akun('Rakha Dika', 'rakha@perpus.id', 'Perpus#123', 'member', @rakha);
-- Berexpected output = akun member baru

CALL sp_membuat_akun('Rayhan Cello', 'rayhan@perpus.id', 'Perpus#123', 'staff', @rayhan);
-- Berexpected output = akun staff baru

SELECT user_id, name, email, role, status FROM vw_akun_user WHERE user_id IN (@rakha, @rayhan);
-- expected output = 2 baris, keduanya active

CALL sp_membuat_akun('Duplikat', 'NAZRIL@perpus.id', 'Perpus#123', 'member', @x);
-- expected eror = "Duplicate entry 'nazril@perpus.id'"
-- Email ditulis huruf besar, tapi sistem menyimpannya dalam huruf kecil, jadi tetap terdeteksi kembar.

CALL sp_membuat_akun('Admin Dua', 'admin2@perpus.id', 'Perpus#123', 'admin', @x);
-- expected eror = "Role harus staff atau member"

CALL sp_membuat_akun('Pendek', 'pendek@perpus.id', '123', 'member', @x);
-- expected eror = "Password minimal 8 karakter"

-- 1.2 Menetapkan akses: status akun
CALL sp_ubah_status_akun(@rakha, 'suspended', @n);
SELECT name, status FROM vw_akun_user WHERE user_id = @rakha; -- expected output = suspended

CALL sp_ubah_status_akun(@rakha, 'active', @n);
SELECT name, status FROM vw_akun_user WHERE user_id = @rakha; -- expected output = active lagi

CALL sp_ubah_status_akun(@rayhan, 'suspended', @n);
-- expected eror = "Status suspended hanya untuk member"

CALL sp_ubah_status_akun(@admin, 'inactive', @n);
-- expected eror = "Tidak bisa mengubah status akun sendiri"

CALL sp_ubah_status_akun(@irfan, 'inactive', @n);
-- expected eror = "Member masih meminjam buku, kembalikan dulu"

-- 1.3 Admin juga punya semua hak staff
SELECT loan_id, user_id, title, status FROM vw_detail_peminjaman WHERE status = 'pending';
-- expected output = antrian pengajuan yang menunggu ACC

CALL sp_menambah_penulis('Habiburrahman El Shirazy', @a_habib);
SELECT @a_habib AS author_baru; -- expected output = id penulis baru

-- Admin bukan member, jadi tidak bisa meminjam
SELECT fn_pinjaman_valid(@bk_laskar) AS gate; -- expected output = "Hanya member yang dapat meminjam buku"

CALL sp_meminjam_buku(@bk_laskar, @x);
-- expected eror = "Hanya member yang dapat meminjam buku"

-- 1.4 Logout
CALL sp_logout();
SELECT * FROM vw_sesi_saya; -- expected output = 0 baris

CALL sp_logout();
-- expected eror = "Belum login"


-- login akun galih staff
CALL sp_login('galihstaff@perpus.id', 'Perpus#2026');

-- 2.1 View untuk staff
SELECT * FROM vw_akun_user ORDER BY role, user_id; -- UC melihat akun user
SELECT * FROM vw_status_buku ORDER BY book_id; -- UC melihat status buku

SELECT loan_id, user_id, title, requested_at
  FROM vw_detail_peminjaman WHERE status = 'pending' ORDER BY requested_at;
-- expected output = antrian ACC milik Rahmi, Shadiq, dan Adit

SELECT loan_id, user_id, title, due_date, days_late, fine_estimate
  FROM vw_detail_peminjaman WHERE is_late = 1;
-- expected output = Faisal telat 5 hari, Irfan telat 3 hari

SELECT * FROM vw_detail_denda WHERE payment_status = 'unpaid'; -- expected output = denda Iqbal 4000

SELECT * FROM vw_audit_stok; -- expected output = 0 baris, artinya stok konsisten

-- 2.2 Menambah penulis
CALL sp_menambah_penulis('Leila S. Chudori', @a_leila);
-- Berexpected output =
CALL sp_menambah_penulis('Leila S. Chudori', @x);
-- expected eror = "Duplicate entry 'Leila S. Chudori'"

-- 2.3 Menambah buku
CALL sp_menambah_buku('Laut Bercerita', '978-6024246945', 3, '["novel","sejarah"]', JSON_ARRAY(@a_leila), @bk_laut);
-- Berexpected output =
SELECT book_id, title, author, total_stock, available_stock, book_state
  FROM vw_status_buku WHERE book_id = @bk_laut;
-- expected output = author terisi otomatis "Leila S. Chudori", stok 3/3

CALL sp_menambah_buku('Buku Gagal', '978-0000000001', 1, NULL, '[9999]', @x);
-- expected eror = "Daftar penulis kosong / tidak ditemukan / duplikat"

CALL sp_menambah_buku('ISBN Kembar', '978-0132350884', 1, NULL, JSON_ARRAY(@a_leila), @x);
-- expected eror = "Duplicate entry '978-0132350884'"

-- 2.4 Mengedit detail buku: stok 3 jadi 5, penulis jadi 2 orang
CALL sp_mengedit_detail_buku(@bk_laut, NULL, NULL, 5, NULL, JSON_ARRAY(@a_leila, @a_habib));
-- Berexpected output =
SELECT title, author, total_stock, available_stock FROM vw_status_buku WHERE book_id = @bk_laut;
-- expected output = author "Leila S. Chudori, Habiburrahman El Shirazy", stok 5/5

SELECT * FROM vw_penulis_buku WHERE book_id = @bk_laut ORDER BY author_order;
-- expected output = 2 penulis sesuai urutan

CALL sp_mengedit_detail_buku(@bk_cleancode, NULL, NULL, 0, NULL, NULL);
-- expected eror = "Stok total tidak boleh kurang dari unit yang sedang dipinjam/diajukan"

-- 2.5 Menghapus buku (soft delete)
CALL sp_menghapus_buku(@bk_laut);
-- Berexpected output =
SELECT title, book_state, deleted_at FROM vw_status_buku WHERE book_id = @bk_laut;
-- expected output = book_state "dihapus", deleted_at terisi

CALL sp_menghapus_buku(@bk_cleancode);
-- expected eror = "Buku masih dipinjam / diajukan"

-- 2.6 Mengedit status peminjaman
-- a) ACC pengajuan Rahmi. processed_by terisi id Galih dari sesi login.
SELECT loan_id INTO @L_rahmi FROM vw_detail_peminjaman WHERE user_id = @rahmi AND status = 'pending';

CALL sp_mengedit_status_peminjaman(@L_rahmi, 'approve');
-- Berexpected output =
SELECT loan_id, status, processed_by, @galih AS id_galih, loan_date, due_date
  FROM vw_detail_peminjaman WHERE loan_id = @L_rahmi;
-- expected output = status borrowed, processed_by sama dengan id_galih

-- b) Tolak pengajuan Shadiq. Stok yang tadinya di-reserve kembali.
SELECT available_stock AS supernova_sebelum FROM vw_status_buku WHERE book_id = @bk_supernova; -- expected output = 1

SELECT loan_id INTO @L_shadiq FROM vw_detail_peminjaman WHERE user_id = @shadiq AND status = 'pending';

CALL sp_mengedit_status_peminjaman(@L_shadiq, 'reject');
-- Berexpected output =
SELECT available_stock AS supernova_sesudah FROM vw_status_buku WHERE book_id = @bk_supernova; -- expected output = 2

CALL sp_mengedit_status_peminjaman(@L_shadiq, 'approve');
-- expected eror = "Hanya pengajuan berstatus pending yang bisa diproses"

-- c) Pengembalian tepat waktu (Rizky)
SELECT loan_id INTO @L_rizky FROM vw_detail_peminjaman WHERE user_id = @rizky AND status = 'borrowed';

CALL sp_pengembalian_buku(@L_rizky, 0, @denda);
SELECT @denda AS denda_rizky; -- expected output = 0.00

-- d) Pengembalian terlambat 3 hari (Irfan). Denda tercatat otomatis, belum dibayar.
SELECT loan_id INTO @L_irfan FROM vw_detail_peminjaman WHERE user_id = @irfan AND status = 'borrowed';

CALL sp_pengembalian_buku(@L_irfan, 0, @denda);
SELECT @denda AS denda_irfan; -- expected output = 3000.00

SELECT fine_id, amount, payment_status FROM vw_detail_denda WHERE loan_id = @L_irfan;
-- expected output = 3000, unpaid

-- e) Pelunasan denda Irfan
SELECT fine_id INTO @F_irfan FROM vw_detail_denda WHERE loan_id = @L_irfan;

CALL sp_membayar_denda(@F_irfan);
-- Berexpected output =
SELECT amount, payment_status FROM vw_detail_denda WHERE fine_id = @F_irfan; -- expected output = paid

CALL sp_membayar_denda(@F_irfan);
-- expected eror = "Denda sudah lunas"

CALL sp_pengembalian_buku(@L_irfan, 0, @denda);
-- expected eror = "Hanya pinjaman berstatus borrowed yang bisa dikembalikan"

-- 2.7 Staff tidak bisa membuat akun
CALL sp_membuat_akun('Coba', 'coba@perpus.id', 'Rahasia#123', 'member', @x);
-- expected eror = "Akses ditolak: khusus admin"

SELECT * FROM vw_audit_stok; -- expected output = tetap 0 baris

CALL sp_logout();


-- login member
-- member nazril tanpa tanggungan
CALL sp_login('nazril@perpus.id', 'Perpus#2026');

-- UC melihat katalog buku
SELECT book_id, title, author, availability FROM vw_katalog_buku ORDER BY title;

SELECT book_id, title, author FROM vw_katalog_buku
 WHERE MATCH(title, author) AGAINST ('Tere Liye'); -- cari berdasarkan penulis atau judul

SELECT book_id, title FROM vw_katalog_buku
 WHERE 'sejarah' MEMBER OF (genre); -- filter berdasarkan genre

-- Cek sebelum pinjam ("langsung cek ui"): kuota dan stok
SELECT * FROM vw_kuota_saya; -- expected output = remaining_quota 3

SELECT fn_pinjaman_valid(@bk_bulan) AS gate_bulan, -- expected output = OK
       fn_pinjaman_valid(@bk_cleancode) AS gate_cleancode;   -- expected output = Stok buku habis

-- UC meminjam buku
CALL sp_meminjam_buku(@bk_bulan, @L_nazril);
-- Berexpected output =
SELECT @L_nazril AS loan_baru; -- expected output = id pinjaman baru

SELECT * FROM vw_riwayat_saya ORDER BY requested_at DESC;
-- expected output = hanya riwayat milik Nazril, 1 pending dan 1 returned

SELECT * FROM vw_kuota_saya; -- expected output = remaining_quota 2

CALL sp_meminjam_buku(@bk_cleancode, @x);
-- expected eror = "Stok buku habis"

CALL sp_meminjam_buku(@bk_bulan, @x);
-- expected eror = "Judul ini sedang Anda pinjam / ajukan"

-- Member tidak bisa melihat atau memproses data orang lain
SELECT COUNT(*) AS lihat_semua_pinjaman FROM vw_detail_peminjaman;                -- expected output = 0
SELECT COUNT(*) AS lihat_akun_user FROM vw_akun_user;                             -- expected output = 0
SELECT COUNT(*) AS lihat_pinjaman_rahmi FROM vw_riwayat_saya WHERE loan_id = @L_rahmi; -- expected output = 0

CALL sp_mengedit_status_peminjaman(@L_nazril, 'approve');
-- expected eror = "Akses ditolak: khusus staff/admin"

CALL sp_logout();

-- member adit kuota penuh
CALL sp_login('adit@perpus.id', 'Perpus#2026');

SELECT * FROM vw_kuota_saya; -- expected output = active_loans 3, remaining_quota 0

SELECT fn_pinjaman_valid(@bk_laskar) AS gate; -- expected output = Kuota pinjam habis (maks 3 aktif)

CALL sp_meminjam_buku(@bk_laskar, @x);
-- expected eror = "Kuota pinjam habis (maks 3 aktif)"

CALL sp_logout();

-- member iqbal punya denda yang belum dibayar
CALL sp_login('iqbal@perpus.id', 'Perpus#2026');

SELECT * FROM vw_denda_saya;  -- UC melihat denda. expected output = 3000 paid, 4000 unpaid
SELECT * FROM vw_kuota_saya;  -- expected output = unpaid_fines 4000

CALL sp_meminjam_buku(@bk_laskar, @x);
-- expected eror = "Masih ada denda yang belum dibayar"

CALL sp_logout();

-- member faisal masih memegang buku yang terlambat
CALL sp_login('faisal@perpus.id', 'Perpus#2026');

SELECT title, due_date, is_late, days_late, fine_estimate
  FROM vw_riwayat_saya WHERE status = 'borrowed';
-- expected output = is_late 1, telat 5 hari, estimasi denda 5000

CALL sp_meminjam_buku(@bk_laskar, @x);
-- expected eror = "Masih ada buku yang terlambat dikembalikan"

CALL sp_logout();

-- member mahar suspended, boleh login dan melihat data, tidak boleh meminjam
CALL sp_login('mahar@perpus.id', 'Perpus#2026');

SELECT * FROM vw_sesi_saya;                -- expected output = status suspended
SELECT title, status FROM vw_riwayat_saya; -- expected output = pengajuan "Bulan" berstatus rejected (ditolak saat suspend)
SELECT * FROM vw_denda_saya;               -- expected output = 2000 paid

CALL sp_meminjam_buku(@bk_laskar, @x);
-- expected eror = "Akun sedang disuspend"

CALL sp_logout();

-- member irfan dendanya sudah lunas di 2.6e, jadi boleh meminjam lagi
CALL sp_login('irfan@perpus.id', 'Perpus#2026');

SELECT * FROM vw_kuota_saya; -- expected output = remaining 3, unpaid 0, late 0

CALL sp_meminjam_buku(@bk_laskar, @L_irfan2);
-- Berexpected output =
SELECT loan_id, title, status FROM vw_riwayat_saya WHERE loan_id = @L_irfan2; -- expected output = pending

CALL sp_logout();


-- trigger
-- Bagian ini menjalankan DML langsung tanpa SP dan tanpa login.
-- Trigger tetap menolak perubahan yang melanggar aturan.
UPDATE loans SET status = 'pending' WHERE id = @L_rahmi;
-- expected eror = "Transisi status tidak valid"

UPDATE loans SET status = 'borrowed' WHERE id = @L_nazril;
-- expected eror = "ACC/penolakan wajib diproses staff/admin (processed_by)"

INSERT INTO loans (user_id, book_id, loan_date, due_date, status)
VALUES (@rahmi, @bk_laskar, CURDATE(), CURDATE() + INTERVAL 7 DAY, 'borrowed');
-- expected eror = "Pinjaman baru harus berstatus pending tanpa processed_by & return_date"

INSERT INTO loans (user_id, book_id, loan_date, due_date)
VALUES (@galih, @bk_laskar, CURDATE(), CURDATE() + INTERVAL 7 DAY);
-- expected eror = "Peminjam harus akun member"

INSERT INTO fines (loan_id, amount) VALUES (@L_rahmi, 5000);
-- expected eror = "Denda hanya untuk pinjaman yang sudah dikembalikan"

UPDATE fines SET amount = 1 WHERE id = @F_irfan;
-- expected eror = "Denda sudah lunas dan tidak dapat diubah"

DELETE FROM fines WHERE id = @F_irfan;
-- expected eror = "Data denda tidak boleh dihapus"

DELETE FROM loans WHERE id = @L_rizky;
-- expected eror = "Data peminjaman tidak boleh dihapus"

DELETE FROM books WHERE id = @bk_bulan;
-- expected eror = "Buku tidak boleh dihapus permanen, gunakan sp_menghapus_buku"

DELETE FROM users WHERE id = @rizky;
-- expected eror = "User tidak boleh dihapus, gunakan status inactive"

UPDATE users SET role = 'admin' WHERE id = @rizky;
-- expected eror = "Role akun tidak dapat diubah setelah dibuat"

UPDATE users SET password = 'plaintext' WHERE id = @rizky;
-- expected eror = "Password harus disimpan dalam format hash (salt$sha256)"

UPDATE users SET status = 'inactive' WHERE id = @admin;
-- expected eror = "Admin aktif terakhir tidak boleh dinonaktifkan"

UPDATE books SET available_stock = available_stock - 1 WHERE id = @bk_cleancode;
-- expected eror = "Check constraint 'chk_books_stock' is violated"
-- Stok Clean Code sudah 0, jadi tidak bisa dikurangi lagi.

-- Nama penulis diubah, kolom author di semua bukunya ikut berubah
UPDATE authors SET name = 'Tere Liye (Darwis)' WHERE name = 'Tere Liye';

SELECT title, author FROM books WHERE isbn IN ('978-6020332956', '978-6020314112');
-- expected output = Bumi dan Bulan menampilkan "Tere Liye (Darwis)"

UPDATE authors SET name = 'Tere Liye' WHERE name = 'Tere Liye (Darwis)'; -- kembalikan nama semula


-- final audit login staff
CALL sp_login('galihstaff@perpus.id', 'Perpus#2026');

SELECT * FROM vw_audit_stok; -- expected output = 0 baris, stok tetap konsisten

SELECT status, COUNT(*) AS jumlah FROM vw_detail_peminjaman GROUP BY status;
-- expected output = rekap jumlah pinjaman per status

CALL sp_logout();