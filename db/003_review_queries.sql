-- Run one section at a time in psql. Seed IDs are 1, 2, 3; inspect before changing.

-- 1. Inspect tables and columns in psql: \dt and \d customers
SELECT current_database(), version();
SELECT * FROM customers ORDER BY id;

-- 2. Add a customer. Change the email when repeating.
INSERT INTO customers(name,email)
VALUES ('Review Customer','review.customer@example.com') RETURNING *;

-- 3. Explain a JOIN across movie, show, screen and theatre.
SELECT sh.id AS show_id,m.title,t.name AS theatre,sc.name AS screen,
       sh.starts_at,sh.price_paise/100.0 AS price_rupees
FROM shows sh JOIN movies m ON m.id=sh.movie_id
JOIN screens sc ON sc.id=sh.screen_id JOIN theatres t ON t.id=sc.theatre_id
ORDER BY sh.starts_at;

-- 4. Find available seat IDs for show 1.
SELECT ss.seat_id,s.row_label||s.seat_number AS seat
FROM show_seats ss JOIN seats s ON s.id=ss.seat_id
WHERE ss.show_id=1 AND ss.booking_id IS NULL
ORDER BY s.row_label,s.seat_number;

-- 5. Actually book one currently available seat for the new customer.
-- This demonstration picks an available seat automatically.
-- In the UI, the user explicitly chooses the seat IDs.
SELECT book_ticket(
 (SELECT id FROM customers WHERE email='review.customer@example.com'),
 1,
 ARRAY(SELECT seat_id FROM show_seats WHERE show_id=1 AND booking_id IS NULL ORDER BY seat_id LIMIT 1),
 'sir-live-demo-001'
) AS booking_id;

-- 6. Verify the ticket, customer and historical seat labels.
SELECT b.id,c.name,m.title,b.status,b.total_paise/100.0 AS total_rupees,
       string_agg(s.row_label||s.seat_number,', ') AS seats
FROM bookings b JOIN customers c ON c.id=b.customer_id
JOIN shows sh ON sh.id=b.show_id JOIN movies m ON m.id=sh.movie_id
JOIN booking_seats bs ON bs.booking_id=b.id JOIN seats s ON s.id=bs.seat_id
GROUP BY b.id,c.name,m.title ORDER BY b.id DESC;

-- 7. Inspect the simulated payment.
SELECT * FROM payments ORDER BY id DESC;

-- 8. Aggregates, views, revenue and a subquery.
SELECT * FROM show_occupancy ORDER BY show_id;
SELECT title,net_paise/100.0 AS revenue_rupees FROM movie_revenue;
SELECT m.title FROM movies m WHERE NOT EXISTS
 (SELECT 1 FROM shows sh JOIN bookings b ON b.show_id=sh.id WHERE sh.movie_id=m.id);

-- 9. Cancellation: customer ID is checked; refund and seat release are atomic.
SELECT cancel_booking(
 (SELECT id FROM bookings WHERE request_key='sir-live-demo-001'),
 (SELECT id FROM customers WHERE email='review.customer@example.com')
);

-- 10. Basic UPDATE and DELETE on a disposable customer, fully rolled back.
BEGIN;
INSERT INTO customers(name,email) VALUES('Temporary Demo','temporary.review@example.com');
UPDATE customers SET name='Updated Demo' WHERE email='temporary.review@example.com';
SELECT * FROM customers WHERE email='temporary.review@example.com';
DELETE FROM customers WHERE email='temporary.review@example.com';
ROLLBACK;

-- 11. An execution plan; tiny tables may correctly use sequential scans.
EXPLAIN (ANALYZE,BUFFERS) SELECT * FROM bookings WHERE customer_id=1;
