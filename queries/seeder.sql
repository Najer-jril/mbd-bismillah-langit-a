USE mbd_uts;

INSERT INTO users (id, name, email, password, role, status) VALUES
(1, 'Admin', 'admin@perpus.id', 'd27b616e1d843c76bf87a434211accf2$05ae7679d4b96aa4102ea6415a111a3615e59d0dcf2313394a18bc91246a1b2c', 'admin',  'active'),
(2, 'Staff Perpus', 'staff@perpus.id', '982918615939384c335a67d87c743575$5f452063515565b461115c3c55e429b2d3c8ffbdbf7afe1d015e5ac8924834ed', 'staff',  'active'),
(3, 'Zaki Zidan', 'zaki@perpus.id', '4bacc6078a2f7db0dbbefd3c8c8a0724$f6fa9f5c8eed193c048612e6a9d3335fd5ac0eb576b546efc4fca9c4d0c08fd3', 'staff',  'active'),
(4, 'Nazril Ilham', 'nazril@perpus.id', '25cf6ee63a94776fd6284296eb281caf$ffca5cd3b03cc6f544626780a012b31b62246ce427f0518dfca70b7f48c7feb6', 'member', 'active'),
(5, 'Adit Rido', 'adit@perpus.id', '24613b1a7501e36414df6f29871ae8db$6b9eb07c535e517c95093b9d7c67908ffea11d3cc5639e22e007e6ae04500921', 'member', 'active'),
(6, 'Mahar Dika', 'mahar@perpus.id', '8c0b39baf03736e0d13e5d00bc2cd812$ed718ebef7218838364492f3b092399a75d9f1cdef65f29c719011dfa86b4e38', 'member', 'suspended'),
(7, 'Radit Yusma', 'radit@perpus.id', '59f2bb393a042f49d0423befd55f083c$815927e56ce12eb8d8412967bc4e70788214e9c302418e7fa2acdefaafdf0e87', 'member', 'inactive');

INSERT INTO authors (id, name) VALUES
(1, 'Ibrahimovic'),
(2, 'Lionel Messi'),
(3, 'Ronaldo'),
(4, 'Alan Turing'),
(5, 'Alber Einstin');

INSERT INTO books (id, title, isbn, author, total_stock, available_stock, genre) VALUES
( 1, 'Algoritma dan Pemrograman', '978-0000000001', 'Ibrahimovic, Lionel Messi', 3, 2, '["informatika","pemrograman"]'),
( 2, 'Bahasa Inggris', '978-0000000002', 'Alan Turing', 2, 2, '["bahasa","umum"]'),
( 3, 'Fisika 1', '978-0000000003', 'Ronaldo', 2, 1, '["sains","fisika"]'),
( 4, 'Matematika 1', '978-0000000004', 'Alber Einstin', 2, 1, '["sains","matematika"]'),
( 5, 'Matematika Diskrit', '978-0000000005', 'Alber Einstin, Ibrahimovic', 2, 2, '["informatika","matematika"]'),
( 6, 'Pengantar Informatika', '978-0000000006', 'Ibrahimovic', 3, 3, '["informatika"]'),
( 7, 'Sistem Digital', '978-0000000007', 'Ronaldo', 1, 0, '["informatika","elektronika"]'),
( 8, 'Aljabar Linier dan Geometri', '978-0000000008', 'Alber Einstin',               2, 2, '["sains","matematika"]'),
( 9, 'Bahasa Indonesia', '978-0000000009', 'Alan Turing', 2, 2, '["bahasa","umum"]'),
(10, 'Fisika 2', '978-0000000010', 'Ronaldo', 2, 2, '["sains","fisika"]');

INSERT INTO book_authors (book_id, author_id, author_order) VALUES
( 1, 1, 1), ( 1, 2, 2),
( 2, 4, 1),
( 3, 3, 1),
( 4, 5, 1),
( 5, 5, 1), ( 5, 1, 2),
( 6, 1, 1),
( 7, 3, 1),
( 8, 5, 1),
( 9, 4, 1),
(10, 3, 1);

INSERT INTO loans (id, user_id, book_id, processed_by, loan_date, due_date, return_date, status, created_at) VALUES
-- nazril user id 4
( 1, 4,  1, 2, CURDATE() - INTERVAL 40 DAY, CURDATE() - INTERVAL 33 DAY, CURDATE() - INTERVAL 35 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 41 DAY, '09:15:00')),
( 2, 4,  6, 3, CURDATE() - INTERVAL 25 DAY, CURDATE() - INTERVAL 18 DAY, CURDATE() - INTERVAL 16 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 26 DAY, '09:15:00')),
( 3, 4,  1, NULL, CURDATE(), CURDATE() + INTERVAL  7 DAY, NULL, 'pending',  NOW()),
( 4, 4,  4, 3, CURDATE() - INTERVAL  2 DAY, CURDATE() + INTERVAL  5 DAY, NULL, 'borrowed', TIMESTAMP(CURDATE() - INTERVAL  3 DAY, '09:15:00')),

-- adit user id 5
( 5, 5,  2, 2, CURDATE() - INTERVAL 30 DAY, CURDATE() - INTERVAL 23 DAY, CURDATE() - INTERVAL 24 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 31 DAY, '09:15:00')),
( 6, 5,  3, 2, CURDATE() - INTERVAL 10 DAY, CURDATE() - INTERVAL  3 DAY, NULL, 'borrowed', TIMESTAMP(CURDATE() - INTERVAL 11 DAY, '09:15:00')),

-- mahar user id 6 + suspended
( 7, 6,  2, 2, CURDATE() - INTERVAL 28 DAY, CURDATE() - INTERVAL 21 DAY, CURDATE() - INTERVAL 22 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 29 DAY, '09:15:00')),
( 8, 6,  7, 3, CURDATE() - INTERVAL  9 DAY, CURDATE() - INTERVAL  2 DAY, NULL, 'borrowed', TIMESTAMP(CURDATE() - INTERVAL 10 DAY, '09:15:00')),
( 9, 6,  5, 1, CURDATE() - INTERVAL  1 DAY, CURDATE() + INTERVAL  6 DAY, NULL, 'rejected', NOW() - INTERVAL 1 DAY),

-- radit user id 7 inactive
(10, 7,  8, 2,    CURDATE() - INTERVAL 20 DAY, CURDATE() - INTERVAL 13 DAY, CURDATE() - INTERVAL  9 DAY, 'returned', TIMESTAMP(CURDATE() - INTERVAL 21 DAY, '09:15:00'));

INSERT INTO fines (id, loan_id, amount, payment_status, created_at) VALUES
(1,  2, 2000.00, 'paid', TIMESTAMP(CURDATE() - INTERVAL 16 DAY, '10:00:00')),
(2, 10, 4000.00, 'unpaid', TIMESTAMP(CURDATE() -  INTERVAL 9 DAY, '10:00:00'));