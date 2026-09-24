-- Load the raw Superstore CSV into a typed table.
-- Run from the project root:  psql -d superstore -f sql/load.sql

DROP TABLE IF EXISTS orders;

-- One row = one product line inside an order (an order can have several rows).
CREATE TABLE orders (
    row_id        INTEGER PRIMARY KEY,
    order_id      TEXT    NOT NULL,
    order_date    DATE    NOT NULL,
    ship_date     DATE    NOT NULL,
    ship_mode     TEXT,
    customer_id   TEXT    NOT NULL,
    customer_name TEXT,
    segment       TEXT,
    country       TEXT,
    city          TEXT,
    state         TEXT,
    postal_code   TEXT,          -- text, not a number: keeps leading zeros like 05408
    region        TEXT,
    product_id    TEXT,
    category      TEXT,
    sub_category  TEXT,
    product_name  TEXT,
    sales         NUMERIC(12,4) NOT NULL,  -- NUMERIC = exact decimals, no float rounding on money
    quantity      INTEGER       NOT NULL,
    discount      NUMERIC(4,2)  NOT NULL,  -- 0.20 means 20% off
    profit        NUMERIC(12,4) NOT NULL
);

-- Dates in the file are US-style (11/8/2016), so tell Postgres to read them month-first.
SET datestyle = 'ISO, MDY';

-- The file was saved by Excel in Windows-1252, not UTF-8.
\copy orders FROM 'data/superstore.csv' WITH (FORMAT csv, HEADER true, ENCODING 'WIN1252')

SELECT COUNT(*) AS rows_loaded FROM orders;
