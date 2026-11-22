-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Case study: SwiftPay Digital Wallet (simulated Nigerian fintech)
-- DBMS: PostgreSQL 16
-- Schema is in Third Normal Form (3NF) - see README.md for justification
-- =====================================================================

DROP SCHEMA IF EXISTS swiftpay CASCADE;
CREATE SCHEMA swiftpay;
SET search_path TO swiftpay;

-- ---------------------------------------------------------------------
-- Lookup: KYC tiers (CBN-style tiered KYC limits)
-- ---------------------------------------------------------------------
CREATE TABLE kyc_tier (
    tier_id          SMALLINT      PRIMARY KEY,
    tier_name        VARCHAR(20)   NOT NULL UNIQUE,
    daily_limit      NUMERIC(14,2) NOT NULL CHECK (daily_limit > 0),
    max_balance      NUMERIC(14,2) NOT NULL CHECK (max_balance > 0)
);

-- ---------------------------------------------------------------------
-- Branch / service region
-- ---------------------------------------------------------------------
CREATE TABLE branch (
    branch_id        SERIAL        PRIMARY KEY,
    branch_name      VARCHAR(60)   NOT NULL,
    state            VARCHAR(30)   NOT NULL,
    UNIQUE (branch_name, state)
);

-- ---------------------------------------------------------------------
-- Customer
-- ---------------------------------------------------------------------
CREATE TABLE customer (
    customer_id      SERIAL        PRIMARY KEY,
    first_name       VARCHAR(40)   NOT NULL,
    last_name        VARCHAR(40)   NOT NULL,
    email            VARCHAR(120)  NOT NULL UNIQUE,
    phone            VARCHAR(15)   NOT NULL UNIQUE,
    bvn              CHAR(11)      NOT NULL UNIQUE CHECK (bvn ~ '^[0-9]{11}$'),
    date_of_birth    DATE          NOT NULL CHECK (date_of_birth < CURRENT_DATE - INTERVAL '18 years'),
    tier_id          SMALLINT      NOT NULL REFERENCES kyc_tier(tier_id),
    branch_id        INT           NOT NULL REFERENCES branch(branch_id),
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Account (a customer can hold several accounts: savings, current, wallet)
-- ---------------------------------------------------------------------
CREATE TABLE account (
    account_id       SERIAL        PRIMARY KEY,
    account_number   CHAR(10)      NOT NULL UNIQUE CHECK (account_number ~ '^[0-9]{10}$'),
    customer_id      INT           NOT NULL REFERENCES customer(customer_id) ON DELETE RESTRICT,
    account_type     VARCHAR(10)   NOT NULL CHECK (account_type IN ('SAVINGS','CURRENT','WALLET')),
    balance          NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),   -- no overdraft
    status           VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE'
                                   CHECK (status IN ('ACTIVE','FROZEN','CLOSED')),
    opened_at        TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Transaction ledger (deposit, withdrawal, transfer, reversal)
-- ---------------------------------------------------------------------
CREATE TABLE txn (
    txn_id           BIGSERIAL     PRIMARY KEY,
    reference        UUID          NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    txn_type         VARCHAR(10)   NOT NULL CHECK (txn_type IN ('DEPOSIT','WITHDRAWAL','TRANSFER','REVERSAL')),
    from_account_id  INT           REFERENCES account(account_id),
    to_account_id    INT           REFERENCES account(account_id),
    amount           NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    status           VARCHAR(10)   NOT NULL DEFAULT 'SUCCESS'
                                   CHECK (status IN ('PENDING','SUCCESS','FAILED','REVERSED')),
    channel          VARCHAR(10)   NOT NULL CHECK (channel IN ('APP','USSD','POS','WEB')),
    reversed_txn_id  BIGINT        REFERENCES txn(txn_id),
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    -- business rules expressed as constraints
    CONSTRAINT chk_txn_accounts CHECK (
        (txn_type = 'DEPOSIT'    AND from_account_id IS NULL     AND to_account_id IS NOT NULL) OR
        (txn_type = 'WITHDRAWAL' AND from_account_id IS NOT NULL AND to_account_id IS NULL) OR
        (txn_type IN ('TRANSFER','REVERSAL') AND from_account_id IS NOT NULL AND to_account_id IS NOT NULL
                                 AND from_account_id <> to_account_id)
    )
);

-- ---------------------------------------------------------------------
-- Saved beneficiaries (M:N between customer and account)
-- ---------------------------------------------------------------------
CREATE TABLE beneficiary (
    customer_id      INT           NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    account_id       INT           NOT NULL REFERENCES account(account_id)  ON DELETE CASCADE,
    nickname         VARCHAR(40),
    added_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (customer_id, account_id)
);

-- ---------------------------------------------------------------------
-- Audit log of balance changes (populated by trigger)
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    audit_id         BIGSERIAL     PRIMARY KEY,
    account_id       INT           NOT NULL REFERENCES account(account_id),
    old_balance      NUMERIC(14,2) NOT NULL,
    new_balance      NUMERIC(14,2) NOT NULL,
    changed_by       TEXT          NOT NULL DEFAULT current_user,
    changed_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION trg_audit_balance() RETURNS trigger AS $$
BEGIN
    IF NEW.balance IS DISTINCT FROM OLD.balance THEN
        INSERT INTO audit_log(account_id, old_balance, new_balance)
        VALUES (NEW.account_id, OLD.balance, NEW.balance);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql SET search_path = swiftpay;

CREATE TRIGGER audit_balance
AFTER UPDATE OF balance ON account
FOR EACH ROW EXECUTE FUNCTION trg_audit_balance();
