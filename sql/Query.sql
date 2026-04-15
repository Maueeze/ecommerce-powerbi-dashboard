-- =========================================================
-- 01. PREVIEW TABLES
-- Check available tables in the database
-- =========================================================

SELECT name
FROM sqlite_master
WHERE type = 'table';


-- Preview sample rows from key tables
SELECT *
FROM olist_orders_dataset
LIMIT 5;
SELECT *
FROM olist_order_items_dataset
LIMIT 5;
SELECT *
FROM olist_products_dataset
LIMIT 5;
SELECT *
FROM olist_customers_dataset
LIMIT 5;
SELECT *
FROM olist_order_reviews_dataset
LIMIT 5;
SELECT *
FROM olist_order_payments_dataset
LIMIT 5;


-- =========================================================
-- 02. BASE JOIN
-- Combine main tables without aggregation
-- Each row = one order item
-- =========================================================

SELECT oi.order_id,
       oi.order_item_id,
       oi.product_id,
       oi.price,
       oi.freight_value,

       o.customer_id,
       o.order_status,
       o.order_purchase_timestamp,
       o.order_delivered_customer_date,

       p.product_category_name,

       c.customer_city,
       c.customer_state,

       r.review_score

FROM olist_order_items_dataset oi
         JOIN olist_orders_dataset o
              ON oi.order_id = o.order_id
         JOIN olist_products_dataset p
              ON oi.product_id = p.product_id
         JOIN olist_customers_dataset c
              ON o.customer_id = c.customer_id
         LEFT JOIN olist_order_reviews_dataset r
                   ON o.order_id = r.order_id

LIMIT 20;


-- =========================================================
-- 03. ITEM-LEVEL ANALYTICAL VIEW
-- Each row = one product within an order
-- Used for:
-- - product/category analysis
-- - revenue per product/category
-- - geographic analysis
-- =========================================================

DROP VIEW IF EXISTS vw_order_items_analytics;

CREATE VIEW vw_order_items_analytics AS
SELECT oi.order_id,
       oi.order_item_id,
       oi.product_id,
       p.product_category_name,

       o.customer_id,
       o.order_status,
       o.order_purchase_timestamp,
       o.order_delivered_customer_date,

       -- Date-based features
       strftime('%Y', o.order_purchase_timestamp)    AS purchase_year,
       strftime('%m', o.order_purchase_timestamp)    AS purchase_month,
       strftime('%Y-%m', o.order_purchase_timestamp) AS purchase_year_month,

       -- Financial metrics
       oi.price,
       oi.freight_value,
       (oi.price + oi.freight_value)                 AS total_item_value,

       -- Customer location
       c.customer_city,
       c.customer_state,

       -- Customer review score
       r.review_score,

       -- Delivery time in days
       CAST(
               julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)
           AS INTEGER
       )                                             AS delivery_days,

       -- Flags for analysis
       CASE
           WHEN o.order_delivered_customer_date IS NOT NULL THEN 1
           ELSE 0
           END                                       AS is_delivered,

       CASE
           WHEN r.review_score <= 2 THEN 1
           ELSE 0
           END                                       AS low_review_flag,

       CASE
           WHEN (
                    julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)
                    ) > 7 THEN 1
           ELSE 0
           END                                       AS long_delivery_flag

FROM olist_order_items_dataset oi
         JOIN olist_orders_dataset o
              ON oi.order_id = o.order_id
         JOIN olist_products_dataset p
              ON oi.product_id = p.product_id
         JOIN olist_customers_dataset c
              ON o.customer_id = c.customer_id
         LEFT JOIN olist_order_reviews_dataset r
                   ON o.order_id = r.order_id
WHERE o.order_status = 'delivered';


-- Preview
SELECT *
FROM vw_order_items_analytics
LIMIT 20;


-- =========================================================
-- 04. ORDER-LEVEL ANALYTICAL VIEW
-- Each row = one order
-- Used for:
-- - KPI calculations
-- - average order value (AOV)
-- - delivery performance
-- - customer satisfaction analysis
-- =========================================================

DROP VIEW IF EXISTS vw_orders_analytics;

CREATE VIEW vw_orders_analytics AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,

    strftime('%Y', o.order_purchase_timestamp) AS purchase_year,
    strftime('%m', o.order_purchase_timestamp) AS purchase_month,
    strftime('%Y-%m', o.order_purchase_timestamp) AS purchase_year_month,

    SUM(oi.price) AS order_price,
    SUM(oi.freight_value) AS order_freight,
    SUM(oi.price + oi.freight_value) AS total_order_value,

    COUNT(oi.order_item_id) AS number_of_items,

    c.customer_city,
    c.customer_state,

    MAX(r.review_score) AS review_score,

    CAST(
        julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)
        AS INTEGER
    ) AS delivery_days,

    CASE
        WHEN MAX(r.review_score) <= 2 THEN 1
        ELSE 0
    END AS low_review_flag,

    CASE
        WHEN (
            julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)
        ) > 7 THEN 1
        ELSE 0
    END AS long_delivery_flag

FROM olist_orders_dataset o
JOIN olist_order_items_dataset oi
    ON o.order_id = oi.order_id
JOIN olist_customers_dataset c
    ON o.customer_id = c.customer_id
LEFT JOIN olist_order_reviews_dataset r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    c.customer_city,
    c.customer_state;


-- Preview
SELECT *
FROM vw_orders_analytics
LIMIT 20;


-- =========================================================
-- 05. DATA QUALITY CHECKS
-- Basic validation of prepared data
-- =========================================================

-- Total number of orders
SELECT COUNT(*) AS total_orders
FROM vw_orders_analytics;

-- Total number of order items
SELECT COUNT(*) AS total_order_items
FROM vw_order_items_analytics;

-- Missing review scores
SELECT COUNT(*) AS missing_reviews
FROM vw_orders_analytics
WHERE review_score IS NULL;

-- Average delivery time
SELECT AVG(delivery_days) AS avg_delivery_days
FROM vw_orders_analytics;

-- Average order value
SELECT AVG(total_order_value) AS avg_order_value
FROM vw_orders_analytics;


-- =========================================================
-- 06. ANALYTICAL QUERIES (FOR INSIGHTS)
-- =========================================================

-- Revenue over time
SELECT purchase_year_month,
       ROUND(SUM(total_order_value), 2) AS revenue
FROM vw_orders_analytics
GROUP BY purchase_year_month
ORDER BY purchase_year_month;


-- Top 10 product categories by revenue
SELECT product_category_name,
       ROUND(SUM(total_item_value), 2) AS revenue
FROM vw_order_items_analytics
GROUP BY product_category_name
ORDER BY revenue DESC
LIMIT 10;


-- Average review score by state
SELECT customer_state,
       ROUND(AVG(review_score), 2) AS avg_review_score
FROM vw_orders_analytics
GROUP BY customer_state
ORDER BY avg_review_score DESC;


-- Delivery time vs review score
SELECT review_score,
       ROUND(AVG(delivery_days), 2) AS avg_delivery_days
FROM vw_orders_analytics
WHERE review_score IS NOT NULL
GROUP BY review_score
ORDER BY review_score;


-- Top states by revenue
SELECT customer_state,
       ROUND(SUM(total_order_value), 2) AS revenue
FROM vw_orders_analytics
GROUP BY customer_state
ORDER BY revenue DESC
LIMIT 10;


SELECT order_id,
       COUNT(*) AS cnt
FROM vw_orders_analytics
GROUP BY order_id
HAVING COUNT(*) > 1;