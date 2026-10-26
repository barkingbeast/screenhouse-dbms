# Live review: basic backend questions and demonstration

The ledger extension is now implemented. After practising the core booking flow, read [LEDGER_VIVA.md](LEDGER_VIVA.md) for a short explanation of balanced postings, automatic payment integration, refund reversals and the audit queries.

## Explain the integration in 30 seconds

“The interface is HTML, CSS, and browser JavaScript. A form sends a JSON HTTP request using fetch. A Node.js server handles the API request. The pg library connects to PostgreSQL through a connection pool. It runs SQL with parameters and returns the database rows as JSON. The browser displays the result. All customers, bookings, seats, and payments are stored in PostgreSQL.”

Trace customer creation: `public/app.js` customer-form handler → POST `/api/customers` → `src/server.js` INSERT with `$1`, `$2` → `customers` table → returned customer ID → customer dropdown.

Trace booking: confirm button → POST `/api/bookings` → `SELECT book_ticket($1,$2,$3::integer[],$4)` → function in `db/001_schema.sql` → bookings + booking_seats + show_seats + payments → ticket JSON.

## Rehearse this exact 5-minute sequence

1. Open Customers. Add your own name and a new email. Show the generated customer ID.
2. Open Database lab. Execute “All customers”; point out the same record in PostgreSQL.
3. Open Book tickets. Select the new customer, a show, and two free seats. Confirm booking and show the ticket number.
4. Open Booking history. Locate the same name and ticket number. In Database lab execute “Bookings and customer details” and “Payment and refund history”.
5. Explain the JOIN and run occupancy or revenue. Cancel the booking, then rerun payments: there is one PAYMENT and one REFUND, while booking history remains.
6. For direct SQL, open the terminal using README instructions and execute individual sections of `db/003_review_queries.sql`.

## Likely questions

| Question | Short answer |
|---|---|
| What is the backend? | Node.js HTTP server plus PostgreSQL; pg is the database driver. |
| Why no Express? | Node has an HTTP server built in. This small project uses explicit route handlers to keep the request-to-query path easy to inspect. |
| Where is the connection? | `src/server.js` creates a pg Pool from DATABASE_URL in `.env`. |
| What is an API? | An HTTP endpoint that accepts input and returns data, such as POST /api/customers. |
| How does adding a customer work? | Parameterized INSERT INTO customers(name,email) VALUES($1,$2) RETURNING *. |
| What is a primary key? | A unique, non-null identifier. customers.id identifies one customer. |
| What is a foreign key? | A database-enforced reference. bookings.customer_id references customers.id. |
| Why separate show_seats from seats? | A physical seat can be sold once in each show. Availability belongs to the pair (show_id,seat_id). |
| What is a transaction? | A group of changes that commits or rolls back together. One book_ticket function call executes atomically; PostgreSQL's implicit transaction covers the statement. |
| How do you prevent double booking? | Lock the show, lock its requested seat rows, verify all are free, then assign seats inside the same transaction. Other compliant writers wait and recheck. |
| Can a user book a seat from a different screen? | Composite foreign keys enforce screen consistency, and the booking function requires inventory rows for the chosen show. |
| What is idempotency? | Retrying the same key and details returns the original booking instead of creating a second payment. Different details with that key are rejected. |
| What is a JOIN? | Combining related rows, for example bookings.customer_id = customers.id. |
| What does GROUP BY do? | Groups rows for aggregate calculations, such as occupancy per show. |
| What is a view? | A stored query; show_occupancy computes current availability. It is not a separate copy of the data. |
| Why store money in paise? | Integer arithmetic keeps prices exact. The UI converts paise into rupees for display. |
| Why preserve booking_seats? | Cancellation releases current allocation while keeping historical ticket details and original prices. |
| What happens if a payment INSERT fails? | PostgreSQL rolls back the function call, including booking and seat changes. |
| What prevents SQL injection? | User values are passed as SQL parameters, not concatenated into SQL text. |
| What is normalization here? | Customer, movie, theatre, screen, show, and seat facts are separated; seat lists are relational rows. Price snapshots deliberately preserve history. |
| What is an index? | A lookup structure; bookings(customer_id,created_at) supports customer history. A small table can still be faster with a sequential scan. |
| Why can't you delete a customer with bookings? | The foreign key protects booking history. Keep the customer record or implement a separate archival policy. |
| Is payment real? | No. Payment and refund records are clearly simulated. |
| Does this have authentication? | No. It is a loopback-only review prototype with a customer selector. Production would need login, authorization, stronger validation and separate database roles. |

## Be precise about limitations

The composite inventory key ensures one current allocation per show/seat. All application booking/cancellation flows use the database functions. The demo connection owns its tables, so someone with those database credentials can bypass business rules using arbitrary direct SQL. Do not claim protection against a malicious database owner.

The database lab is a local read-only teaching console with a statement timeout, not a production SQL service. Full login, seat holds, payment gateways, and movie scheduling overlap validation are not implemented. A small double-entry ledger IS implemented; read `LEDGER_VIVA.md` for its explanation and queries. Payment inserts automatically post journals; refunds reverse the original posting, and financial history rejects normal edits.

Driver references: [parameterized queries](https://node-postgres.com/features/queries), [transactions and connection handling](https://node-postgres.com/features/transactions).
