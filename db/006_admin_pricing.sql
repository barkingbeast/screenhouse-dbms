BEGIN;
LOCK TABLE shows, seats, bookings, booking_seats IN SHARE ROW EXCLUSIVE MODE;
ALTER TABLE movies ADD COLUMN is_active boolean NOT NULL DEFAULT true;
ALTER TABLE shows ADD COLUMN is_active boolean NOT NULL DEFAULT true;
CREATE TABLE seat_categories (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 code text NOT NULL UNIQUE CHECK(code IN ('STANDARD','PREMIUM','RECLINER')),
 name text NOT NULL UNIQUE, sort_order integer NOT NULL UNIQUE
);
INSERT INTO seat_categories(code,name,sort_order) VALUES('STANDARD','Standard',1),('PREMIUM','Premium',2),('RECLINER','Recliner',3);
ALTER TABLE seats ADD COLUMN category_id integer REFERENCES seat_categories(id);
UPDATE seats SET category_id=(SELECT id FROM seat_categories WHERE code=CASE row_label WHEN 'B' THEN 'PREMIUM' WHEN 'C' THEN 'RECLINER' ELSE 'STANDARD' END);
ALTER TABLE seats ALTER COLUMN category_id SET NOT NULL;
-- SQL demonstrations that insert seats without a category remain Standard.
DO $$ DECLARE standard_id integer; BEGIN
 SELECT id INTO standard_id FROM seat_categories WHERE code='STANDARD';
 EXECUTE format('ALTER TABLE seats ALTER COLUMN category_id SET DEFAULT %s',standard_id);
END $$;
CREATE INDEX seats_category_idx ON seats(category_id);
CREATE TABLE show_prices (
 show_id integer NOT NULL REFERENCES shows(id),
 category_id integer NOT NULL REFERENCES seat_categories(id),
 price_paise bigint NOT NULL CHECK(price_paise BETWEEN 1 AND 10000000),
 PRIMARY KEY(show_id,category_id)
);
INSERT INTO show_prices SELECT sh.id,c.id,sh.price_paise+CASE c.code WHEN 'PREMIUM' THEN 10000 WHEN 'RECLINER' THEN 25000 ELSE 0 END FROM shows sh CROSS JOIN seat_categories c;
-- Historical tickets were sold under flat pricing. Preserve those prices and category labels.
ALTER TABLE booking_seats ADD COLUMN category_name text NOT NULL DEFAULT 'Standard';

CREATE FUNCTION sync_show_prices() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='INSERT' THEN
   INSERT INTO show_prices SELECT NEW.id,c.id,LEAST(10000000,NEW.price_paise+CASE c.code WHEN 'PREMIUM' THEN 10000 WHEN 'RECLINER' THEN 25000 ELSE 0 END) FROM seat_categories c;
 ELSE
   UPDATE show_prices SET price_paise=NEW.price_paise
   WHERE show_id=NEW.id AND category_id=(SELECT id FROM seat_categories WHERE code='STANDARD') AND price_paise<>NEW.price_paise;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER show_initial_prices AFTER INSERT OR UPDATE OF price_paise ON shows FOR EACH ROW EXECUTE FUNCTION sync_show_prices();
CREATE FUNCTION sync_standard_price() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.category_id=(SELECT id FROM seat_categories WHERE code='STANDARD') THEN
   UPDATE shows SET price_paise=NEW.price_paise WHERE id=NEW.show_id AND price_paise<>NEW.price_paise;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER standard_price_sync AFTER INSERT OR UPDATE OF price_paise ON show_prices FOR EACH ROW EXECUTE FUNCTION sync_standard_price();

CREATE OR REPLACE FUNCTION book_ticket(p_customer integer,p_show integer,p_seats integer[],p_key text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE s shows%ROWTYPE; prior bookings%ROWTYPE; payload jsonb; sorted integer[]; bid integer; n integer; total bigint;
BEGIN
 IF p_seats IS NULL OR cardinality(p_seats) NOT BETWEEN 1 AND 6 OR array_position(p_seats,NULL) IS NOT NULL THEN RAISE EXCEPTION 'Choose 1 to 6 seats'; END IF;
 SELECT array_agg(x ORDER BY x) INTO sorted FROM (SELECT DISTINCT unnest(p_seats) x) z;
 IF cardinality(sorted)<>cardinality(p_seats) THEN RAISE EXCEPTION 'Duplicate seat selection'; END IF;
 IF p_key IS NULL OR length(p_key) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'Invalid request key'; END IF;
 payload:=jsonb_build_object('customer',p_customer,'show',p_show,'seats',sorted);
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key,0));
 SELECT * INTO prior FROM bookings WHERE request_key=p_key;
 IF FOUND THEN
   IF prior.request_payload<>payload THEN RAISE EXCEPTION 'Request key reused with different details'; END IF;
   RETURN prior.id;
 END IF;
 SELECT * INTO s FROM shows WHERE id=p_show FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Show not found'; END IF;
 IF s.starts_at<=now() THEN RAISE EXCEPTION 'Show has already started'; END IF;
 IF NOT s.is_active OR NOT EXISTS(SELECT 1 FROM movies WHERE id=s.movie_id AND is_active) THEN RAISE EXCEPTION 'This show is not open for booking'; END IF;
 PERFORM id FROM customers WHERE id=p_customer;
 IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
 PERFORM seat_id FROM show_seats WHERE show_id=p_show AND seat_id=ANY(sorted) ORDER BY seat_id FOR UPDATE;
 SELECT count(*) INTO n FROM show_seats WHERE show_id=p_show AND seat_id=ANY(sorted) AND booking_id IS NULL;
 IF n<>cardinality(sorted) THEN RAISE EXCEPTION 'Seat unavailable or does not belong to this show'; END IF;
 -- Stabilize category prices until the booking and ledger commit.
 PERFORM p.category_id FROM show_prices p WHERE p.show_id=p_show ORDER BY p.category_id FOR SHARE;
 SELECT count(*),sum(p.price_paise) INTO n,total
 FROM show_seats ss JOIN seats st ON st.id=ss.seat_id JOIN show_prices p ON p.show_id=ss.show_id AND p.category_id=st.category_id
 WHERE ss.show_id=p_show AND ss.seat_id=ANY(sorted);
 IF n<>cardinality(sorted) THEN RAISE EXCEPTION 'Seat pricing is incomplete for this show'; END IF;
 INSERT INTO bookings(customer_id,show_id,status,total_paise,request_key,request_payload) VALUES(p_customer,p_show,'CONFIRMED',total,p_key,payload) RETURNING id INTO bid;
 INSERT INTO booking_seats(booking_id,show_id,seat_id,price_paise,category_name)
 SELECT bid,p_show,st.id,p.price_paise,c.name FROM seats st JOIN seat_categories c ON c.id=st.category_id JOIN show_prices p ON p.show_id=p_show AND p.category_id=st.category_id WHERE st.id=ANY(sorted);
 UPDATE show_seats SET booking_id=bid WHERE show_id=p_show AND seat_id=ANY(sorted) AND booking_id IS NULL;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>cardinality(sorted) THEN RAISE EXCEPTION 'Seat allocation conflict'; END IF;
 INSERT INTO payments(booking_id,kind,amount_paise,reference) VALUES(bid,'PAYMENT',total,'demo-payment-'||bid);
 RETURN bid;
END $$;
CREATE VIEW seat_price_catalog AS
 SELECT sh.id AS show_id,m.title,sc.name AS screen,c.name AS category,p.price_paise
 FROM show_prices p JOIN shows sh ON sh.id=p.show_id JOIN movies m ON m.id=sh.movie_id
 JOIN screens sc ON sc.id=sh.screen_id JOIN seat_categories c ON c.id=p.category_id;
COMMIT;
