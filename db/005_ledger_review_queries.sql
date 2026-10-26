-- SELECT statements also run in Database lab.
SELECT transaction_id,booking_id,kind,reverses_id,account,
       debit_paise/100.0 AS debit_rupees,credit_paise/100.0 AS credit_rupees
FROM ledger_journal ORDER BY transaction_id DESC,account;

SELECT * FROM ledger_balances;
SELECT * FROM ledger_audit ORDER BY transaction_id DESC;
SELECT * FROM ledger_reconciliation ORDER BY payment_id DESC;

-- Both should return zero rows.
SELECT * FROM ledger_audit WHERE NOT balanced;
SELECT * FROM ledger_reconciliation WHERE status <> 'OK';

-- Each payment/refund should have exactly one journal.
SELECT p.id,p.kind,count(t.id) AS journal_count
FROM payments p LEFT JOIN ledger_transactions t ON t.payment_id=p.id
GROUP BY p.id HAVING count(t.id)<>1;

-- Debit cash and credit sales balances offset exactly.
SELECT sum(balance_paise) AS combined_signed_balance FROM ledger_balances;

-- psql only: UPDATE is rejected; ROLLBACK exits the aborted transaction.
BEGIN;
UPDATE ledger_entries SET amount_paise=1 WHERE id=1;
ROLLBACK;
