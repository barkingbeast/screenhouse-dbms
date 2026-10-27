-- Review queries only; schema upgrade is 006_admin_pricing.sql.
SELECT id,title,language,duration_minutes,is_active FROM movies ORDER BY id;
SELECT show_id,title,screen,category,round(price_paise/100.0,2) AS price_rupees
FROM seat_price_catalog ORDER BY show_id,price_paise;

SELECT sc.name,s.row_label||s.seat_number AS seat,c.name AS category
FROM seats s JOIN screens sc ON sc.id=s.screen_id JOIN seat_categories c ON c.id=s.category_id
ORDER BY sc.id,s.row_label,s.seat_number;

SELECT booking_id,seat_id,category_name,round(price_paise/100.0,2) AS sold_price_rupees
FROM booking_seats ORDER BY booking_id DESC,seat_id;

-- Snapshot consistency: zero rows expected.
SELECT b.id,b.total_paise,sum(bs.price_paise) AS item_total
FROM bookings b JOIN booking_seats bs ON bs.booking_id=b.id
GROUP BY b.id HAVING b.total_paise<>sum(bs.price_paise);

-- Standard base price synchronization: zero rows expected.
SELECT sh.id FROM shows sh JOIN show_prices p ON p.show_id=sh.id
JOIN seat_categories c ON c.id=p.category_id
WHERE c.code='STANDARD' AND sh.price_paise<>p.price_paise;
