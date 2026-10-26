# Ledger implementation verification

- Applied `004_ledger.sql` to the existing demo database. Existing payments were backfilled without replacing bookings.
- Ran setup again: it detected the existing ledger and preserved all journals.
- Ran the full PostgreSQL test suite: 23 checks passed in an isolated schema, including concurrent seat contention, immutable history, exact refund reversals, idempotent reposting, deferred validation and injected ledger failures during booking/cancellation.
- Verified zero bad journals and zero unreconciled payment records in the live demo database.
- Opened Database lab and executed the journal query from the new View journal button.
- Executed Check balances through the browser: eight journal rows were returned, each with two entries, net_paise 0 and balanced true, including a refund journal.
- Newly created bookings appeared in the live journal during verification, confirming that automatic posting is active after migration.
- Saved the audit screenshot as `docs/ledger-proof.png`.

Counts describe the verification snapshot. Additional bookings/refunds will add journals automatically.
