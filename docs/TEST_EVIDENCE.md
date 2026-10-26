# Test evidence

Executed: 2026-10-26T12:48:53.245Z

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

Tests use real PostgreSQL connections in a disposable schema with its own seed data. Fault-injection triggers and every test record are removed by dropping only that schema; public demo data is preserved.
