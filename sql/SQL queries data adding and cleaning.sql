-- -- Create a dedicated database for this project
-- CREATE DATABASE streambharat_ott;

-- -- Connect to it
-- \c streambharat_ott;

CREATE TABLE dim_plans (
    plan_id        VARCHAR(10)  PRIMARY KEY,
    plan_name      VARCHAR(50)  NOT NULL,
    price_inr      INTEGER      NOT NULL,
    duration_days  INTEGER      NOT NULL,
    content_access VARCHAR(50),
    max_screens    INTEGER
);

COPY dim_plans FROM 'D:\Downloads\claude P1 data\dim_plans.csv' CSV HEADER;

-- Verify
SELECT * FROM dim_plans;

-- Staging table = exact same columns, ZERO constraints
-- No PRIMARY KEY, no NOT NULL, accepts everything including duplicates

CREATE TABLE staging_customers (
    customer_id          VARCHAR(10),
    customer_name        VARCHAR(100),
    age                  INTEGER,
    gender               VARCHAR(20),
    city                 VARCHAR(50),
    state                VARCHAR(50),
    phone_number         VARCHAR(15),
    email                VARCHAR(100),
    registration_date    TEXT,
    language_preference  VARCHAR(30),
    primary_device       VARCHAR(30)
);

-- Now import the dirty CSV — it will work perfectly
COPY staging_customers FROM 'D:\Downloads\claude P1 data\dim_customers.csv' CSV HEADER;

-- Verify total rows including duplicates
SELECT * FROM staging_customers;

SELECT DISTINCT * FROM staging_customers;

SELECT customer_id, COUNT(*)
FROM staging_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;
-- Expected: 3030 (3000 unique + 30 duplicates)

CREATE TABLE dim_customers (
    customer_id          VARCHAR(10)  PRIMARY KEY,
    customer_name        VARCHAR(100),
    age                  INTEGER,
    gender               VARCHAR(20),
    city                 VARCHAR(50),
    state                VARCHAR(50),
    phone_number         VARCHAR(15),
    email                VARCHAR(100),
    registration_date    TEXT,
    language_preference  VARCHAR(30),
    primary_device       VARCHAR(30)
);

-- WHAT THIS DOES:
-- ROW_NUMBER() assigns a number to each row
-- PARTITION BY customer_id = restart count for each customer_id
-- ORDER BY customer_id = consistent ordering
-- So first occurrence gets row_num = 1, duplicate gets row_num = 2
-- We only INSERT rows where row_num = 1 (first occurrence only)

INSERT INTO dim_customers
SELECT
    customer_id,
    customer_name,
    age,
    gender,
    city,
    state,
    phone_number,
    email,
    registration_date,
    language_preference,
    primary_device
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY customer_id
        ) AS row_num
    FROM staging_customers
) AS ranked
WHERE row_num = 1;

-- Verify — should be exactly 3000
SELECT * FROM dim_customers;

-- Also confirm no duplicates remain
SELECT customer_id, COUNT(*) AS occurrences
FROM dim_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;
-- Expected: 0 rows returned = perfectly clean

CREATE TABLE fact_subscriptions (
    subscription_id  VARCHAR(10)  PRIMARY KEY,
    customer_id      VARCHAR(10)  REFERENCES dim_customers(customer_id),
    plan_id          VARCHAR(10)  REFERENCES dim_plans(plan_id),
    start_date       DATE,
    end_date         DATE,
    tenure_months    INTEGER,
    renewal_count    INTEGER,
    churn_flag       INTEGER,
    churn_reason     TEXT
);

COPY fact_subscriptions FROM 'D:\Downloads\claude P1 data\fact_subscriptions.csv' CSV HEADER;

-- Verify
SELECT * FROM fact_subscriptions;

CREATE TABLE fact_usage (
    usage_id                  VARCHAR(10)   PRIMARY KEY,
    customer_id               VARCHAR(10)   REFERENCES dim_customers(customer_id),
    subscription_id           VARCHAR(10)   REFERENCES fact_subscriptions(subscription_id),
    avg_watch_hours_per_day   NUMERIC(5,2),
    sessions_per_week         INTEGER,
    last_login_days_ago       INTEGER,
    content_type_preference   VARCHAR(50),
    completion_rate_pct       NUMERIC(5,2),
    peak_usage_time           VARCHAR(20)
);

COPY fact_usage FROM 'D:\Downloads\claude P1 data\fact_usage.csv' CSV HEADER;

-- Verify
SELECT * FROM fact_usage;

CREATE TABLE fact_payments (
    payment_id       VARCHAR(15)  PRIMARY KEY,
    customer_id      VARCHAR(10)  REFERENCES dim_customers(customer_id),
    subscription_id  VARCHAR(10)  REFERENCES fact_subscriptions(subscription_id),
    transaction_id   VARCHAR(15),
    payment_date     TEXT,
    amount_inr       INTEGER,
    payment_status   VARCHAR(20),
    payment_method   VARCHAR(30),
    failed_attempts  INTEGER
);

COPY fact_payments FROM 'D:\Downloads\claude P1 data\fact_payments.csv' CSV HEADER;

-- Verify
SELECT * FROM fact_payments;

-- Check all table row counts
SELECT 'dim_plans'           AS table_name, COUNT(*) AS rows FROM dim_plans
UNION ALL
SELECT 'staging_customers',    COUNT(*) FROM staging_customers
UNION ALL
SELECT 'dim_customers',        COUNT(*) FROM dim_customers
UNION ALL
SELECT 'fact_subscriptions',   COUNT(*) FROM fact_subscriptions
UNION ALL
SELECT 'fact_usage',           COUNT(*) FROM fact_usage
UNION ALL
SELECT 'fact_payments',        COUNT(*) FROM fact_payments;

-- PART 1 — dim_customers Cleaning
-- Problem 1: Empty Strings → Should be NULL

-- ── AUDIT FIRST ──────────────────────────────────────────
-- See exact counts of empty strings vs real NULLs
SELECT
    COUNT(*) FILTER (WHERE phone_number        = '') AS empty_phone,
    COUNT(*) FILTER (WHERE phone_number       IS NULL) AS null_phone,
    COUNT(*) FILTER (WHERE email               = '') AS empty_email,
    COUNT(*) FILTER (WHERE email              IS NULL) AS null_email,
    COUNT(*) FILTER (WHERE language_preference = '') AS empty_language,
    COUNT(*) FILTER (WHERE language_preference IS NULL) AS null_language
FROM dim_customers;

-- ── FIX ──────────────────────────────────────────────────
-- Convert all empty strings to proper NULL
-- NULLIF(value, '') means: if value = '' return NULL, else return value

UPDATE dim_customers
SET
    phone_number        = NULLIF(phone_number, ''),
    email               = NULLIF(email, ''),
    language_preference = NULLIF(language_preference, '');

-- ── VERIFY ───────────────────────────────────────────────
-- Empty strings should now be 0, NULLs should have the counts
SELECT
    COUNT(*) FILTER (WHERE phone_number        = '') AS empty_phone,
    COUNT(*) FILTER (WHERE phone_number       IS NULL) AS null_phone,
    COUNT(*) FILTER (WHERE email               = '') AS empty_email,
    COUNT(*) FILTER (WHERE email              IS NULL) AS null_email,
    COUNT(*) FILTER (WHERE language_preference = '') AS empty_language,
    COUNT(*) FILTER (WHERE language_preference IS NULL) AS null_language
FROM dim_customers;
-- Expected: all empty_ columns = 0, null_ columns have counts	

-- Problem 2: Invalid Ages (0 and 999)
-- ── AUDIT ────────────────────────────────────────────────
SELECT
    age,
    COUNT(*) AS count
FROM dim_customers
WHERE age NOT BETWEEN 18 AND 100
GROUP BY age
ORDER BY age;

-- ── FIX ──────────────────────────────────────────────────
-- Set invalid ages to NULL
-- We keep the row — customer is real, just age is unknown
UPDATE dim_customers
SET age = NULL
WHERE age NOT BETWEEN 18 AND 100;

-- ── VERIFY ───────────────────────────────────────────────
-- No ages should exist outside 18-100 now
SELECT
    MIN(age)                                    AS min_age,
    MAX(age)                                    AS max_age,
    ROUND(AVG(age), 1)                          AS avg_age,
    COUNT(*) FILTER (WHERE age IS NULL)         AS null_ages,
    COUNT(*) FILTER (WHERE age NOT BETWEEN 18 AND 100
                     AND age IS NOT NULL)       AS still_invalid
FROM dim_customers;
-- Expected: still_invalid = 0

--Problem 3: Dirty City Spellings
-- ── AUDIT ────────────────────────────────────────────────
-- See all unique city values to spot dirty ones
SELECT
    city,
    COUNT(*) AS customer_count
FROM dim_customers
GROUP BY city
ORDER BY city;
-- Look for: Mumbay, Bangalore, Calcutta, Madras

-- ── FIX ──────────────────────────────────────────────────
-- Standardize all city names to official names
-- CASE WHEN is like Excel IF — checks condition, returns value

UPDATE dim_customers
SET city = CASE
    WHEN city = 'Mumbay'    THEN 'Mumbai'
    WHEN city = 'Bangalore' THEN 'Bengaluru'
    WHEN city = 'Calcutta'  THEN 'Kolkata'
    WHEN city = 'Madras'    THEN 'Chennai'
    ELSE city               -- keep all other cities unchanged
END
WHERE city IN ('Mumbay', 'Bangalore', 'Calcutta', 'Madras');


-- ── VERIFY ───────────────────────────────────────────────
-- Dirty names should no longer exist
SELECT city, COUNT(*) AS count
FROM dim_customers
WHERE city IN ('Mumbay', 'Bangalore', 'Calcutta', 'Madras')
GROUP BY city;
-- Expected: 0 rows returned

-- Also verify correct cities have the counts now
SELECT city, COUNT(*) AS count
FROM dim_customers
WHERE city IN ('Mumbai', 'Bengaluru', 'Kolkata', 'Chennai')
GROUP BY city
ORDER BY city;

--Problem 4: Fix Wrong Date Format + Convert to DATE
-- ── AUDIT ────────────────────────────────────────────────
-- DD-MM-YYYY has 2-digit day at start (positions 1-2 are digits,
-- position 3 is hyphen, and year is at the end in positions 7-10)
SELECT
    COUNT(*) FILTER (
        WHERE registration_date ~ '^\d{2}-\d{2}-\d{4}$'
    ) AS wrong_format_count,
    COUNT(*) FILTER (
        WHERE registration_date ~ '^\d{4}-\d{2}-\d{2}$'
    ) AS correct_format_count
FROM dim_customers;

-- Preview some wrong format rows
SELECT customer_id, registration_date
FROM dim_customers
WHERE registration_date ~ '^\d{2}-\d{2}-\d{4}$'
LIMIT 10;

-- ── FIX STEP 1: Standardize format in TEXT column first ──
-- For DD-MM-YYYY rows: split by '-', rearrange to YYYY-MM-DD
-- SPLIT_PART(string, delimiter, position) splits text by delimiter

UPDATE dim_customers
SET registration_date =
    SPLIT_PART(registration_date, '-', 3) || '-' ||   -- YYYY
    SPLIT_PART(registration_date, '-', 2) || '-' ||   -- MM
    SPLIT_PART(registration_date, '-', 1)             -- DD
WHERE registration_date ~ '^\d{2}-\d{2}-\d{4}$';

-- ── FIX STEP 2: Verify format is uniform before converting ──
SELECT
    COUNT(*) FILTER (
        WHERE registration_date ~ '^\d{2}-\d{2}-\d{4}$'
    ) AS still_wrong_format
FROM dim_customers;
-- Expected: 0

-- ── FIX STEP 3: Convert TEXT column to proper DATE type ──
ALTER TABLE dim_customers
ALTER COLUMN registration_date
TYPE DATE
USING registration_date::DATE;

-- ── VERIFY ───────────────────────────────────────────────
SELECT
    MIN(registration_date) AS earliest_registration,
    MAX(registration_date) AS latest_registration,
    COUNT(*) FILTER (WHERE registration_date IS NULL) AS null_dates
FROM dim_customers;
-- Expected: dates fall between 2023-01-01 and 2024-11-01 approx

-- PART 2 — fact_subscriptions Cleaning
-- Problem 5: Missing Churn Reasons
-- ── AUDIT ────────────────────────────────────────────────
SELECT
    churn_flag,
    COUNT(*)                                          AS total,
    COUNT(*) FILTER (WHERE churn_reason = '')         AS empty_reason,
    COUNT(*) FILTER (WHERE churn_reason IS NULL)      AS null_reason
FROM fact_subscriptions
GROUP BY churn_flag;

-- ── FIX ──────────────────────────────────────────────────
-- Step 1: Convert empty string to NULL first
UPDATE fact_subscriptions
SET churn_reason = NULLIF(churn_reason, '');

-- Step 2: Fill NULLs in churned rows with 'Unknown'
-- We only fill WHERE churn_flag = 1
-- Active customers (churn_flag = 0) should have NULL churn_reason — that's correct

UPDATE fact_subscriptions
SET churn_reason = 'Unknown / Not Captured'
WHERE churn_flag = 1
  AND churn_reason IS NULL;

-- ── VERIFY ───────────────────────────────────────────────
-- All churned rows should now have a churn reason
SELECT
    COUNT(*) FILTER (WHERE churn_flag = 1 AND churn_reason IS NULL) AS churned_missing_reason,
    COUNT(*) FILTER (WHERE churn_flag = 0 AND churn_reason IS NULL) AS active_null_reason
FROM fact_subscriptions;
-- Expected: churned_missing_reason = 0
-- active_null_reason will have count — that is CORRECT behavior

-- Churn reason distribution
SELECT churn_reason, COUNT(*) AS count
FROM fact_subscriptions
WHERE churn_flag = 1
GROUP BY churn_reason
ORDER BY count DESC;

-- PART 3 — fact_usage Cleaning
-- Problem 6: Negative Watch Hours
-- ── AUDIT ────────────────────────────────────────────────
SELECT
    COUNT(*) FILTER (WHERE avg_watch_hours_per_day < 0)  AS negative_watch_hours,
    MIN(avg_watch_hours_per_day)                          AS minimum_value,
    MAX(avg_watch_hours_per_day)                          AS maximum_value,
    ROUND(AVG(avg_watch_hours_per_day), 2)                AS current_avg
FROM fact_usage;

-- ── FIX ──────────────────────────────────────────────────
UPDATE fact_usage
SET avg_watch_hours_per_day = NULL
WHERE avg_watch_hours_per_day < 0;

-- ── VERIFY ───────────────────────────────────────────────
SELECT
    COUNT(*) FILTER (WHERE avg_watch_hours_per_day < 0)  AS negative_watch_hours,
    MIN(avg_watch_hours_per_day)                          AS minimum_value,
    ROUND(AVG(avg_watch_hours_per_day), 2)                AS avg_after_clean
FROM fact_usage;
-- Expected: negative_watch_hours = 0, minimum_value >= 0

-- ── AUDIT + VERIFY: sessions and completion rate NULLs ───
-- These came in as NULL directly (numeric columns) — just confirm counts
SELECT
    COUNT(*) FILTER (WHERE sessions_per_week    IS NULL) AS null_sessions,
    COUNT(*) FILTER (WHERE completion_rate_pct  IS NULL) AS null_completion
FROM fact_usage;

-- PART 4 — fact_payments Cleaning
-- Problem 7: Fix Wrong Date Format
-- ── AUDIT ────────────────────────────────────────────────
SELECT
    COUNT(*) FILTER (
        WHERE payment_date ~ '^\d{2}/\d{2}/\d{4}$'
    ) AS wrong_format_slash,
    COUNT(*) FILTER (
        WHERE payment_date ~ '^\d{4}-\d{2}-\d{2}$'
    ) AS correct_format
FROM fact_payments;

-- ── FIX STEP 1: Convert DD/MM/YYYY → YYYY-MM-DD ──────────
-- SPLIT_PART with '/' as delimiter this time

UPDATE fact_payments
SET payment_date =
    SPLIT_PART(payment_date, '/', 3) || '-' ||   -- YYYY
    SPLIT_PART(payment_date, '/', 2) || '-' ||   -- MM
    SPLIT_PART(payment_date, '/', 1)             -- DD
WHERE payment_date ~ '^\d{2}/\d{2}/\d{4}$';

-- ── FIX STEP 2: Convert TEXT column to DATE ───────────────
ALTER TABLE fact_payments
ALTER COLUMN payment_date
TYPE DATE
USING payment_date::DATE;

-- ── VERIFY ───────────────────────────────────────────────
SELECT
    MIN(payment_date) AS earliest_payment,
    MAX(payment_date) AS latest_payment,
    COUNT(*) FILTER (WHERE payment_date IS NULL) AS null_dates
FROM fact_payments;

--Problem 8: NULL Payment Methods
-- ── AUDIT ────────────────────────────────────────────────
SELECT
    payment_method,
    COUNT(*) AS count
FROM fact_payments
GROUP BY payment_method
ORDER BY count DESC;
-- You will see a blank/NULL row in results

-- ── FIX ──────────────────────────────────────────────────
-- Step 1: Empty string to NULL
UPDATE fact_payments
SET payment_method = NULLIF(payment_method, '');

-- Step 2: Fill with 'Unknown'
UPDATE fact_payments
SET payment_method = 'Unknown'
WHERE payment_method IS NULL;

--Problem 9: Flag Amount Mismatches
-- ── AUDIT ────────────────────────────────────────────────
-- Join payments to subscriptions to plans to compare amounts
SELECT
    fp.payment_id,
    fp.subscription_id,
    dp.plan_name,
    dp.price_inr                AS expected_amount,
    fp.amount_inr               AS actual_amount,
    fp.amount_inr - dp.price_inr AS difference
FROM fact_payments fp
JOIN fact_subscriptions fs ON fp.subscription_id = fs.subscription_id
JOIN dim_plans dp          ON fs.plan_id = dp.plan_id
WHERE fp.amount_inr <> dp.price_inr
ORDER BY ABS(fp.amount_inr - dp.price_inr) DESC
LIMIT 20;

-- Count total mismatches
SELECT COUNT(*) AS total_mismatches
FROM fact_payments fp
JOIN fact_subscriptions fs ON fp.subscription_id = fs.subscription_id
JOIN dim_plans dp          ON fs.plan_id = dp.plan_id
WHERE fp.amount_inr <> dp.price_inr;

-- ── FIX: Add a flag column — don't change financial data ─
ALTER TABLE fact_payments
ADD COLUMN amount_mismatch_flag VARCHAR(5) DEFAULT 'No';

UPDATE fact_payments fp
SET amount_mismatch_flag = 'Yes'
FROM fact_subscriptions fs
JOIN dim_plans dp ON fs.plan_id = dp.plan_id
WHERE fp.subscription_id = fs.subscription_id
  AND fp.amount_inr <> dp.price_inr;

-- ── VERIFY ───────────────────────────────────────────────
SELECT
    amount_mismatch_flag,
    COUNT(*) AS count
FROM fact_payments
GROUP BY amount_mismatch_flag; 

--Final Step — Full Cleaning Verification
-- ══════════════════════════════════════════════════════
-- FINAL DATA QUALITY REPORT — Post Cleaning
-- StreamBharat OTT Churn Project
-- ══════════════════════════════════════════════════════

SELECT 'dim_customers' AS table_name,
    COUNT(*)                                                AS total_rows,
    COUNT(*) FILTER (WHERE phone_number IS NULL)            AS null_phones,
    COUNT(*) FILTER (WHERE email IS NULL)                   AS null_emails,
    COUNT(*) FILTER (WHERE language_preference IS NULL)     AS null_language,
    COUNT(*) FILTER (WHERE age IS NULL)                     AS null_ages,
    COUNT(*) FILTER (WHERE city IN
        ('Mumbay','Bangalore','Calcutta','Madras'))          AS dirty_cities_remaining
FROM dim_customers
UNION ALL
SELECT 'fact_subscriptions',
    COUNT(*),
    COUNT(*) FILTER (WHERE churn_flag=1 AND churn_reason IS NULL),
    0, 0, 0, 0
FROM fact_subscriptions
UNION ALL
SELECT 'fact_usage',
    COUNT(*),
    COUNT(*) FILTER (WHERE avg_watch_hours_per_day < 0),
    0, 0, 0, 0
FROM fact_usage
UNION ALL
SELECT 'fact_payments',
    COUNT(*),
    COUNT(*) FILTER (WHERE payment_method = 'Unknown'),
    COUNT(*) FILTER (WHERE amount_mismatch_flag = 'Yes'),
    0, 0, 0
FROM fact_payments;

