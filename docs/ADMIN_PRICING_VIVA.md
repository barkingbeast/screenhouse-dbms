# Admin management and category pricing

## What to demonstrate

1. Open **Admin → Movies**. Add a title, language, runtime and genre. Use **Edit** to change its metadata or pause sales.
2. Open **Screens**. Add a screen to the theatre and choose 4–12 seats per row. Saving creates three physical rows: A Standard, B Premium, C Recliner.
3. Open **Shows & pricing**. Select a movie, screen, future time and three prices. Saving creates show inventory for every seat in that screen.
4. Open **Book tickets** and select the new show. The category legend lists the show-specific prices. Select seats from multiple rows and inspect the itemized checkout.
5. Confirm a simulated booking, then change that show's prices in Admin. Booking history and SQL still show the original ticket prices.
6. Cancel the original ticket. The refund and ledger reversal use its original total, not the new prices.

For a clean example, use Standard INR 200, Premium INR 350, and Recliner INR 550. Booking A1 + B1 + C1 costs INR 1,100. Raising the future prices to 300/450/650 must leave that ticket and its refundable total at INR 1,100.

## Explain the database design

`seat_categories` names the three types. Each physical `seats` row has a category foreign key. `show_prices` has the composite primary key `(show_id, category_id)`: the same category can cost different amounts in different shows.

`book_ticket()` locks the show and selected inventory, reads category prices from PostgreSQL, sums them, and snapshots both `price_paise` and `category_name` into `booking_seats`. The browser's calculated total is only a preview; the server never accepts a client-supplied price. The payment and journal use the server total.

The original `shows.price_paise` column remains as the Standard base price for compatibility with earlier SQL examples. Two synchronization triggers keep it consistent with the Standard row in `show_prices`. This is deliberate redundancy maintained by the database. Historical ticket prices are deliberate snapshots and do not synchronize with future prices.

Before the upgrade, every seat had the same fare. Existing bookings retain their old amounts and get a Standard snapshot label; their present-day physical seat category can differ. No historical payment is recalculated.

## Admin business rules

- Movie and screen forms support create/edit; unused records support delete.
- Movies/shows can pause sales while retaining history. This is a sales flag, not deletion or a refund.
- A screen cannot be deleted while it has shows; a movie cannot be deleted while it has shows.
- A show with ANY booking history, including cancellations, cannot be deleted or moved to another movie, screen or time. Category prices and sales availability can still change.
- Physical seat layouts are generated once and stay fixed. Screen names can be edited.
- Movie runtime cannot change while the movie has shows, protecting the scheduling assumptions.
- Admin scheduling checks for overlap on the same screen, including movie duration plus 15 minutes for cleanup. Pausing sales does not free the physical scheduling slot.
- Screen locks serialize admin schedule changes. Show locks coordinate price changes with booking, ensuring the ticket gets one consistent price set.
- Prices are positive integer paise, at most INR 100,000, with Standard ≤ Premium ≤ Recliner.

The scheduling/history checks above are in the admin service transaction, with foreign keys and pricing constraints in PostgreSQL. A database owner writing arbitrary SQL can bypass service rules. This is a loopback-only academic admin interface without authentication; it is not production role-based access control.

## Trace a request

Admin form in `public/admin.js` → POST/PUT `/api/admin/...` in `src/server.js` → service functions in `src/admin.js` → parameterized queries on one transaction connection → PostgreSQL → refreshed admin and booking views.

Migration: `db/006_admin_pricing.sql`. Existing databases apply it with `npm run setup`; setup preserves existing records and does not reapply an existing pricing migration.

## SQL to practise

```sql
-- Inspect current prices by movie, screen, show and category.
SELECT show_id, title, screen, category,
       round(price_paise / 100.0, 2) AS price_rupees
FROM seat_price_catalog ORDER BY show_id, price_paise;

-- Find the physical category of every seat.
SELECT s.id, sc.name AS screen, s.row_label || s.seat_number AS seat, c.name AS category
FROM seats s JOIN screens sc ON sc.id=s.screen_id
JOIN seat_categories c ON c.id=s.category_id
ORDER BY sc.id, s.row_label, s.seat_number;

-- Original ticket prices, preserved after an admin edit.
SELECT booking_id, seat_id, category_name, price_paise / 100.0 AS sold_price_rupees
FROM booking_seats ORDER BY booking_id DESC, seat_id;

-- Validate each booking's stored total against its item snapshots.
SELECT b.id, b.total_paise, sum(bs.price_paise) AS item_total
FROM bookings b JOIN booking_seats bs ON bs.booking_id=b.id
GROUP BY b.id HAVING b.total_paise <> sum(bs.price_paise);
-- Expected: no rows.
```

## Likely questions

**Why not put all prices in seats?** Seats are physical. A show owns its current category prices, so the same seat can have different prices in different shows.

**Why store the category name and price in the ticket?** They preserve what was sold at booking time, even if the current show pricing changes later.

**What if prices change while a customer books?** Admin and booking transactions lock the show. One waits, then proceeds with its consistent price set; completed tickets never get repriced.

**Why block deletion?** A movie or show with references forms part of ticket/payment history. Pausing sales preserves that evidence and avoids orphan records.

**Is the admin a login role?** No. It is a local demo management surface. Login and production authorization are separate future work.
