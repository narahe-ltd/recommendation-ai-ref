-- init.sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    transaction_history TEXT,
    preferences TEXT,
    embedding VECTOR(384) 
);

CREATE TABLE IF NOT EXISTS products (
    product_id VARCHAR(50) PRIMARY KEY,
    description TEXT,
    embedding VECTOR(384)
);

CREATE TABLE IF NOT EXISTS usage_logs (
    id SERIAL PRIMARY KEY,
    customer_id VARCHAR(50),
    action TEXT,
    timestamp TIMESTAMP
);

-- DROP INDEX IF EXISTS products_embedding_idx;

-- Re-run this in PostgreSQL
CREATE INDEX IF NOT EXISTS products_embedding_idx 
ON products 
USING hnsw (embedding vector_cosine_ops);

-- Initial test data
INSERT INTO customers (customer_id, transaction_history, preferences, embedding)
VALUES
    ('cust001', 'Checking account usage, loan payment, ATM withdrawals', 'Likes online banking, prefers low fees, quick support', NULL),
    ('cust002', 'Savings account deposits, credit card usage, bill payments', 'Interested in investment options, high interest rates', NULL),
    ('cust003', 'Mortgage payments, frequent transfers, debit card usage', 'Values mobile app, cashback rewards', NULL),
    ('cust004', 'Investment account trades, savings deposits', 'Prefers low-risk investments, detailed reports', NULL),
    ('cust005', 'Credit card purchases, loan applications', 'Likes travel rewards, flexible payments', NULL)
ON CONFLICT (customer_id) DO UPDATE SET
    transaction_history = EXCLUDED.transaction_history,
    preferences = EXCLUDED.preferences,
    embedding = EXCLUDED.embedding;

INSERT INTO products (product_id, description, embedding)
VALUES
    ('prod001', 'Low-fee checking account with mobile banking', NULL),
    ('prod002', 'High-yield savings account with 2% interest', NULL),
    ('prod003', 'Investment portfolio starter with low-risk options', NULL),
    ('prod004', 'Cashback debit card with 1% rewards', NULL),
    ('prod005', 'Travel rewards credit card with no annual fee', NULL),
    ('prod006', 'Online-only checking account with instant transfers', NULL),
    ('prod007', 'Fixed-rate mortgage with flexible terms', NULL),
    ('prod008', 'Premium savings account with 2.5% interest', NULL),
    ('prod009', 'Stock trading account with real-time analytics', NULL),
    ('prod010', 'Personal loan with low interest rates', NULL)
ON CONFLICT (product_id) DO UPDATE SET
    description = EXCLUDED.description,
    embedding = EXCLUDED.embedding;