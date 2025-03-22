-- test_data.sql
INSERT INTO customers (customer_id, transaction_history, preferences, embedding) VALUES
('cust001', 'Checking account usage, loan payment', 'Likes online banking, prefers low fees', NULL),
('cust002', 'Savings account deposits, credit card usage', 'Interested in investment options', NULL);

INSERT INTO products (product_id, description, embedding) VALUES
('prod001', 'Low-fee checking account', NULL),
('prod002', 'High-yield savings account', NULL),
('prod003', 'Investment portfolio starter', NULL);

-- test_data.sql (manual vectors)
INSERT INTO customers (customer_id, transaction_history, preferences, embedding) VALUES
('cust011', 'Checking account usage, loan payment', 'Likes online banking, prefers low fees', 
 ('[' || array_to_string(ARRAY[0.1, 0.2, 0.3]::float[] || array_fill(0::float, ARRAY[381]), ',') || ']')::vector),
('cust012', 'Savings account deposits, credit card usage', 'Interested in investment options', 
 ('[' || array_to_string(ARRAY[0.2, 0.1, 0.4]::float[] || array_fill(0::float, ARRAY[381]), ',') || ']')::vector);

INSERT INTO products (product_id, description, embedding) VALUES
('prod011', 'Low-fee checking account', 
 ('[' || array_to_string(ARRAY[0.15, 0.25, 0.35]::float[] || array_fill(0::float, ARRAY[381]), ',') || ']')::vector),
('prod012', 'High-yield savings account', 
 ('[' || array_to_string(ARRAY[0.25, 0.15, 0.45]::float[] || array_fill(0::float, ARRAY[381]), ',') || ']')::vector),
('prod013', 'Investment portfolio starter', 
 ('[' || array_to_string(ARRAY[0.22, 0.12, 0.42]::float[] || array_fill(0::float, ARRAY[381]), ',') || ']')::vector);