# Test evidence

Executed: 2026-10-27T06:43:22.310Z

- PASS: Base schema, seed and ledger migration apply in an isolated test schema
- PASS: Add customer through INSERT RETURNING
- PASS: Two-seat booking calculates exact total
- PASS: Identical retry returns original ticket and one payment
- PASS: Changed payload with same key rejected
- PASS: Already-booked seat rejected
- PASS: Duplicate seats rejected
- PASS: Nonexistent or cross-show seat rejected
- PASS: Two real connections: second booking waits then fails on same seat
- PASS: Rollback leaves no ticket, allocation, or payment
- PASS: Cancellation retry: one refund, ticket history preserved
- PASS: Released seat can be rebooked
- PASS: Cancellation ownership checked
- PASS: Seat from another screen rejected
- PASS: Payment automatically creates exact cash debit and sales credit
- PASS: Posting the same payment again returns the original journal
- PASS: Refund records a new journal reversing both original entries
- PASS: All seed, payment and refund journals reconcile
- PASS: Journal update/delete/truncate and payment edits are rejected
- PASS: Deferred balance check rejects COMMIT and rolls back an incomplete journal plus payment
- PASS: A zero-sum journal with amounts that do not match its payment is rejected
- PASS: Ledger insert failure rolls back the booking, payment and seat allocation
- PASS: Ledger failure during cancellation preserves the original booking and seat
- PASS: Admin creates and edits a movie
- PASS: Admin creates category seats automatically and edits a screen
- PASS: Admin schedules a show with inventory and three category prices
- PASS: Admin rejects overlapping show times on the same screen
- PASS: Mixed-category booking totals the server prices and snapshots each seat
- PASS: Price edits preserve historical ticket values and idempotent retries
- PASS: New bookings use the revised category prices
- PASS: Cancellation refunds the original mixed-category total after prices change
- PASS: Admin cannot delete or reschedule records with booking history
- PASS: Admin validates scheduled runtimes, price order and exact two-decimal currency
- PASS: Paused movie or show rejects new bookings
- PASS: Concurrent admin price update waits for booking; the ticket keeps one consistent price set
- PASS: Concurrent admin scheduling allows only one overlapping show
- PASS: Unused shows can move screens and unused movies/screens/shows can be deleted
- PASS: Maximum supported price works for all three categories
- PASS: Admin catalog exposes prices and every mixed-price payment/refund reconciles

Tests use real PostgreSQL connections in a disposable schema with its own seed data. Fault-injection triggers and every test record are removed by dropping only that schema; public demo data is preserved.
