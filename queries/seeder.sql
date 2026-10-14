-- pw all akun Perpus#2026

-- PERSONA MEMBER
--   nazril : bersih                    -> pinjam sukses
--   adit : kuota penuh (3 aktif)     -> gate kuota; pegang eksemplar terakhir "Clean Code"
--   iqbal : denda 4000 belum dibayar  -> gate denda
--   faisal : buku terlambat 5 hari     -> gate keterlambatan
--   mahar : suspended                 -> boleh login, tidak boleh pinjam
--   radit : inactive                  -> tidak boleh login
--   rahmi : pengajuan pending         -> staff ACC
--   shadiq : pengajuan pending         -> staff tolak
--   irfan : pinjam terlambat 3 hari   -> staff terima kembali + denda
--   rizky : pinjam belum jatuh tempo  -> staff terima kembali tanpa denda
--   miftah, abim : riwayat panjang
-- STAFF: galih (2), zaki (3), hilma (4, inactive)   ADMIN: dimas (1)

USE mbd_uts;

-- users
INSERT INTO users (id, name, email, password, role, status) VALUES
(1, 'Admin Dimas', 'dimasadmin@perpus.id', 'd27b616e1d843c76bf87a434211accf2$05ae7679d4b96aa4102ea6415a111a3615e59d0dcf2313394a18bc91246a1b2c', 'admin', 'active'),
(2, 'Staff Galih', 'galihstaff@perpus.id', '982918615939384c335a67d87c743575$5f452063515565b461115c3c55e429b2d3c8ffbdbf7afe1d015e5ac8924834ed', 'staff', 'active'),
(3, 'Staff Zaki', 'zakistaff@perpus.id', '4bacc6078a2f7db0dbbefd3c8c8a0724$f6fa9f5c8eed193c048612e6a9d3335fd5ac0eb576b546efc4fca9c4d0c08fd3', 'staff', 'active'),
(4, 'Staff Hilma', 'hilmastaff@perpus.id', 'a662bc0279ab2c5aee86435ec46a27cf$a9d6918c54542cf5881c869e07d1c3d7c9ce24900263f9c443eebef9e6410eca', 'staff', 'inactive'),
(5, 'Nazril Ilham', 'nazril@perpus.id', '25cf6ee63a94776fd6284296eb281caf$ffca5cd3b03cc6f544626780a012b31b62246ce427f0518dfca70b7f48c7feb6', 'member', 'active'),
(6, 'Adit Rido', 'adit@perpus.id', '24613b1a7501e36414df6f29871ae8db$6b9eb07c535e517c95093b9d7c67908ffea11d3cc5639e22e007e6ae04500921', 'member', 'active'),
(7, 'Iqbal Alex', 'iqbal@perpus.id', '05d7ec1335f8e6d4cb361a9007e16760$c26c29329188c0415f77c399c681636a426dea0a71ef361f4331318cbf6b97aa', 'member', 'active'),
(8, 'Faisal Ical', 'faisal@perpus.id', '97f633ecbe5d1426fb78e73ac88d3746$6567be5327e32f8b2e7348a023cc30b9571a357281832b7e961fc9edec16ac0a', 'member', 'active'),
(9, 'Mahar Dika', 'mahar@perpus.id', '8c0b39baf03736e0d13e5d00bc2cd812$ed718ebef7218838364492f3b092399a75d9f1cdef65f29c719011dfa86b4e38', 'member', 'suspended'),
(10, 'Radit Yusma', 'radit@perpus.id', '59f2bb393a042f49d0423befd55f083c$815927e56ce12eb8d8412967bc4e70788214e9c302418e7fa2acdefaafdf0e87', 'member', 'inactive'),
(11, 'Rahmi Syafitri', 'rahmi@perpus.id', 'cf87f49103de7a7fcb8d5471f5f5c80b$5b85128993750e9f7f6d45dac7df730384ba99903e13f32432e1c5257adcf045', 'member', 'active'),
(12, 'Shadiq Fatiy', 'shadiq@perpus.id', 'ba33ca2860308db39852cb45e6598ea0$451825c1037cf13cd357a41b2987fd957234b9620d2dac38e9398e88e75367af', 'member', 'active'),
(13, 'Irfan Zaki', 'irfan@perpus.id', '8ea373301d37c461619b7b3bd93a9346$ba37b67aa874db540e51168b6ce217187ebc92398200d3d267f49866203169bd', 'member', 'active'),
(14, 'Rizky Wanda', 'rizky@perpus.id', '347b7529fef719f46058940175c3bf8c$58e508c5a044ad3197308818ff2fd91423b6d7ccf781fd24b3d6a23ec02312b3', 'member', 'active'),
(15, 'Miftah Fauzi', 'miftah@perpus.id', '5d9ac3993163e8705589cebcc243f738$64cda493a0712393882799c73dcbb902b8f7c64339fd6b34335f10c26e685062', 'member', 'active'),
(16, 'Abim Akmal', 'abim@perpus.id', 'fe10acee99888bb740c66e7e0ff78762$662ce194da5a38bbc0b5a914e89fe155df91ddc3ccc862dbc8ba84ac9fefd0b2', 'member', 'active');

-- authors
INSERT INTO authors (id, name) VALUES
(1, 'Ramez Elmasri'),
(2, 'Shamkant B. Navathe'),
(3, 'Abraham Silberschatz'),
(4, 'Henry F. Korth'),
(5, 'S. Sudarshan'),
(6, 'Robert C. Martin'),
(7, 'Martin Fowler'),
(8, 'Andrew Hunt'),
(9, 'David Thomas'),
(10, 'Thomas H. Cormen'),
(11, 'Charles E. Leiserson'),
(12, 'Andrea Hirata'),
(13, 'Pramoedya Ananta Toer'),
(14, 'Tere Liye'),
(15, 'Dee Lestari'),
(16, 'Ahmad Fuadi'),
(17, 'Eka Kurniawan');

-- buku
-- available_stock = total_stock - pinjaman aktif (pending + borrowed) di tabel loans
INSERT INTO books (id, title, isbn, author, total_stock, available_stock, genre) VALUES
(1, 'Fundamentals of Database Systems', '978-0133970777', 'Ramez Elmasri, Shamkant B. Navathe', 4, 3, '["database","textbook"]'),
(2, 'Database System Concepts', '978-0078022159', 'Abraham Silberschatz, Henry F. Korth, S. Sudarshan', 3, 2, '["database","textbook"]'),
(3, 'Clean Code', '978-0132350884', 'Robert C. Martin', 1, 0, '["programming"]'),
(4, 'Clean Architecture', '978-0134494166', 'Robert C. Martin', 2, 2, '["programming","architecture"]'),
(5, 'Refactoring', '978-0134757599', 'Martin Fowler', 2, 2, '["programming"]'),
(6, 'Patterns of Enterprise Application Architecture', '978-0321127426', 'Martin Fowler', 1, 1, '["architecture"]'),
(7, 'The Pragmatic Programmer', '978-0135957059', 'Andrew Hunt, David Thomas', 3, 1, '["programming"]'),
(8, 'Introduction to Algorithms', '978-0262046305', 'Thomas H. Cormen, Charles E. Leiserson', 2, 2, '["algorithm","textbook"]'),
(9, 'Laskar Pelangi', '978-9793062792', 'Andrea Hirata', 5, 5, '["novel","fiksi"]'),
(10, 'Sang Pemimpi', '978-9793062921', 'Andrea Hirata', 3, 3, '["novel","fiksi"]'),
(11, 'Bumi Manusia', '978-9799731234', 'Pramoedya Ananta Toer', 4, 3, '["novel","sejarah"]'),
(12, 'Anak Semua Bangsa', '978-9799731241', 'Pramoedya Ananta Toer', 2, 2, '["novel","sejarah"]'),
(13, 'Bumi', '978-6020332956', 'Tere Liye', 4, 3, '["novel","fantasi"]'),
(14, 'Bulan', '978-6020314112', 'Tere Liye', 3, 3, '["novel","fantasi"]'),
(15, 'Supernova: Ksatria, Puteri, dan Bintang Jatuh', '978-6028811125', 'Dee Lestari', 2, 1, '["novel","fiksi"]'),
(16, 'Negeri 5 Menara', '978-9792248616', 'Ahmad Fuadi', 3, 3, '["novel","inspiratif"]'),
(17, 'Cantik Itu Luka', '978-6020312583', 'Eka Kurniawan', 2, 2, '["novel","sastra"]'),
(18, 'Sistem Basis Data (Edisi Lama)', '978-9790000017', 'Abraham Silberschatz', 1, 1, '["database"]');

-- buku lama yang sudah di-soft delete
UPDATE books SET deleted_at = NOW() - INTERVAL 5 DAY WHERE id = 18;

-- penulis buku
INSERT INTO book_authors (book_id, author_id, author_order) VALUES
(1, 1, 1), (1, 2, 2),
(2, 3, 1), (2, 4, 2), (2, 5, 3),
(3, 6, 1),
(4, 6, 1),
(5, 7, 1),
(6, 7, 1),
(7, 8, 1), (7, 9, 2),
(8, 10, 1), (8, 11, 2),
(9, 12, 1),
(10, 12, 1),
(11, 13, 1),
(12, 13, 1),
(13, 14, 1),
(14, 14, 1),
(15, 15, 1),
(16, 16, 1),
(17, 17, 1),
(18, 3, 1);

-- peminjaman
-- Lama pinjam 7 hari: due_date = loan_date + 7.
-- Kolom tanggal ditulis "N hari lalu" relatif ke CURDATE().
-- processed_by: 1 admin, 2 galih, 3 zaki, 4 hilma

INSERT INTO loans (id, user_id, book_id, processed_by, loan_date, due_date, return_date, status, created_at) VALUES

-- Abim: telat 7 hari (denda lunas), lalu tepat waktu
(1, 16, 1, 4, CURDATE() - INTERVAL 65 DAY, CURDATE() - INTERVAL 58 DAY, CURDATE() - INTERVAL 51 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 66 DAY, '09:15:00')),
(2, 16, 17, 2, CURDATE() - INTERVAL 18 DAY, CURDATE() - INTERVAL 11 DAY, CURDATE() - INTERVAL 11 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 19 DAY, '09:15:00')),

-- Radit (nanti inactive): termasuk buku yang sekarang sudah dihapus
(3, 10, 18, 4, CURDATE() - INTERVAL 85 DAY, CURDATE() - INTERVAL 78 DAY, CURDATE() - INTERVAL 79 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 86 DAY, '09:15:00')),
(4, 10, 12, 4, CURDATE() - INTERVAL 70 DAY, CURDATE() - INTERVAL 63 DAY, CURDATE() - INTERVAL 63 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 71 DAY, '09:15:00')),

-- Nazril: 1 riwayat tepat waktu
(5, 5, 9, 2, CURDATE() - INTERVAL 40 DAY, CURDATE() - INTERVAL 33 DAY, CURDATE() - INTERVAL 35 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 41 DAY, '09:15:00')),

-- Miftah: 1 ditolak, 1 telat 1 hari (lunas)
(6, 15, 4, 2, CURDATE() - INTERVAL 15 DAY, CURDATE() - INTERVAL  8 DAY, NULL, 'rejected', TIMESTAMP(CURDATE() - INTERVAL 16 DAY, '09:15:00')),
(7, 15, 16, 3, CURDATE() - INTERVAL 22 DAY, CURDATE() - INTERVAL 15 DAY, CURDATE() - INTERVAL 14 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 23 DAY, '09:15:00')),

-- Adit: kuota penuh (2 borrowed + 1 pending)
(8, 6, 9, 3, CURDATE() - INTERVAL 50 DAY, CURDATE() - INTERVAL 43 DAY, CURDATE() - INTERVAL 43 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 51 DAY, '09:15:00')),
(9, 6, 3, 2, CURDATE() - INTERVAL  2 DAY, CURDATE() + INTERVAL  5 DAY, NULL, 'borrowed', TIMESTAMP(CURDATE() - INTERVAL  3 DAY, '09:15:00')),
(10, 6, 13, 3, CURDATE() - INTERVAL  3 DAY, CURDATE() + INTERVAL  4 DAY, NULL, 'borrowed', TIMESTAMP(CURDATE() - INTERVAL  4 DAY, '09:15:00')),
(11, 6, 7, NULL, CURDATE(), CURDATE() + INTERVAL  7 DAY, NULL, 'pending', NOW()),

-- Iqbal: tepat waktu, telat 3 hari (lunas), telat 4 hari (BELUM lunas)
(12, 7, 11, 2, CURDATE() - INTERVAL 60 DAY, CURDATE() - INTERVAL 53 DAY, CURDATE() - INTERVAL 54 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 61 DAY, '09:15:00')),
(13, 7, 5, 3, CURDATE() - INTERVAL 45 DAY, CURDATE() - INTERVAL 38 DAY, CURDATE() - INTERVAL 35 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 46 DAY, '09:15:00')),
(14, 7, 10, 2, CURDATE() - INTERVAL 20 DAY, CURDATE() - INTERVAL 13 DAY, CURDATE() - INTERVAL  9 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 21 DAY, '09:15:00')),

-- Faisal: sedang terlambat 5 hari
(15, 8, 16, 2, CURDATE() - INTERVAL 30 DAY, CURDATE() - INTERVAL 23 DAY, CURDATE() - INTERVAL 23 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 31 DAY, '09:15:00')),
(16, 8, 2, 3, CURDATE() - INTERVAL 12 DAY, CURDATE() - INTERVAL  5 DAY, NULL, 'borrowed', TIMESTAMP(CURDATE() - INTERVAL 13 DAY, '09:15:00')),

-- Mahar (suspended): telat 2 hari (lunas); pengajuan ditolak otomatis oleh admin saat suspend
(17, 9, 17, 3, CURDATE() - INTERVAL 40 DAY, CURDATE() - INTERVAL 33 DAY, CURDATE() - INTERVAL 31 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 41 DAY, '09:15:00')),
(18, 9, 14, 1, CURDATE() - INTERVAL  1 DAY, CURDATE() + INTERVAL  6 DAY, NULL, 'rejected', NOW() - INTERVAL 1 DAY),

-- Rahmi: riwayat + pengajuan pending (tes ACC)
(19, 11, 4, 2, CURDATE() - INTERVAL 55 DAY, CURDATE() - INTERVAL 48 DAY, CURDATE() - INTERVAL 48 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 56 DAY, '09:15:00')),
(20, 11, 8, 3, CURDATE() - INTERVAL 35 DAY, CURDATE() - INTERVAL 28 DAY, CURDATE() - INTERVAL 28 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 36 DAY, '09:15:00')),
(21, 11, 6, 3, CURDATE() - INTERVAL 25 DAY, CURDATE() - INTERVAL 18 DAY, NULL, 'rejected', TIMESTAMP(CURDATE() - INTERVAL 26 DAY, '09:15:00')),
(22, 11, 1, NULL, CURDATE(), CURDATE() + INTERVAL  7 DAY, NULL, 'pending', NOW()),

-- Shadiq: riwayat + pengajuan pending (tes tolak)
(23, 12, 13, 2, CURDATE() - INTERVAL 28 DAY, CURDATE() - INTERVAL 21 DAY, CURDATE() - INTERVAL 23 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 29 DAY, '09:15:00')),
(24, 12, 15, NULL, CURDATE(), CURDATE() + INTERVAL  7 DAY, NULL, 'pending', NOW()),

-- Irfan: sedang terlambat 3 hari (tes pengembalian + denda)
(25, 13, 9, 2, CURDATE() - INTERVAL 50 DAY, CURDATE() - INTERVAL 43 DAY, CURDATE() - INTERVAL 44 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 51 DAY, '09:15:00')),
(26, 13, 11, 3, CURDATE() - INTERVAL 10 DAY, CURDATE() - INTERVAL  3 DAY, NULL, 'borrowed', TIMESTAMP(CURDATE() - INTERVAL 11 DAY, '09:15:00')),
 
-- Rizky: belum jatuh tempo (tes pengembalian tanpa denda)
(27, 14, 7, 2, CURDATE() - INTERVAL  2 DAY, CURDATE() + INTERVAL  5 DAY, NULL, 'borrowed', TIMESTAMP(CURDATE() - INTERVAL  3 DAY, '09:15:00'));

-- denda
-- amount = hari terlambat x Rp1.000 ; created_at = tanggal pengembalian
INSERT INTO fines (id, loan_id, amount, payment_status, created_at) VALUES
(1, 1, 7000.00, 'paid', TIMESTAMP(CURDATE() - INTERVAL 51 DAY, '10:00:00')),  -- Abim, telat 7 hr
(2, 7, 1000.00, 'paid', TIMESTAMP(CURDATE() - INTERVAL 14 DAY, '10:00:00')),  -- Miftah, telat 1 hr
(3, 13, 3000.00, 'paid', TIMESTAMP(CURDATE() - INTERVAL 35 DAY, '10:00:00')),  -- Iqbal, telat 3 hr
(4, 14, 4000.00, 'unpaid', TIMESTAMP(CURDATE() - INTERVAL  9 DAY, '10:00:00')),  -- Iqbal, telat 4 hr
(5, 17, 2000.00, 'paid', TIMESTAMP(CURDATE() - INTERVAL 31 DAY, '10:00:00'));   -- Mahar, telat 2 hr
