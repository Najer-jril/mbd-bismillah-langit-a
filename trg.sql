-- =====================================================================
-- TRIGGER versi PLAIN untuk DBeaver (tanpa DELIMITER, tanpa //)
-- CARA PAKAI (Mac):
--   1. Blok USE + semua DROP TRIGGER -> Option + X
--   2. Blok 1 trigger (CREATE TRIGGER s/d END;) -> Cmd + Enter
--   3. Kerjakan berurutan dari atas. Wajib: function sudah dibuat dulu,
--      dan trg_loans_after_update_stock harus ada sebelum
--      trg_loans_after_update_fine (dipakai di FOLLOWS).
-- =====================================================================
USE mbd_uts;

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
DROP TRIGGER IF EXISTS trg_loans_after_update_fine;      -- di-drop sebelum _stock karena FOLLOWS
DROP TRIGGER IF EXISTS trg_loans_after_update_stock;
DROP TRIGGER IF EXISTS trg_loans_before_delete_block;
DROP TRIGGER IF EXISTS trg_fines_before_insert_guard;
DROP TRIGGER IF EXISTS trg_fines_before_update_lock;
DROP TRIGGER IF EXISTS trg_fines_before_delete_block;

-- ------------------------------------------------------------- USERS

-- trg_users_before_insert_guard untuk merapikan email (huruf kecil, tanpa spasi),
-- menolak password yang belum di-hash, dan memastikan status suspended hanya untuk member
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
END;

-- trg_users_before_update_guard untuk mengunci role (tidak bisa diubah setelah dibuat),
-- menolak password baru yang belum di-hash, dan mencegah admin aktif terakhir dinonaktifkan
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
END;

-- trg_users_before_delete_block untuk melarang hapus user permanen (pakai status inactive)
CREATE TRIGGER trg_users_before_delete_block
BEFORE DELETE ON users
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User tidak boleh dihapus, gunakan status inactive';
END;

-- ------------------------------------------------------------- AUTHORS / BOOK_AUTHORS

-- trg_authors_after_update_sync untuk memperbarui books.author di semua buku karya penulis
-- itu ketika nama penulis diubah
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
END;

-- trg_book_authors_after_insert_sync untuk mengisi ulang books.author (gabungan nama penulis)
-- setiap kali penulis ditautkan ke buku
CREATE TRIGGER trg_book_authors_after_insert_sync
AFTER INSERT ON book_authors
FOR EACH ROW
BEGIN
    UPDATE books
       SET author = (SELECT LEFT(GROUP_CONCAT(a.name ORDER BY ba.author_order SEPARATOR ', '), 200)
                       FROM book_authors ba JOIN authors a ON a.id = ba.author_id
                      WHERE ba.book_id = NEW.book_id)
     WHERE id = NEW.book_id;
END;

-- trg_book_authors_after_delete_sync untuk mengisi ulang books.author setiap kali
-- penulis dilepas dari buku (kosong '' kalau sudah tidak ada penulis)
CREATE TRIGGER trg_book_authors_after_delete_sync
AFTER DELETE ON book_authors
FOR EACH ROW
BEGIN
    UPDATE books
       SET author = COALESCE((SELECT LEFT(GROUP_CONCAT(a.name ORDER BY ba.author_order SEPARATOR ', '), 200)
                                FROM book_authors ba JOIN authors a ON a.id = ba.author_id
                               WHERE ba.book_id = OLD.book_id), '')
     WHERE id = OLD.book_id;
END;

-- ------------------------------------------------------------- BOOKS

-- trg_books_before_insert_stock untuk buku baru: available_stock otomatis = total_stock
-- (nilai dari input diabaikan) dan buku baru tidak boleh langsung berstatus terhapus
CREATE TRIGGER trg_books_before_insert_stock
BEFORE INSERT ON books
FOR EACH ROW
BEGIN
    IF NEW.total_stock < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'total_stock tidak boleh negatif';
    END IF;
    SET NEW.available_stock = NEW.total_stock;
    SET NEW.deleted_at = NULL;
END;

-- trg_books_before_update_stock untuk menggeser available_stock ketika total_stock diubah
-- (mis. total 3 -> 5, available ikut +2), menolak total lebih kecil dari eksemplar yang
-- sedang dipinjam, dan membekukan buku yang sudah di-soft delete
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
END;

-- trg_books_before_delete_block untuk melarang hapus buku permanen (wajib soft delete
-- lewat sp_menghapus_buku)
CREATE TRIGGER trg_books_before_delete_block
BEFORE DELETE ON books
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Buku tidak boleh dihapus permanen, gunakan sp_menghapus_buku';
END;

-- ------------------------------------------------------------- LOANS

-- trg_loans_before_insert_guard untuk memastikan pinjaman baru selalu lahir sebagai
-- pengajuan 'pending' (belum diproses, belum kembali) dan peminjamnya harus member
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
END;

-- trg_loans_before_update_status untuk menjaga alur status pinjaman
-- (pending -> borrowed/rejected, borrowed -> returned), ACC/tolak wajib ada staff-nya
-- di processed_by, dan return_date otomatis diisi hari ini saat dikembalikan
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
END;

-- trg_loans_after_update_stock untuk <<include>> update stok buku: stok +1 ketika
-- pengajuan ditolak (reservasi batal) atau buku dikembalikan
CREATE TRIGGER trg_loans_after_update_stock
AFTER UPDATE ON loans
FOR EACH ROW
BEGIN
    IF (OLD.status = 'pending'  AND NEW.status = 'rejected')
    OR (OLD.status = 'borrowed' AND NEW.status = 'returned') THEN
        UPDATE books SET available_stock = available_stock + 1 WHERE id = NEW.book_id;
    END IF;
END;

-- trg_loans_after_update_fine untuk <<extend>> menghitung denda: kalau buku kembali
-- lewat jatuh tempo, otomatis catat denda 'unpaid'. FOLLOWS = dijalankan SETELAH
-- trg_loans_after_update_stock (urutan pasti karena event & timing-nya sama)
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
END;

-- trg_loans_before_delete_block untuk melarang hapus riwayat peminjaman
CREATE TRIGGER trg_loans_before_delete_block
BEFORE DELETE ON loans
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Data peminjaman tidak boleh dihapus';
END;

-- ------------------------------------------------------------- FINES

-- trg_fines_before_insert_guard untuk memastikan denda hanya dibuat untuk pinjaman yang
-- sudah dikembalikan, dan denda baru selalu berstatus 'unpaid'
CREATE TRIGGER trg_fines_before_insert_guard
BEFORE INSERT ON fines
FOR EACH ROW
BEGIN
    IF COALESCE((SELECT status FROM loans WHERE id = NEW.loan_id), '') <> 'returned' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Denda hanya untuk pinjaman yang sudah dikembalikan';
    END IF;
    SET NEW.payment_status = 'unpaid';
END;

-- trg_fines_before_update_lock untuk mengunci denda: yang sudah lunas tidak bisa diubah,
-- dan nominal / pinjaman pada denda tidak boleh diubah manual
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
END;

-- trg_fines_before_delete_block untuk melarang hapus denda (sama dengan memutihkan utang)
CREATE TRIGGER trg_fines_before_delete_block
BEFORE DELETE ON fines
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Data denda tidak boleh dihapus';
END;