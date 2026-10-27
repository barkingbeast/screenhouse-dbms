# Admin and pricing verification

The expanded PostgreSQL suite passes **39 checks**, using a disposable schema and preserving the public demo data. Tests include movie/screen/show CRUD, category-seat generation, mixed-category pricing, original-price refunds, protected history, pause/resume, schedule overlap, concurrent price changes, concurrent scheduling, upper-bound prices and ledger reconciliation.

Browser verification on the local demo:

- Created movie **Review Premiere**, runtime 120 minutes, and **Review Screen** with five seats per row (15 total).
- Created its show for October 29, 2026 at 19:00 local time with Standard INR 200, Premium INR 350, and Recliner INR 550.
- Booked A1/B1/C1 for the seeded Review Demo customer. Ticket **#14** totals INR 1,100 and records each category/price.
- Edited future prices to INR 300/450/650 through Admin. API verification confirms ticket #14 still totals INR 1,100 with its original 200/350/550 item snapshots.
- Selected A2/B2/C2 afterward: itemized checkout totals INR 1,400 using the revised prices. This second selection was not booked.
- Executed the new pricing/snapshot query presets, plus ledger audit and payment reconciliation.
- Desktop check at 1440px: content width 1425px; no page overflow.
- Mobile check at 390px: content width 375px; seat targets remain 44px wide. Admin forms and all five navigation destinations remain available.
- JavaScript syntax checks pass for browser and server modules.

These local demo fixtures remain available for rehearsal. A fresh clone starts with the original seed data; create your own movie/screen/show through Admin as described in ADMIN_PRICING_VIVA.md.

Screenshots: `admin-management.png` and `seat-categories.png`.
