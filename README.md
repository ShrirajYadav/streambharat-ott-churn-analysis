# streambharat-ott-churn-analysis
End-to-end customer churn analysis for an Indian OTT platform using SQL, Excel &amp; Power BI

# 🎬 StreamBharat OTT — Customer Churn Analysis

## 📌 Project Overview
StreamBharat is a fictional Indian OTT platform losing subscribers
at an alarming rate. This project identifies WHY customers churn,
WHICH customers are at highest risk right now, and WHAT the
retention team should do about it.

This is a complete end-to-end analytics project covering
data generation, cleaning, analysis, and dashboarding.

---

## 🎯 Business Problem
> "StreamBharat's subscriber base is declining. Leadership needs
> to understand the churn drivers and identify at-risk customers
> before revenue impact becomes irreversible."

---

## 🔧 Tools & Technologies
| Tool          | Purpose                              |
|---------------|--------------------------------------|
| Python        | Custom dataset generation            |
| PostgreSQL    | Data storage, cleaning & analysis    |
| Microsoft Excel | Business reporting & pivot analysis|
| Power BI      | Interactive dashboard                |

---

## 🗄️ Database Schema
5-table Star Schema with full referential integrity:

- dim_customers     — Customer profiles (3,000 records)
- dim_plans         — Subscription plan catalog (4 plans)
- fact_subscriptions — Subscription records + churn status
- fact_usage        — Viewing behaviour per subscription
- fact_payments     — Monthly payment records (23,000+ rows)

---

## 🧹 Data Cleaning Highlights
Real-world data quality issues solved using SQL:

| Issue                    | Records Affected | Solution              |
|--------------------------|------------------|-----------------------|
| Duplicate customer rows  | 30               | ROW_NUMBER() window   |
| Empty strings → NULL     | 352              | NULLIF()              |
| Invalid ages (0, 999)    | 54               | Conditional UPDATE    |
| Dirty city spellings     | 21               | CASE WHEN             |
| Missing churn reasons    | 122              | Labelled 'Unknown'    |
| Negative watch hours     | 112              | Set to NULL           |
| Payment amount mismatch  | 628              | Flag column added     |

---

## 📊 Key Business Findings

1. **Overall churn rate is 44%** — significantly above the
   healthy benchmark of 30% for OTT platforms

2. **Mobile plan has highest churn** vs Premium at lowest

3. **Monthly revenue lost to churn: ₹5,15,000**

4. **Top churn reason: Frequent Buffering Issue**

5. **Churned users watch fewer hours**

6. **Payment failures spike in the last 2 months**

---

## 💡 Business Recommendations

- Contact all Critical-risk customers with a personalised
  retention offer — 1 month free or plan upgrade discount
- Investigate payment failure root cause for at-risk subscribers
- Launch re-engagement campaign for users inactive 20+ days
- Add regional language content — top churn reason is poor
  regional content availability
- Build a loyalty programme for subscribers beyond 6 months
- Improve Mobile app streaming quality to reduce buffering
  complaints — the second most common churn reason

---

## 📁 Repository Structure
- /dataset    → Raw CSV files
- /sql        → All SQL scripts
- /excel      → Excel business report
- /powerbi    → Power BI dashboard file
- /screenshots → Dashboard preview images

---

## 👤 About This Project
Built by Shriraj Yadav as part of a Data & Business Analytics
portfolio. This project simulates a real analyst workflow —
from database design through to executive reporting.

🔗 LinkedIn: linkedin.com/in/shrirajyadav
📧 Contact: yadavshriraj8@gmail.com
