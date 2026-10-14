-- =====================================================================
-- SISTEM PERPUSTAKAAN - MySQL 8.4
-- File 01: SCHEMA  (aman dijalankan ulang: semua tabel di-drop dulu)
--
-- Perubahan dari ERD:
--   * serial -> INT AUTO_INCREMENT, jsonb -> JSON, *_enum -> ENUM
--   * + authors, book_authors   (UC: menambah penulis)
--   * + user_sessions           (mekanisme "user yang sedang login")
--   * books.author  = salinan DENORMALISASI nama penulis (diisi trigger)
--   * books.deleted_at          (soft delete)
--   * users.password = 'salt$sha256'  (verifikasi di DB, lihat fn_hash_password)
--   * loans.status   = pending -> borrowed -> returned | pending -> rejected
--                      "terlambat" TIDAK disimpan, dihitung di view
-- =====================================================================
CREATE DATABASE IF NOT EXISTS perpustakaan
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE perpustakaan;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS fines, loans, book_authors, books, authors, user_sessions, users;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
CREATE TABLE users (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    email       VARCHAR(100) NOT NULL,
    password    VARCHAR(255) NOT NULL,          -- format: <salt 32 hex>$<sha256 64 hex>
    role        ENUM('admin','staff','member') NOT NULL DEFAULT 'member',
    status      ENUM('active','suspended','inactive') NOT NULL DEFAULT 'active',
    created_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_users_email UNIQUE (email),
    INDEX idx_users_role_status (role, status)
) ENGINE=InnoDB;

-- Sesi login, 1 baris per koneksi MySQL.
-- ENGINE=MEMORY: isi otomatis kosong saat server restart, sehingga
-- CONNECTION_ID() yang dipakai ulang setelah restart tidak mewarisi sesi lama.
CREATE TABLE user_sessions (
    connection_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,   -- = CONNECTION_ID()
    user_id       INT NOT NULL,
    login_at      DATETIME NOT NULL
) ENGINE=MEMORY;

-- ---------------------------------------------------------------------
CREATE TABLE authors (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_authors_name UNIQUE (name)
) ENGINE=InnoDB;

CREATE TABLE books (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    isbn VARCHAR(20)  NOT NULL,
    author VARCHAR(200) NOT NULL DEFAULT '',   -- DENORMALISASI, diisi trigger
    total_stock INT NOT NULL,
    available_stock INT NOT NULL DEFAULT 0,             -- dikelola SP & trigger
    genre JSON NULL,                          -- contoh: ["database","textbook"]
    deleted_at TIMESTAMP NULL DEFAULT NULL,        -- soft delete
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_books_isbn UNIQUE (isbn),
    CONSTRAINT chk_books_stock CHECK (total_stock >= 0 AND available_stock BETWEEN 0 AND total_stock),
    FULLTEXT INDEX ft_books_search (title, author),             -- cari judul/penulis
    INDEX idx_books_genre ((CAST(genre AS CHAR(50) ARRAY))),    -- filter genre: MEMBER OF
    INDEX idx_books_deleted (deleted_at)
) ENGINE=InnoDB;

CREATE TABLE book_authors (
    book_id INT NOT NULL,
    author_id INT NOT NULL,
    author_order TINYINT UNSIGNED NOT NULL DEFAULT 1,           -- urutan nama di sampul
    PRIMARY KEY (book_id, author_id),
    INDEX idx_ba_author (author_id),
    CONSTRAINT fk_ba_book FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ba_author FOREIGN KEY (author_id) REFERENCES authors(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
CREATE TABLE loans (
    id INT  AUTO_INCREMENT PRIMARY KEY,
    user_id INT  NOT NULL,                     -- member pengaju
    book_id INT  NOT NULL,
    processed_by INT  NULL,                         -- staff yang ACC / menolak
    loan_date DATE NOT NULL,                     -- tgl pengajuan, di-reset saat ACC
    due_date DATE NOT NULL,
    return_date DATE NULL,
    status ENUM('pending','borrowed','returned','rejected') NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,  -- waktu pengajuan
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_loans_user  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_loans_book  FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE RESTRICT,
    CONSTRAINT fk_loans_staff FOREIGN KEY (processed_by) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT chk_loans_dates CHECK (due_date >= loan_date
                                      AND (return_date IS NULL OR return_date >= loan_date)),
    INDEX idx_loans_user_status (user_id, status),     -- kuota, riwayat member
    INDEX idx_loans_status_due (status, due_date),    -- daftar terlambat
    INDEX idx_loans_status_created (status, created_at),  -- antrian ACC
    INDEX idx_loans_book_status (book_id, status)
) ENGINE=InnoDB;

CREATE TABLE fines (
    id INT AUTO_INCREMENT PRIMARY KEY,
    loan_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_status ENUM('unpaid','paid') NOT NULL DEFAULT 'unpaid',
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_fines_loan UNIQUE (loan_id),
    CONSTRAINT fk_fines_loan FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE RESTRICT,
    CONSTRAINT chk_fines_amount CHECK (amount > 0),
    INDEX idx_fines_status (payment_status)
) ENGINE=InnoDB;
