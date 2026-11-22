-- =====================================================================
-- Portfolio 3 - Safe funds transfer as an ACID transaction
-- Concurrency control: pessimistic row locks (SELECT ... FOR UPDATE)
-- taken in a fixed order (lowest account_id first) to prevent deadlock.
-- =====================================================================
SET search_path TO swiftpay;

CREATE OR REPLACE PROCEDURE transfer_funds(p_from INT, p_to INT, p_amount NUMERIC, p_channel TEXT DEFAULT 'APP')
LANGUAGE plpgsql SET search_path = swiftpay AS $$
DECLARE
    v_from_bal NUMERIC; v_from_status TEXT; v_to_status TEXT;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

    -- lock both rows in a deterministic order -> no circular wait -> no deadlock
    PERFORM 1 FROM account WHERE account_id IN (p_from, p_to) ORDER BY account_id FOR UPDATE;

    SELECT balance, status INTO v_from_bal, v_from_status FROM account WHERE account_id = p_from;
    SELECT status INTO v_to_status FROM account WHERE account_id = p_to;

    IF v_from_status <> 'ACTIVE' OR v_to_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Account not active (from=%, to=%)', v_from_status, v_to_status;
    END IF;
    IF v_from_bal < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds: balance %, requested %', v_from_bal, p_amount;
    END IF;

    UPDATE account SET balance = balance - p_amount WHERE account_id = p_from;
    UPDATE account SET balance = balance + p_amount WHERE account_id = p_to;
    INSERT INTO txn(txn_type, from_account_id, to_account_id, amount, status, channel)
    VALUES ('TRANSFER', p_from, p_to, p_amount, 'SUCCESS', p_channel);
END $$;

-- Known starting state for the demos
UPDATE account SET balance = 100000, status = 'ACTIVE' WHERE account_id IN (101, 102, 103);
DELETE FROM audit_log;
