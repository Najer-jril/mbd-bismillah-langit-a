USE mbd_uts;

DROP TRIGGER IF EXISTS trg_users_before_insert_guard;
DROP TRIGGER IF EXISTS trg_users_before_update_guard;
DROP TRIGGER IF EXISTS trg_users_after_update_revoke;
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


-- trg_users_before_insert_guard untuk merapikan email (all lower), menolak password belum di-hash, status suspended hanya untuk member
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

-- trg_users_before_update_guard untuk mengunci role, menolak password belum di-hash, gaboleh inactive last admin aktif 
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

-- trg_users_after_update_revoke untuk semua akun yang diubah status jadi inactive, semua token login HTTP dicabut / paksa logout
CREATE TRIGGER trg_users_after_update_revoke
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    IF NEW.status = 'inactive' AND OLD.status <> 'inactive' THEN
        DELETE FROM auth_tokens WHERE user_id = NEW.id;
    END IF;
END;

-- trg_users_before_delete_block, melarang hard delete/hapus permanen akun user (pakai status inactive)
CREATE TRIGGER trg_users_before_delete_block
BEFORE DELETE ON users
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User tidak boleh dihapus, gunakan status inactive';
END;

-- trg_authors_after_update_sync, nama penulis diubah terus diperbarui books.author di semua bukunya
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

-- trg_book_authors_after_insert_sync, penulis ditautkan ke buku terus update books.author juga
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

-- trg_book_authors_after_delete_sync, penulis dilepas dari buku terus update books.author juga
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

-- trg_books_before_insert_stock, ketika insert buku baru total stok langsung jadi available_stock, gabisa negatif, dan 
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

-- trg_books_before_update_stock, total_stock berubah jadinya available_stock ikut berubah, kalo ada buku terhapus mau di edeit sudah gabisa karna dibekukan
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
                SET MESSAGE_TEXT = 'Stok total tidak boleh kurang dari unit yang sedang dipinjam/diajukan';
        END IF;
    END IF;
END;

-- trg_books_before_delete_block, larang hapus buku permanen (bisa soft delete lewat sp menghapus_buku)
CREATE TRIGGER trg_books_before_delete_block
BEFORE DELETE ON books
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Buku tidak boleh dihapus permanen, gunakan sp_menghapus_buku';
END;

-- trg_loans_before_insert_guard, pinjaman baru wajib pending dan peminjamnya harus member
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

-- trg_loans_before_update_status, protek flow status peminjaman, harus dari pending ke borrowed/rejected dan borrowed ke returned, ACC wajib ada akun staff
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

-- trg_loans_after_update_stock, usecase <<include>> untuk update stok, stok +1 saat ditolak / dikembalikan
CREATE TRIGGER trg_loans_after_update_stock
AFTER UPDATE ON loans
FOR EACH ROW
BEGIN
    IF (OLD.status = 'pending'  AND NEW.status = 'rejected')
    OR (OLD.status = 'borrowed' AND NEW.status = 'returned') THEN
        UPDATE books SET available_stock = available_stock + 1 WHERE id = NEW.book_id;
    END IF;
END;

-- trg_loans_after_update_fine, usecase <<extend>> buat hitung denda, mencatat denda jika telat mengembalikan
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

-- trg_loans_before_delete_block, gaboleh hapus riwayat peminjaman
CREATE TRIGGER trg_loans_before_delete_block
BEFORE DELETE ON loans
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Data peminjaman tidak boleh dihapus';
END;

-- trg_fines_before_insert_guard, denda hanya untuk pinjaman status returned, dan statusnya langsung unpaid
CREATE TRIGGER trg_fines_before_insert_guard
BEFORE INSERT ON fines
FOR EACH ROW
BEGIN
    IF COALESCE((SELECT status FROM loans WHERE id = NEW.loan_id), '') <> 'returned' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Denda hanya untuk pinjaman yang sudah dikembalikan';
    END IF;
    SET NEW.payment_status = 'unpaid';
END;

-- trg_fines_before_update_lock, total akhir denda lunas, nominal tidak boleh diubah
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

-- trg_fines_before_delete_block, ga boleh hapus denda
CREATE TRIGGER trg_fines_before_delete_block
BEFORE DELETE ON fines
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Data denda tidak boleh dihapus';
END;