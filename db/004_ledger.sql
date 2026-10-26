-- Run once after the base schema. Existing payments are backfilled atomically.
BEGIN;
LOCK TABLE payments IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE ledger_accounts (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 code text NOT NULL UNIQUE CHECK(code IN ('DEMO_CASH','TICKET_SALES')),
 name text NOT NULL
);
INSERT INTO ledger_accounts(code,name) VALUES ('DEMO_CASH','Simulated cash'),('TICKET_SALES','Ticket sales');

CREATE TABLE ledger_transactions (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 payment_id integer NOT NULL UNIQUE REFERENCES payments(id),
 idempotency_key text NOT NULL UNIQUE,
 reverses_id bigint UNIQUE REFERENCES ledger_transactions(id),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ledger_entries (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 transaction_id bigint NOT NULL REFERENCES ledger_transactions(id),
 account_id integer NOT NULL REFERENCES ledger_accounts(id),
 amount_paise bigint NOT NULL CHECK(amount_paise<>0),
 UNIQUE(transaction_id,account_id)
);
CREATE INDEX ledger_entries_account_idx ON ledger_entries(account_id);

-- Positive = debit, negative = credit. Each journal must balance at COMMIT.
-- Validate its relationship to the payment as well as the zero-sum invariant.
CREATE FUNCTION validate_ledger_journal() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE tid bigint; t ledger_transactions%ROWTYPE; p payments%ROWTYPE;
        original_payment payments%ROWTYPE; entry_count integer; net numeric;
        cash numeric; sales numeric; expected numeric;
BEGIN
 IF TG_TABLE_NAME='ledger_transactions' THEN tid:=NEW.id; ELSE tid:=NEW.transaction_id; END IF;
 SELECT * INTO STRICT t FROM ledger_transactions WHERE id=tid;
 SELECT * INTO STRICT p FROM payments WHERE id=t.payment_id;
 SELECT count(*),COALESCE(sum(e.amount_paise),0),
        COALESCE(sum(e.amount_paise) FILTER (WHERE a.code='DEMO_CASH'),0),
        COALESCE(sum(e.amount_paise) FILTER (WHERE a.code='TICKET_SALES'),0)
 INTO entry_count,net,cash,sales
 FROM ledger_entries e JOIN ledger_accounts a ON a.id=e.account_id WHERE e.transaction_id=tid;
 expected:=CASE WHEN p.kind='PAYMENT' THEN p.amount_paise::numeric ELSE -p.amount_paise::numeric END;
 IF entry_count<>2 OR net<>0 OR cash<>expected OR sales<>-expected THEN
   RAISE EXCEPTION 'Ledger must balance with two entries matching the payment';
 END IF;
 IF t.idempotency_key<>'payment:'||p.id THEN RAISE EXCEPTION 'Invalid ledger payment key'; END IF;
 IF p.kind='PAYMENT' AND t.reverses_id IS NOT NULL THEN RAISE EXCEPTION 'A payment cannot reverse a journal'; END IF;
 IF p.kind='REFUND' THEN
   SELECT op.* INTO original_payment FROM ledger_transactions ot JOIN payments op ON op.id=ot.payment_id WHERE ot.id=t.reverses_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Refund must reverse an original payment journal'; END IF;
   IF original_payment.kind<>'PAYMENT' OR original_payment.booking_id<>p.booking_id OR original_payment.amount_paise<>p.amount_paise THEN
     RAISE EXCEPTION 'Refund must reverse the original booking payment in full';
   END IF;
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER validate_ledger_header AFTER INSERT ON ledger_transactions
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_ledger_journal();
CREATE CONSTRAINT TRIGGER validate_ledger_entry AFTER INSERT ON ledger_entries
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_ledger_journal();

CREATE FUNCTION protect_financial_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Financial history is append-only; record a refund reversal instead'; END $$;
CREATE TRIGGER immutable_ledger_transactions BEFORE UPDATE OR DELETE OR TRUNCATE ON ledger_transactions
 FOR EACH STATEMENT EXECUTE FUNCTION protect_financial_history();
CREATE TRIGGER immutable_ledger_entries BEFORE UPDATE OR DELETE OR TRUNCATE ON ledger_entries
 FOR EACH STATEMENT EXECUTE FUNCTION protect_financial_history();
CREATE TRIGGER immutable_ledger_accounts BEFORE UPDATE OR DELETE OR TRUNCATE ON ledger_accounts
 FOR EACH STATEMENT EXECUTE FUNCTION protect_financial_history();
CREATE TRIGGER immutable_payments BEFORE UPDATE OR DELETE OR TRUNCATE ON payments
 FOR EACH STATEMENT EXECUTE FUNCTION protect_financial_history();

CREATE FUNCTION post_payment_journal(p_payment integer) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE p payments%ROWTYPE; journal_id bigint; original_id bigint; signed_amount bigint;
BEGIN
 SELECT * INTO p FROM payments WHERE id=p_payment FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
 SELECT id INTO journal_id FROM ledger_transactions WHERE payment_id=p.id;
 IF FOUND THEN RETURN journal_id; END IF;
 IF p.kind='REFUND' THEN
   SELECT t.id INTO original_id FROM ledger_transactions t JOIN payments op ON op.id=t.payment_id
   WHERE op.booking_id=p.booking_id AND op.kind='PAYMENT';
   IF NOT FOUND THEN RAISE EXCEPTION 'Original payment journal not found'; END IF;
 END IF;
 signed_amount:=CASE WHEN p.kind='PAYMENT' THEN p.amount_paise ELSE -p.amount_paise END;
 INSERT INTO ledger_transactions(payment_id,idempotency_key,reverses_id)
 VALUES(p.id,'payment:'||p.id,original_id) RETURNING id INTO journal_id;
 INSERT INTO ledger_entries(transaction_id,account_id,amount_paise)
 SELECT journal_id,id,CASE WHEN code='DEMO_CASH' THEN signed_amount ELSE -signed_amount END FROM ledger_accounts;
 RETURN journal_id;
END $$;
CREATE FUNCTION journal_payment_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM post_payment_journal(NEW.id); RETURN NEW; END $$;
CREATE TRIGGER payment_posts_journal AFTER INSERT ON payments
 FOR EACH ROW EXECUTE FUNCTION journal_payment_insert();

-- Keep pre-existing tickets and generate journals for all historical payments.
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT id FROM payments ORDER BY CASE WHEN kind='PAYMENT' THEN 0 ELSE 1 END,id LOOP
   PERFORM post_payment_journal(p.id);
 END LOOP;
END $$;

CREATE VIEW ledger_journal AS
 SELECT t.id AS transaction_id,p.booking_id,p.id AS payment_id,p.kind,t.reverses_id,
        a.code AS account,
        CASE WHEN e.amount_paise>0 THEN e.amount_paise ELSE 0 END AS debit_paise,
        CASE WHEN e.amount_paise<0 THEN -e.amount_paise ELSE 0 END AS credit_paise,
        e.amount_paise,t.created_at
 FROM ledger_transactions t JOIN payments p ON p.id=t.payment_id
 JOIN ledger_entries e ON e.transaction_id=t.id JOIN ledger_accounts a ON a.id=e.account_id;
CREATE VIEW ledger_balances AS
 SELECT a.code,a.name,COALESCE(sum(e.amount_paise),0) AS balance_paise
 FROM ledger_accounts a LEFT JOIN ledger_entries e ON e.account_id=a.id GROUP BY a.id;
CREATE VIEW ledger_audit AS
 SELECT t.id AS transaction_id,p.booking_id,p.kind,count(e.id)::integer AS entry_count,
        COALESCE(sum(e.amount_paise),0) AS net_paise,
        count(e.id)=2 AND COALESCE(sum(e.amount_paise),0)=0
        AND COALESCE(sum(e.amount_paise) FILTER (WHERE a.code='DEMO_CASH'),0)=
            CASE WHEN p.kind='PAYMENT' THEN p.amount_paise::numeric ELSE -p.amount_paise::numeric END
        AS balanced
 FROM ledger_transactions t JOIN payments p ON p.id=t.payment_id
 LEFT JOIN ledger_entries e ON e.transaction_id=t.id LEFT JOIN ledger_accounts a ON a.id=e.account_id
 GROUP BY t.id,p.id;
CREATE VIEW ledger_reconciliation AS
 SELECT p.id AS payment_id,p.booking_id,p.kind,t.id AS transaction_id,
        CASE WHEN t.id IS NULL THEN 'MISSING JOURNAL' WHEN a.balanced IS NOT TRUE THEN 'INVALID JOURNAL' ELSE 'OK' END AS status
 FROM payments p LEFT JOIN ledger_transactions t ON t.payment_id=p.id LEFT JOIN ledger_audit a ON a.transaction_id=t.id;
REVOKE EXECUTE ON FUNCTION post_payment_journal(integer),journal_payment_insert(),validate_ledger_journal(),protect_financial_history() FROM PUBLIC;
COMMIT;
