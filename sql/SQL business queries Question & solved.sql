-- Analysis Structure — 12 Business Questions

-- SECTION A — Churn Overview        (Q1, Q2, Q3)
-- SECTION B — Customer Profile      (Q4, Q5, Q6)
-- SECTION C — Revenue Impact        (Q7, Q8)
-- SECTION D — Engagement Analysis   (Q9, Q10)
-- SECTION E — Payment Health        (Q11)
-- SECTION F — Risk Identification   (Q12)

-- ══════════════════════════════════════════
-- Q1: Overall Churn Rate
-- Technique: Basic aggregation + ROUND
-- ══════════════════════════════════════════

SELECT
    COUNT(*)                                        AS total_subscriptions,
    COUNT(*) FILTER (WHERE churn_flag = 1)          AS total_churned,
    COUNT(*) FILTER (WHERE churn_flag = 0)          AS total_active,
    ROUND(
        COUNT(*) FILTER (WHERE churn_flag = 1)
        * 100.0 / COUNT(*), 2
    )                                               AS churn_rate_pct,
    ROUND(
        COUNT(*) FILTER (WHERE churn_flag = 0)
        * 100.0 / COUNT(*), 2
    )                                               AS retention_rate_pct
FROM fact_subscriptions;

-- ══════════════════════════════════════════
-- Q2: Churn Rate by Subscription Plan
-- Technique: JOIN + GROUP BY + ROUND
-- ══════════════════════════════════════════

SELECT
    dp.plan_name,
    dp.price_inr                                        AS plan_price_inr,
    COUNT(fs.subscription_id)                           AS total_subscriptions,
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)           AS churned,
    COUNT(*) FILTER (WHERE fs.churn_flag = 0)           AS active,
    ROUND(
        COUNT(*) FILTER (WHERE fs.churn_flag = 1)
        * 100.0 / COUNT(*), 2
    )                                                   AS churn_rate_pct,
    ROUND(
        COUNT(*) FILTER (WHERE fs.churn_flag = 0)
        * 100.0 / COUNT(*), 2
    )                                                   AS retention_rate_pct
FROM fact_subscriptions fs
JOIN dim_plans dp ON fs.plan_id = dp.plan_id
GROUP BY dp.plan_name, dp.price_inr, dp.plan_id
ORDER BY dp.price_inr ASC;

-- ══════════════════════════════════════════
-- Q3: Top Churn Reasons with Percentage
-- Technique: FILTER + subquery for total
-- ══════════════════════════════════════════

SELECT
    churn_reason,
    COUNT(*)                                        AS total_churned,
    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM fact_subscriptions WHERE churn_flag = 1),
    2)                                              AS pct_of_total_churn
FROM fact_subscriptions
WHERE churn_flag = 1
GROUP BY churn_reason
ORDER BY total_churned DESC;

-- ══════════════════════════════════════════
-- Q4: Churn by Age Group
-- Technique: CASE WHEN bucketing + JOIN
-- ══════════════════════════════════════════

SELECT
    CASE
        WHEN dc.age BETWEEN 18 AND 25 THEN '18-25 Gen Z'
        WHEN dc.age BETWEEN 26 AND 35 THEN '26-35 Millennials'
        WHEN dc.age BETWEEN 36 AND 45 THEN '36-45 Gen X'
        WHEN dc.age BETWEEN 46 AND 60 THEN '46-60 Boomers'
        ELSE 'Unknown Age'
    END                                             AS age_group,
    COUNT(fs.subscription_id)                       AS total_subscriptions,
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)       AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE fs.churn_flag = 1)
        * 100.0 / COUNT(*), 2
    )                                               AS churn_rate_pct,
    ROUND(AVG(dc.age), 1)                           AS avg_age
FROM fact_subscriptions fs
JOIN dim_customers dc ON fs.customer_id = dc.customer_id
GROUP BY age_group
ORDER BY churn_rate_pct DESC;

-- ══════════════════════════════════════════
-- Q5a: Churn by City (Top 10)
-- Technique: Multi-table JOIN + LIMIT
-- ══════════════════════════════════════════

SELECT
    dc.city,
    dc.state,
    COUNT(fs.subscription_id)                       AS total_subscriptions,
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)       AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE fs.churn_flag = 1)
        * 100.0 / COUNT(*), 2
    )                                               AS churn_rate_pct
FROM fact_subscriptions fs
JOIN dim_customers dc ON fs.customer_id = dc.customer_id
GROUP BY dc.city, dc.state
HAVING COUNT(fs.subscription_id) > 50      -- ignore cities with very few users
ORDER BY churn_rate_pct DESC
LIMIT 10;

-- ══════════════════════════════════════════
-- Q5b: Churn by State (for map visualization)
-- ══════════════════════════════════════════

SELECT
    dc.state,
    COUNT(fs.subscription_id)                       AS total_subscriptions,
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)       AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE fs.churn_flag = 1)
        * 100.0 / COUNT(*), 2
    )                                               AS churn_rate_pct
FROM fact_subscriptions fs
JOIN dim_customers dc ON fs.customer_id = dc.customer_id
GROUP BY dc.state
ORDER BY churn_rate_pct DESC;

-- ══════════════════════════════════════════
-- Q6: Churn by Primary Device
-- Technique: JOIN + GROUP BY
-- ══════════════════════════════════════════

SELECT
    dc.primary_device,
    COUNT(fs.subscription_id)                       AS total_subscriptions,
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)       AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE fs.churn_flag = 1)
        * 100.0 / COUNT(*), 2
    )                                               AS churn_rate_pct,
    ROUND(AVG(fs.tenure_months), 1)                 AS avg_tenure_months
FROM fact_subscriptions fs
JOIN dim_customers dc ON fs.customer_id = dc.customer_id
GROUP BY dc.primary_device
ORDER BY churn_rate_pct DESC;

-- ══════════════════════════════════════════
-- Q7a: Revenue Lost to Churn by Plan
-- Technique: 3-table JOIN + revenue math
-- ══════════════════════════════════════════

SELECT
    dp.plan_name,
    dp.price_inr                                    AS monthly_price_inr,
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)       AS churned_subscriptions,
    -- Revenue lost = churned subscribers × monthly plan price
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)
        * dp.price_inr                              AS monthly_revenue_lost_inr,
    -- Annualized loss potential
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)
        * dp.price_inr * 12                         AS annual_revenue_lost_inr,
    -- Active revenue still being earned
    COUNT(*) FILTER (WHERE fs.churn_flag = 0)
        * dp.price_inr                              AS monthly_active_revenue_inr
FROM fact_subscriptions fs
JOIN dim_plans dp ON fs.plan_id = dp.plan_id
GROUP BY dp.plan_name, dp.price_inr, dp.plan_id
ORDER BY monthly_revenue_lost_inr DESC;

-- ══════════════════════════════════════════
-- Q7b: Total Revenue Summary (Executive KPI)
-- ══════════════════════════════════════════

SELECT
    SUM(dp.price_inr)
        FILTER (WHERE fs.churn_flag = 0)            AS total_active_monthly_revenue_inr,
    SUM(dp.price_inr)
        FILTER (WHERE fs.churn_flag = 1)            AS total_lost_monthly_revenue_inr,
    ROUND(
        SUM(dp.price_inr) FILTER (WHERE fs.churn_flag = 1)
        * 100.0 / SUM(dp.price_inr), 2
    )                                               AS revenue_loss_pct
FROM fact_subscriptions fs
JOIN dim_plans dp ON fs.plan_id = dp.plan_id;

-- ══════════════════════════════════════════
-- Q8: Monthly Churn Trend
-- Technique: CTE + DATE functions + Window Function
-- This is an advanced query — read carefully
-- ══════════════════════════════════════════

WITH monthly_stats AS (
    -- Step 1: Group subscriptions by the month they ended
    -- Only look at churned subscriptions
    SELECT
        TO_CHAR(end_date, 'YYYY-MM')                AS churn_month,
        COUNT(*)                                    AS churned_count
    FROM fact_subscriptions
    WHERE churn_flag = 1
      AND end_date IS NOT NULL
    GROUP BY TO_CHAR(end_date, 'YYYY-MM')
)
-- Step 2: Add a running total and month-over-month change
SELECT
    churn_month,
    churned_count,
    -- Running total of churned customers over time
    SUM(churned_count) OVER (
        ORDER BY churn_month
    )                                               AS cumulative_churned,
    -- Previous month's churn count (LAG looks back 1 row)
    LAG(churned_count) OVER (
        ORDER BY churn_month
    )                                               AS prev_month_churned,
    -- Month over month change
    churned_count - LAG(churned_count) OVER (
        ORDER BY churn_month
    )                                               AS mom_change
FROM monthly_stats
ORDER BY churn_month;

-- ══════════════════════════════════════════
-- Q9a: Engagement vs Churn — Side by Side
-- Technique: 3-table JOIN + conditional AVG
-- ══════════════════════════════════════════

SELECT
    CASE fs.churn_flag
        WHEN 1 THEN 'Churned'
        WHEN 0 THEN 'Active'
    END                                                     AS customer_status,
    COUNT(*)                                                AS total_count,
    ROUND(AVG(fu.avg_watch_hours_per_day), 2)               AS avg_watch_hours_per_day,
    ROUND(AVG(fu.sessions_per_week), 1)                     AS avg_sessions_per_week,
    ROUND(AVG(fu.last_login_days_ago), 1)                   AS avg_days_since_login,
    ROUND(AVG(fu.completion_rate_pct), 1)                   AS avg_completion_rate_pct
FROM fact_subscriptions fs
JOIN fact_usage fu ON fs.subscription_id = fu.subscription_id
GROUP BY fs.churn_flag
ORDER BY fs.churn_flag DESC;

-- ══════════════════════════════════════════
-- Q9b: Engagement Buckets — Who is at risk?
-- ══════════════════════════════════════════

SELECT
    CASE
        WHEN fu.avg_watch_hours_per_day < 1.0   THEN 'Very Low  (<1 hr)'
        WHEN fu.avg_watch_hours_per_day < 2.0   THEN 'Low       (1-2 hrs)'
        WHEN fu.avg_watch_hours_per_day < 3.5   THEN 'Medium    (2-3.5 hrs)'
        ELSE                                         'High      (>3.5 hrs)'
    END                                             AS watch_bucket,
    COUNT(*)                                        AS total_users,
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)       AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE fs.churn_flag = 1)
        * 100.0 / COUNT(*), 2
    )                                               AS churn_rate_pct
FROM fact_subscriptions fs
JOIN fact_usage fu ON fs.subscription_id = fu.subscription_id
WHERE fu.avg_watch_hours_per_day IS NOT NULL
GROUP BY watch_bucket
ORDER BY churn_rate_pct DESC;

-- ══════════════════════════════════════════
-- Q10: Content Preference vs Churn
-- Technique: 3-table JOIN + GROUP BY
-- ══════════════════════════════════════════

SELECT
    fu.content_type_preference,
    COUNT(*)                                        AS total_users,
    COUNT(*) FILTER (WHERE fs.churn_flag = 1)       AS churned,
    COUNT(*) FILTER (WHERE fs.churn_flag = 0)       AS active,
    ROUND(
        COUNT(*) FILTER (WHERE fs.churn_flag = 1)
        * 100.0 / COUNT(*), 2
    )                                               AS churn_rate_pct,
    ROUND(AVG(fu.avg_watch_hours_per_day), 2)       AS avg_watch_hours
FROM fact_subscriptions fs
JOIN fact_usage fu ON fs.subscription_id = fu.subscription_id
GROUP BY fu.content_type_preference
ORDER BY churn_rate_pct ASC;    -- Best retaining content at top

-- ══════════════════════════════════════════
-- Q11: Payment Failure Analysis
-- Technique: CTE + multi-table JOIN
-- ══════════════════════════════════════════

WITH payment_summary AS (
    -- Step 1: Summarize payment health per subscription
    SELECT
        subscription_id,
        COUNT(*)                                    AS total_payments,
        COUNT(*) FILTER (WHERE payment_status = 'Failed')   AS failed_payments,
        COUNT(*) FILTER (WHERE payment_status = 'Success')  AS successful_payments,
        SUM(failed_attempts)                        AS total_failed_attempts,
        ROUND(
            COUNT(*) FILTER (WHERE payment_status = 'Failed')
            * 100.0 / COUNT(*), 2
        )                                           AS failure_rate_pct
    FROM fact_payments
    GROUP BY subscription_id
)
-- Step 2: Connect to churn status
SELECT
    CASE fs.churn_flag
        WHEN 1 THEN 'Churned'
        WHEN 0 THEN 'Active'
    END                                             AS customer_status,
    COUNT(*)                                        AS subscriptions,
    ROUND(AVG(ps.failed_payments), 2)               AS avg_failed_payments,
    ROUND(AVG(ps.failure_rate_pct), 2)              AS avg_failure_rate_pct,
    ROUND(AVG(ps.total_failed_attempts), 2)         AS avg_failed_attempts
FROM fact_subscriptions fs
JOIN payment_summary ps ON fs.subscription_id = ps.subscription_id
GROUP BY fs.churn_flag
ORDER BY fs.churn_flag DESC;

-- ══════════════════════════════════════════
-- Q12: High Risk Active Customer List
-- Technique: CTE + multi-table JOIN + scoring
-- This is your FLAGSHIP query — most impressive
-- ══════════════════════════════════════════

WITH payment_health AS (
    SELECT
        subscription_id,
        COUNT(*) FILTER (WHERE payment_status = 'Failed') AS failed_payments,
        COUNT(*)                                          AS total_payments
    FROM fact_payments
    GROUP BY subscription_id
),
risk_scoring AS (
    SELECT
        dc.customer_id,
        dc.customer_name,
        dc.city,
        dc.state,
        dc.primary_device,
        dp.plan_name,
        dp.plan_id,
        dp.price_inr,
        fs.subscription_id,
        fs.tenure_months,
        fs.churn_flag,
        COALESCE(fu.avg_watch_hours_per_day, 0) AS watch_hours,
        COALESCE(fu.sessions_per_week, 0)       AS sessions,
        COALESCE(fu.last_login_days_ago, 0)     AS last_login,
        COALESCE(fu.completion_rate_pct, 0)     AS completion_rate,
        COALESCE(ph.failed_payments, 0)         AS failed_payments,
        (
          COALESCE(CASE WHEN COALESCE(fu.avg_watch_hours_per_day, 0) < 1.0
                        THEN 3 ELSE 0 END, 0)
        + COALESCE(CASE WHEN COALESCE(fu.sessions_per_week, 0) < 3
                        THEN 2 ELSE 0 END, 0)
        + COALESCE(CASE WHEN COALESCE(fu.last_login_days_ago, 0) > 20
                        THEN 3 ELSE 0 END, 0)
        + COALESCE(CASE WHEN COALESCE(fu.completion_rate_pct, 0) < 30
                        THEN 2 ELSE 0 END, 0)
        + COALESCE(CASE WHEN COALESCE(ph.failed_payments, 0) >= 2
                        THEN 3 ELSE 0 END, 0)
        + COALESCE(CASE WHEN dp.plan_id = 'P001'
                        THEN 1 ELSE 0 END, 0)
        + COALESCE(CASE WHEN fs.tenure_months <= 2
                        THEN 2 ELSE 0 END, 0)
        ) AS risk_score
    FROM fact_subscriptions fs
    JOIN dim_customers dc  ON fs.customer_id     = dc.customer_id
    JOIN dim_plans dp      ON fs.plan_id         = dp.plan_id
    JOIN fact_usage fu     ON fs.subscription_id = fu.subscription_id
    LEFT JOIN payment_health ph ON fs.subscription_id = ph.subscription_id
    WHERE fs.churn_flag = 0
)
SELECT
    customer_id,
    customer_name,
    city,
    state,
    primary_device,
    plan_name,
    price_inr                          AS monthly_price_inr,
    tenure_months,
    ROUND(watch_hours::NUMERIC, 2)     AS avg_daily_watch_hrs,
    sessions                           AS sessions_per_week,
    last_login                         AS days_since_last_login,
    ROUND(completion_rate::NUMERIC, 1) AS completion_rate_pct,
    failed_payments,
    risk_score,
    CASE
        WHEN risk_score >= 10 THEN 'CRITICAL'
        WHEN risk_score >= 7  THEN 'HIGH'
        WHEN risk_score >= 4  THEN 'MEDIUM'
        ELSE                       'LOW'
    END                                AS risk_level
FROM risk_scoring
WHERE risk_score >= 7
ORDER BY risk_score DESC, last_login DESC
LIMIT 50;