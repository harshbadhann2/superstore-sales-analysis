-- Superstore sales analysis.
-- Run from the project root:  psql -d superstore -f sql/analysis.sql
-- Each "\o outputs/<file>.csv" line sends the next query's result to that CSV (for Tableau).
-- "\o" on its own switches output back to the screen.

\pset format csv


-- ============================================================
-- 1a. Sales, profit and profit margin by REGION
-- What: total sales and profit for each region, plus margin = profit / sales.
-- Why:  sales alone can mislead. A region can sell a lot but keep little of it.
--       Margin shows how many cents of profit we keep from each dollar sold.
--       NULLIF avoids a divide-by-zero error if a group ever had zero sales.
-- ============================================================
\o outputs/01a_sales_profit_by_region.csv
SELECT
    region,
    ROUND(SUM(sales), 2)                                  AS total_sales,
    ROUND(SUM(profit), 2)                                 AS total_profit,
    ROUND(100 * SUM(profit) / NULLIF(SUM(sales), 0), 2)   AS profit_margin_pct
FROM orders
GROUP BY region
ORDER BY total_sales DESC;


-- ============================================================
-- 1b. Sales, profit and profit margin by CATEGORY
-- What: same idea as 1a, but split by product category.
-- Why:  tells us which product lines actually make money, not just which sell most.
-- ============================================================
\o outputs/01b_sales_profit_by_category.csv
SELECT
    category,
    ROUND(SUM(sales), 2)                                  AS total_sales,
    ROUND(SUM(profit), 2)                                 AS total_profit,
    ROUND(100 * SUM(profit) / NULLIF(SUM(sales), 0), 2)   AS profit_margin_pct
FROM orders
GROUP BY category
ORDER BY total_sales DESC;


-- ============================================================
-- 2. Month-over-month sales growth using LAG()
-- What: total sales per month, then compare each month with the month before.
-- How:  DATE_TRUNC('month', ...) turns every date into the 1st of its month so we can group by month.
--       LAG(x) is a window function: it looks at the value from the PREVIOUS row
--       (ordered by month) without needing a self-join.
--       Growth % = (this month - last month) / last month * 100.
--       I also use LAG(x, 12) = the same month last year, because this business is very
--       seasonal (big Nov/Dec, weak Jan/Feb), so year-over-year is the fairer comparison.
-- Why:  shows the trend and seasonality, and is the input for the forecast.
-- ============================================================
\o outputs/02_monthly_sales_growth.csv
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', order_date)::date AS month,
        SUM(sales)                            AS sales
    FROM orders
    GROUP BY 1
)
SELECT
    month,
    ROUND(sales, 2)                                                   AS sales,
    ROUND(LAG(sales) OVER (ORDER BY month), 2)                        AS prev_month_sales,
    ROUND(100 * (sales - LAG(sales) OVER (ORDER BY month))
              / NULLIF(LAG(sales) OVER (ORDER BY month), 0), 2)       AS mom_growth_pct,
    ROUND(100 * (sales - LAG(sales, 12) OVER (ORDER BY month))
              / NULLIF(LAG(sales, 12) OVER (ORDER BY month), 0), 2)   AS yoy_growth_pct
FROM monthly
ORDER BY month;


-- ============================================================
-- 3. Top 10 customers by revenue using RANK()
-- What: add up each customer's sales, rank them from highest to lowest, keep the top 10.
-- How:  RANK() OVER (ORDER BY revenue DESC) numbers the rows 1, 2, 3...
--       If two customers tie they get the same rank (and the next rank is skipped).
--       We can't filter on a window function in WHERE directly, so we rank inside a CTE
--       first and filter in the outer query.
-- Why:  shows who the most valuable customers are, and whether they are also profitable.
-- ============================================================
\o outputs/03_top10_customers.csv
WITH customer_revenue AS (
    SELECT
        customer_id,
        customer_name,
        segment,
        COUNT(DISTINCT order_id)                    AS orders,
        SUM(sales)                                  AS revenue,
        SUM(profit)                                 AS profit,
        RANK() OVER (ORDER BY SUM(sales) DESC)      AS revenue_rank
    FROM orders
    GROUP BY customer_id, customer_name, segment
)
SELECT
    revenue_rank,
    customer_id,
    customer_name,
    segment,
    orders,
    ROUND(revenue, 2) AS revenue,
    ROUND(profit, 2)  AS profit
FROM customer_revenue
WHERE revenue_rank <= 10
ORDER BY revenue_rank;


-- ============================================================
-- 4a. Loss-making sub-categories
-- What: sub-categories whose TOTAL profit is negative, with their average discount.
-- How:  HAVING filters after grouping (WHERE filters rows before grouping),
--       so HAVING SUM(profit) < 0 keeps only the groups that lost money overall.
-- Why:  these are products we are selling at a loss. Showing the average discount next
--       to the loss hints at the cause (compare with ~15.6% average discount company-wide).
-- ============================================================
\o outputs/04a_loss_making_subcategories.csv
SELECT
    category,
    sub_category,
    ROUND(SUM(sales), 2)                                  AS total_sales,
    ROUND(SUM(profit), 2)                                 AS total_profit,
    ROUND(100 * SUM(profit) / NULLIF(SUM(sales), 0), 2)   AS profit_margin_pct,
    ROUND(100 * AVG(discount), 1)                         AS avg_discount_pct
FROM orders
GROUP BY category, sub_category
HAVING SUM(profit) < 0
ORDER BY total_profit;


-- ============================================================
-- 4b. How discount level relates to profit
-- What: put every order line into a discount band and compare profit in each band.
-- How:  CASE WHEN turns the exact discount into a readable band. MIN(discount) is only
--       used to sort the bands in the right order.
-- Why:  tests the idea from 4a across the whole business. If margin turns negative
--       above a certain discount, that is a clear pricing recommendation.
-- ============================================================
\o outputs/04b_discount_vs_profit.csv
SELECT
    CASE
        WHEN discount = 0     THEN '0% (no discount)'
        WHEN discount <= 0.20 THEN '1-20%'
        WHEN discount <= 0.40 THEN '21-40%'
        ELSE                       'Over 40%'
    END                                                   AS discount_band,
    COUNT(*)                                              AS order_lines,
    ROUND(SUM(sales), 2)                                  AS total_sales,
    ROUND(SUM(profit), 2)                                 AS total_profit,
    ROUND(100 * SUM(profit) / NULLIF(SUM(sales), 0), 2)   AS profit_margin_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE profit < 0) / COUNT(*), 1) AS pct_lines_losing_money
FROM orders
GROUP BY discount_band
ORDER BY MIN(discount);


-- ============================================================
-- 5. Repeat vs one-time customers using a CTE
-- What: count each customer's distinct orders, label them 'Repeat' (2+ orders) or
--       'One-time' (1 order), then compare the two groups.
-- How:  a CTE (WITH ... AS) is a named temporary result. Step 1 builds one row per
--       customer; step 2 groups those rows by the label. It reads top-to-bottom like
--       the steps you would explain out loud. COUNT(DISTINCT order_id) matters because
--       one order can have many product rows.
--       SUM(...) OVER () is the grand total across all groups, used for the % share.
-- Why:  tells us whether revenue depends on loyal customers or on new ones.
-- ============================================================
\o outputs/05_repeat_vs_onetime_customers.csv
WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS num_orders,
        SUM(sales)               AS revenue
    FROM orders
    GROUP BY customer_id
),
labelled AS (
    SELECT
        CASE WHEN num_orders > 1 THEN 'Repeat' ELSE 'One-time' END AS customer_type,
        num_orders,
        revenue
    FROM customer_orders
)
SELECT
    customer_type,
    COUNT(*)                                                  AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_of_customers,
    ROUND(SUM(revenue), 2)                                    AS revenue,
    ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)  AS pct_of_revenue,
    ROUND(AVG(num_orders), 1)                                 AS avg_orders_per_customer,
    ROUND(SUM(revenue) / COUNT(*), 2)                         AS avg_revenue_per_customer
FROM labelled
GROUP BY customer_type
ORDER BY customers DESC;


\o

-- ============================================================
-- Full clean table for Tableau (one row per order line, UTF-8, ISO dates).
-- ============================================================
\copy (SELECT * FROM orders ORDER BY row_id) TO 'outputs/superstore_clean.csv' WITH (FORMAT csv, HEADER true)
