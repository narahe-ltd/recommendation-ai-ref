-- init.sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    transaction_history TEXT,
    preferences TEXT,
    embedding VECTOR(384) 
);

CREATE TABLE products (
    product_id VARCHAR(50) PRIMARY KEY,
    description TEXT,
    embedding VECTOR(384)
);

CREATE TABLE usage_logs (
    id SERIAL PRIMARY KEY,
    customer_id VARCHAR(50),
    action TEXT,
    timestamp TIMESTAMP
);

CREATE INDEX ON products USING hnsw (embedding vector_cosine_ops);