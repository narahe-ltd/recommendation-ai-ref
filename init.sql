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

DROP INDEX IF EXISTS products_embedding_idx;

-- Re-run this in PostgreSQL
CREATE INDEX IF NOT EXISTS products_embedding_idx 
ON products 
USING hnsw (embedding vector_cosine_ops);

-- test_data.sql
INSERT INTO customers (customer_id, transaction_history, preferences, embedding) VALUES
('cust001', 'Checking account usage, loan payment', 'Likes online banking, prefers low fees', NULL),
('cust002', 'Savings account deposits, credit card usage', 'Interested in investment options', NULL);

INSERT INTO products (product_id, description, embedding) VALUES
('prod001', 'Low-fee checking account', NULL),
('prod002', 'High-yield savings account', NULL),
('prod003', 'Investment portfolio starter', NULL);