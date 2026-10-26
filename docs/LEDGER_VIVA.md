# Defending the ledger in two minutes

## What it does

“Payments tell us which booking paid or received a refund. The ledger records the effect on two accounts. Every transaction has equal debits and credits, so the signed total is zero. We preserve financial history and create a new reversal when a booking is cancelled.”

This project uses positive numbers for debits and negative numbers for credits. Amounts are stored as integer paise.

| Action | Account | Debit | Credit |
|---|---|---:|---:|
| Simulated INR 250 payment | DEMO_CASH | 250 | 0 |
| Same payment | TICKET_SALES | 0 | 250 |
| Full refund | DEMO_CASH | 0 | 250 |
| Same refund | TICKET_SALES | 250 | 0 |

For a payment, simulated cash increases with a debit; sales increase with a credit. The refund reverses both. Zero-sum does not mean there is no revenue: the individual accounts show the economic effect. `ledger_balances` uses a signed debit-minus-credit balance, so a normal positive sales amount appears negative there.

## Integration — point to these files

1. Browser confirm → POST /api/bookings → `book_ticket()` inserts a payment.
2. The AFTER INSERT trigger on `payments` calls `post_payment_journal()`.
3. The function creates one `ledger_transactions` header and two `ledger_entries` linked to `ledger_accounts`.
4. Deferred constraint triggers validate the complete journal at COMMIT. An invalid journal prevents the entire booking transaction from committing.
5. Cancellation inserts a REFUND. Its new journal points to the original header through `reverses_id` and posts opposite amounts.

Implementation: `db/004_ledger.sql`. Existing booking and cancellation functions do not need to duplicate ledger code. Direct SQL inserts into payments use the same trigger as the API. Existing payments are backfilled when this migration is applied.

## Show it in the review

1. Book a ticket normally; note its booking ID.
2. Database lab → “Ledger: debits and credits” → Execute query. Find that booking; point out equal debit/credit amounts.
3. Run “Ledger: balance audit”: each row should have two entries, net_paise 0, and balanced true.
4. Cancel the ticket and rerun the journal query. The REFUND is a NEW transaction; its reverses_id identifies the original payment journal.
5. Run “Ledger: payment reconciliation”: every payment and refund should show OK.

## Likely questions

| Question | Answer |
|---|---|
| Why not just use payments? | Payments record the event; the ledger records its balanced effect on accounts, while preserving the original postings. |
| What are the three tables? | Accounts name the buckets, transactions group a posting, entries contain signed amounts. |
| Why a deferred trigger? | The first entry alone cannot balance. Validation waits until all entries are present at transaction commit. |
| Why not a CHECK constraint? | A normal row CHECK cannot validate the sum of multiple journal rows. |
| Why not edit the old payment on refund? | That loses the original history. The refund adds a linked reversal and retains both events. |
| What prevents duplicate journals? | UNIQUE(payment_id) and a unique payment-derived idempotency key. Reposting that same payment returns the original journal ID. |
| What if journal insertion fails? | PostgreSQL rolls back the whole booking statement: ticket, payment, seats, and journal. |
| Is balanced always correct? | No. A wrong pair can also balance. We additionally validate account amounts against the payment, require a full matching reversal, and reconcile payments to journals. |
| Is it a full accounting system? | No. It is a two-account teaching extension with simulated money, immediate sales recognition and full refunds. Taxes, fees, deferred revenue and bank settlement are outside scope. |
| Is it tamper-proof? | Normal UPDATE, DELETE, and TRUNCATE are blocked by triggers. A database owner can alter or disable triggers; production needs restricted roles. |

## SQL to rehearse

```sql
SELECT transaction_id, booking_id, kind, reverses_id, account,
       debit_paise / 100.0 AS debit_rupees,
       credit_paise / 100.0 AS credit_rupees
FROM ledger_journal
ORDER BY transaction_id DESC, account;

SELECT * FROM ledger_audit ORDER BY transaction_id DESC;
-- Expected: zero rows below.
SELECT * FROM ledger_audit WHERE NOT balanced;
SELECT * FROM ledger_reconciliation WHERE status <> 'OK';

SELECT code, name, balance_paise / 100.0 AS signed_balance_rupees
FROM ledger_balances;

-- In psql only: demonstrate rejection. No history is actually changed.
BEGIN;
UPDATE ledger_entries SET amount_paise = 1 WHERE id = 1;
-- Expected: append-only error. Reset the aborted transaction:
ROLLBACK;
```

For a particular ticket, add `WHERE booking_id = <the actual booking ID>` to the first query. The two-account balance total should be zero; movie revenue should match the cash balance if all recorded money events are these full purchases/refunds.
