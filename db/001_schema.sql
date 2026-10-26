BEGIN;
CREATE TABLE customers(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, name text NOT NULL CHECK(length(trim(name)) BETWEEN 2 AND 80), email text NOT NULL UNIQUE CHECK(email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'), created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE movies(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, title text NOT NULL, language text NOT NULL, duration_minutes integer NOT NULL CHECK(duration_minutes>0), genre text NOT NULL);
CREATE TABLE theatres(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,name text NOT NULL,city text NOT NULL);
CREATE TABLE screens(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,theatre_id integer NOT NULL REFERENCES theatres,name text NOT NULL,UNIQUE(theatre_id,name));
CREATE TABLE seats(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,screen_id integer NOT NULL REFERENCES screens,row_label text NOT NULL,seat_number integer NOT NULL CHECK(seat_number>0), UNIQUE(screen_id,row_label,seat_number),UNIQUE(id,screen_id));
CREATE TABLE shows(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,movie_id integer NOT NULL REFERENCES movies,screen_id integer NOT NULL REFERENCES screens,starts_at timestamptz NOT NULL,price_paise bigint NOT NULL CHECK(price_paise>0),UNIQUE(id,screen_id));
CREATE TABLE bookings(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,customer_id integer NOT NULL REFERENCES customers,show_id integer NOT NULL REFERENCES shows,status text NOT NULL CHECK(status IN ('CONFIRMED','CANCELLED')),total_paise bigint NOT NULL CHECK(total_paise>0),request_key text NOT NULL UNIQUE,request_payload jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(id,show_id));
CREATE TABLE show_seats(show_id integer NOT NULL,seat_id integer NOT NULL,screen_id integer NOT NULL,booking_id integer,PRIMARY KEY(show_id,seat_id),FOREIGN KEY(show_id,screen_id) REFERENCES shows(id,screen_id),FOREIGN KEY(seat_id,screen_id) REFERENCES seats(id,screen_id),FOREIGN KEY(booking_id,show_id) REFERENCES bookings(id,show_id));
CREATE TABLE booking_seats(booking_id integer NOT NULL,show_id integer NOT NULL,seat_id integer NOT NULL,price_paise bigint NOT NULL CHECK(price_paise>0),PRIMARY KEY(booking_id,seat_id),FOREIGN KEY(booking_id,show_id) REFERENCES bookings(id,show_id),FOREIGN KEY(show_id,seat_id) REFERENCES show_seats(show_id,seat_id));
CREATE TABLE payments(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,booking_id integer NOT NULL REFERENCES bookings,kind text NOT NULL CHECK(kind IN ('PAYMENT','REFUND')),amount_paise bigint NOT NULL CHECK(amount_paise>0),reference text NOT NULL UNIQUE,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(booking_id,kind));
CREATE INDEX ON shows(movie_id,starts_at);
CREATE INDEX ON shows(screen_id);
CREATE INDEX ON screens(theatre_id);
CREATE INDEX ON bookings(customer_id,created_at);
CREATE INDEX ON bookings(show_id);
CREATE INDEX ON booking_seats(show_id,seat_id);
CREATE INDEX ON show_seats(booking_id,show_id);

-- One function is shared by the API and the reviewer's SQL session.
CREATE FUNCTION book_ticket(p_customer integer,p_show integer,p_seats integer[],p_key text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE s shows%ROWTYPE; prior bookings%ROWTYPE; payload jsonb; sorted integer[]; bid integer; n integer;
BEGIN
 IF p_seats IS NULL OR cardinality(p_seats) NOT BETWEEN 1 AND 6 OR array_position(p_seats,NULL) IS NOT NULL THEN RAISE EXCEPTION 'Choose 1 to 6 seats'; END IF;
 SELECT array_agg(x ORDER BY x) INTO sorted FROM (SELECT DISTINCT unnest(p_seats) x) z;
 IF cardinality(sorted)<>cardinality(p_seats) THEN RAISE EXCEPTION 'Duplicate seat selection'; END IF;
 IF p_key IS NULL OR length(p_key) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'Invalid request key'; END IF;
 payload:=jsonb_build_object('customer',p_customer,'show',p_show,'seats',sorted);
 -- Serializes retries of the same request, including requests across shows.
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key,0));
 SELECT * INTO prior FROM bookings WHERE request_key=p_key;
 IF FOUND THEN
   IF prior.request_payload<>payload THEN RAISE EXCEPTION 'Request key reused with different details'; END IF;
   RETURN prior.id;
 END IF;
 SELECT * INTO s FROM shows WHERE id=p_show FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Show not found'; END IF;
 IF s.starts_at<=now() THEN RAISE EXCEPTION 'Show has already started'; END IF;
 PERFORM id FROM customers WHERE id=p_customer;
 IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
 PERFORM seat_id FROM show_seats WHERE show_id=p_show AND seat_id=ANY(sorted) ORDER BY seat_id FOR UPDATE;
 SELECT count(*) INTO n FROM show_seats WHERE show_id=p_show AND seat_id=ANY(sorted) AND booking_id IS NULL;
 IF n<>cardinality(sorted) THEN RAISE EXCEPTION 'Seat unavailable or does not belong to this show'; END IF;
 INSERT INTO bookings(customer_id,show_id,status,total_paise,request_key,request_payload) VALUES(p_customer,p_show,'CONFIRMED',s.price_paise*cardinality(sorted),p_key,payload) RETURNING id INTO bid;
 INSERT INTO booking_seats SELECT bid,p_show,unnest(sorted),s.price_paise;
 UPDATE show_seats SET booking_id=bid WHERE show_id=p_show AND seat_id=ANY(sorted) AND booking_id IS NULL;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>cardinality(sorted) THEN RAISE EXCEPTION 'Seat allocation conflict'; END IF;
 INSERT INTO payments(booking_id,kind,amount_paise,reference) VALUES(bid,'PAYMENT',s.price_paise*cardinality(sorted),'demo-payment-'||bid);
 RETURN bid;
END $$;

CREATE FUNCTION cancel_booking(p_booking integer,p_customer integer) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE b bookings%ROWTYPE; sid integer; show_time timestamptz;
BEGIN
 SELECT show_id INTO sid FROM bookings WHERE id=p_booking;
 IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found'; END IF;
 SELECT starts_at INTO show_time FROM shows WHERE id=sid FOR UPDATE;
 SELECT * INTO b FROM bookings WHERE id=p_booking FOR UPDATE;
 IF b.customer_id<>p_customer THEN RAISE EXCEPTION 'Customer does not own booking'; END IF;
 IF b.status='CANCELLED' THEN RETURN b.id; END IF;
 IF show_time<=now() THEN RAISE EXCEPTION 'Cannot cancel a started show'; END IF;
 UPDATE bookings SET status='CANCELLED' WHERE id=b.id;
 UPDATE show_seats SET booking_id=NULL WHERE show_id=sid AND booking_id=b.id;
 INSERT INTO payments(booking_id,kind,amount_paise,reference) VALUES(b.id,'REFUND',b.total_paise,'demo-refund-'||b.id);
 RETURN b.id;
END $$;

CREATE VIEW show_occupancy AS
SELECT sh.id AS show_id,m.title,sc.name AS screen,sh.starts_at, count(ss.seat_id)::integer AS total_seats,count(ss.booking_id)::integer AS booked_seats,(count(ss.seat_id)-count(ss.booking_id))::integer AS available_seats,round(100.0*count(ss.booking_id)/NULLIF(count(ss.seat_id),0),1) AS occupancy_percent
FROM shows sh JOIN movies m ON m.id=sh.movie_id JOIN screens sc ON sc.id=sh.screen_id LEFT JOIN show_seats ss ON ss.show_id=sh.id GROUP BY sh.id,m.title,sc.name;
CREATE VIEW movie_revenue AS
SELECT m.id,m.title,COALESCE(sum(CASE WHEN p.kind='PAYMENT' THEN p.amount_paise ELSE -p.amount_paise END),0)::bigint AS net_paise
FROM movies m LEFT JOIN shows sh ON sh.movie_id=m.id LEFT JOIN bookings b ON b.show_id=sh.id LEFT JOIN payments p ON p.booking_id=b.id GROUP BY m.id;
REVOKE EXECUTE ON FUNCTION book_ticket(integer,integer,integer[],text),cancel_booking(integer,integer) FROM PUBLIC;
COMMIT;
