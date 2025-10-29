# PAX Configuration Safety Guide

**⚠️  CRITICAL: Read this before deploying PAX in production**

PAX storage provides significant benefits when configured correctly, but **catastrophic performance degradation** when configured incorrectly. This guide documents critical pitfalls, validation procedures, and recovery strategies.

---

## Table of Contents

1. [Critical Pitfalls](#critical-pitfalls)
2. [Pre-Deployment Validation Checklist](#pre-deployment-validation-checklist)
3. [Red Flags: Detecting Misconfiguration in Production](#red-flags-detecting-misconfiguration-in-production)
4. [Recovery Procedures](#recovery-procedures)
5. [Case Studies](#case-studies)
6. [Safe Configuration Templates](#safe-configuration-templates)

---

## Critical Pitfalls

### 🔴 Pitfall #1: Bloom Filters on Low-Cardinality Columns (MOST DANGEROUS)

**Severity:** CRITICAL - Causes 80%+ storage bloat, 50x+ memory overhead

#### The Problem

Bloom filters are designed for **high-cardinality columns** (>1000 distinct values). Using them on low-cardinality columns causes:
- Massive storage overhead (bloom filter data stored per file)
- Excessive memory consumption during queries
- Destroyed compression ratios
- Slower query performance

#### Real-World Impact (Case Study: October 2025)

```sql
-- BAD CONFIGURATION (caused 81% storage bloat)
CREATE TABLE sales_fact (...) USING pax WITH (
    bloomfilter_columns='transaction_hash,customer_id,product_id'
    -- transaction_hash: n_distinct=-1 (constant value) ❌
    -- customer_id: n_distinct=-0.46 (very low cardinality) ❌
    -- product_id: 99,671 (high cardinality) ✅
);
```

**Result:**
| Metric | Expected | Actual | Disaster |
|--------|----------|--------|----------|
| Storage | 750 MB | 1,350 MB | +80% bloat |
| Memory | 600 KB | 8,683 KB | +1,347% overhead |
| Compression | 8.2x | 1.85x | -78% efficiency |
| Query time | Faster | 2-3x slower | -60% performance |

**Cost:** 408 MB wasted per 10M rows = **~40 GB per 1B rows**

#### How to Avoid

**Step 1: Check cardinality of ALL columns BEFORE configuration**

```sql
-- Run this query on your table
SELECT
    attname AS column_name,
    n_distinct,
    CASE
        WHEN ABS(n_distinct) > 1000 THEN '✅ GOOD for bloom filter'
        WHEN ABS(n_distinct) > 100 THEN '🟠 BORDERLINE - use minmax instead'
        ELSE '❌ BAD for bloom filter - will cause bloat'
    END AS bloom_suitability,
    CASE
        WHEN ABS(n_distinct) < 0 THEN 'Negative = % of total rows'
        ELSE 'Positive = estimated distinct count'
    END AS note
FROM pg_stats
WHERE schemaname = 'your_schema'
  AND tablename = 'your_table'
ORDER BY ABS(n_distinct) DESC;
```

**Step 2: Only add columns with n_distinct > 1000**

```sql
-- GOOD CONFIGURATION (optimized)
CREATE TABLE sales_fact (...) USING pax WITH (
    bloomfilter_columns='product_id',  -- Only high-cardinality
    minmax_columns='transaction_hash,customer_id,region,status'  -- Low-cardinality here
);
```

#### Warning Signs in Production

- Table size 2x+ larger than AOCO equivalent
- Query memory usage >5 MB per query
- Compression ratio < 3x
- `pg_total_relation_size()` grows unexpectedly after CLUSTER

---

### 🟠 Pitfall #2: Insufficient maintenance_work_mem During Clustering

**Severity:** HIGH - Causes 2-3x storage bloat, data duplication

#### The Problem

Z-order clustering loads the entire table into memory for sorting. If `maintenance_work_mem` is too low:
- Clustering spills to disk
- Creates temporary duplicate data
- Results in 2-3x storage bloat
- Data cannot be properly sorted

#### Real-World Impact

```sql
-- DEFAULT (causes bloat)
maintenance_work_mem = 64 MB  -- Default PostgreSQL setting

-- Clustering 10M rows with 64MB memory
CLUSTER sales_fact_pax;
-- Result: 1,500-2,000 MB (2-2.7x bloat)
```

**Expected:** 745 MB → 780 MB (5% growth)
**Actual:** 745 MB → 2,000 MB (168% growth)

#### How to Avoid

**Calculate required memory:**

```
Formula: (rows × avg_row_bytes × 2) / 1MB

For 10M rows × 600 bytes:
= (10,000,000 × 600 × 2) / 1,048,576
= ~11.4 GB ideal
= 2 GB safe minimum
```

**Set before clustering:**

```sql
-- For 10M rows
SET maintenance_work_mem = '2GB';
CLUSTER sales_fact_pax;

-- For 50M rows
SET maintenance_work_mem = '4GB';

-- For 200M rows
SET maintenance_work_mem = '8GB';

-- For 1B rows
SET maintenance_work_mem = '32GB';
```

**Validation script:**

```bash
psql -f sql/04a_validate_clustering_config.sql
# Check output for memory recommendations
```

#### Warning Signs in Production

- Clustered table 2x+ larger than no-cluster variant
- Compression ratio drops after clustering
- Clustering takes 2x+ longer than expected
- Disk I/O spikes during CLUSTER operation

---

### 🟠 Pitfall #3: Clustering on Non-Correlated Columns

**Severity:** MEDIUM - Wastes storage (26%+), no performance benefit

#### The Problem

Z-order clustering only helps when columns are **queried together**. Clustering on non-correlated columns:
- Adds storage overhead (26% in our tests)
- Provides no query speedup
- Wastes maintenance_work_mem
- Requires periodic re-clustering

#### Real-World Impact

```sql
-- BAD: These columns are NEVER queried together
CREATE TABLE sales_fact (...) USING pax WITH (
    cluster_columns='sale_date,product_id'  -- Different access patterns
);
```

**Queries that DON'T benefit:**
```sql
-- Query 1: Only uses sale_date
SELECT * FROM sales_fact WHERE sale_date = '2023-01-01';

-- Query 2: Only uses product_id
SELECT * FROM sales_fact WHERE product_id = 12345;

-- No queries use BOTH → clustering wasted 26% storage
```

#### How to Avoid

**Step 1: Analyze your query workload**

```sql
-- Identify columns that appear together in WHERE clauses
-- Example query log analysis:
SELECT
    query,
    COUNT(*) as frequency
FROM pg_stat_statements
WHERE query LIKE '%WHERE%'
  AND query LIKE '%AND%'  -- Multi-column filters
GROUP BY query
ORDER BY frequency DESC
LIMIT 20;
```

**Step 2: Look for correlation patterns**

Common correlated dimensions:
- ✅ `date + region` (time-series analysis by region)
- ✅ `customer_id + order_date` (customer history)
- ✅ `product_category + brand` (product browsing)
- ❌ `date + random_id` (no correlation)
- ❌ `status + unrelated_field` (different access patterns)

**Step 3: Configure clustering conservatively**

```sql
-- GOOD: Only if queries use both columns frequently
CREATE TABLE sales_fact (...) USING pax WITH (
    cluster_columns='sale_date,region',  -- 50%+ of queries use both
    cluster_type='zorder'
);

-- BETTER: Skip clustering if unsure
CREATE TABLE sales_fact (...) USING pax WITH (
    -- No clustering configured
    -- Still get minmax and bloom filter benefits
);
```

#### Warning Signs in Production

- Clustered table 20%+ larger than no-cluster
- EXPLAIN ANALYZE shows high "Rows Removed by Filter"
- No queries use all clustered columns together
- Clustering takes hours but provides no speedup

---

## Pre-Deployment Validation Checklist

Use this checklist **before deploying ANY PAX table to production**.

### ☑️ Phase 1: Column Analysis (15 minutes)

```bash
# 1. Generate sample data (1-10M rows)
psql -f sql/01_setup_schema.sql
psql -f sql/02_create_variants.sql
psql -f sql/03_generate_data_SMALL.sql

# 2. Analyze statistics
ANALYZE your_table_name;

# 3. Inspect cardinality
psql -f sql/07_inspect_pax_internals.sql
```

**Validate:**
- [ ] All `bloomfilter_columns` have n_distinct > 1000
- [ ] All low-cardinality columns (<100) are in `minmax_columns` only
- [ ] No overlap between bloomfilter and minmax columns

### ☑️ Phase 2: Configuration Review (10 minutes)

```sql
-- Review PAX reloptions
SELECT
    relname,
    unnest(reloptions) AS option
FROM pg_class
WHERE relname = 'your_table_name';
```

**Validate:**
- [ ] `bloomfilter_columns`: Only high-cardinality (1-3 columns max)
- [ ] `minmax_columns`: All filterable columns (6-12 columns)
- [ ] `cluster_columns`: Only correlated dimensions (2-3 max)
- [ ] `compresstype='zstd'` and `compresslevel=5` (default)
- [ ] `storage_format='porc'`

### ☑️ Phase 3: Memory Calculation (5 minutes)

```bash
# Run validation script
psql -f sql/04a_validate_clustering_config.sql
```

**Validate:**
- [ ] Recommended maintenance_work_mem calculated
- [ ] Sufficient disk space (2x table size)
- [ ] No warnings about insufficient memory

### ☑️ Phase 4: Test Clustering (30 minutes)

```sql
-- Set memory
SET maintenance_work_mem = '<recommended_value>';

-- Cluster
CLUSTER your_table_name;

-- Check results
SELECT
    pg_size_pretty(pg_total_relation_size('your_table_name')) AS clustered_size;
```

**Validate:**
- [ ] Clustered size < 110% of no-cluster size
- [ ] Compression ratio > 5x
- [ ] Clustering completed without disk spills

### ☑️ Phase 5: Performance Testing (30 minutes)

```bash
# Run benchmark queries
psql -f sql/05_test_sample_queries.sql
```

**Validate:**
- [ ] Queries on clustered columns are faster
- [ ] Memory usage < 5 MB per query
- [ ] No "Rows Removed by Filter" > 50% of total
- [ ] Query times competitive with AOCO

### ☑️ Phase 6: Production Deployment

**Only proceed if ALL validations passed.**

```sql
-- Create production table with validated configuration
CREATE TABLE prod_table (...) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,
    minmax_columns='<validated_list>',
    bloomfilter_columns='<validated_list>',  -- High-cardinality only
    cluster_columns='<validated_list>',      -- Optional
    cluster_type='zorder',
    storage_format='porc'
);

-- Set memory
SET maintenance_work_mem = '<calculated_value>';

-- Load data
INSERT INTO prod_table SELECT * FROM source_table;

-- Cluster (if configured)
CLUSTER prod_table;

-- Analyze
ANALYZE prod_table;
```

---

## Red Flags: Detecting Misconfiguration in Production

### 🚨 Immediate Red Flags (Check Daily)

```sql
-- 1. Check storage bloat
SELECT
    relname,
    pg_size_pretty(pg_total_relation_size(oid)) AS total_size,
    ROUND(pg_total_relation_size(oid)::numeric / reltuples / 100) AS bytes_per_100_rows
FROM pg_class
WHERE relam = (SELECT oid FROM pg_am WHERE amname = 'pax')
  AND relkind = 'r'
ORDER BY pg_total_relation_size(oid) DESC;

-- RED FLAG: bytes_per_100_rows > 100KB
-- Expected: 30-80KB for typical tables
```

```sql
-- 2. Check query memory usage
SELECT
    query,
    calls,
    mean_exec_time,
    max_exec_time,
    shared_blks_hit,
    shared_blks_read,
    temp_blks_written  -- RED FLAG: Should be 0
FROM pg_stat_statements
WHERE query LIKE '%pax_table_name%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

```sql
-- 3. Check compression ratio
WITH table_stats AS (
    SELECT
        relname,
        pg_total_relation_size(oid) AS compressed_size,
        reltuples * 600 AS estimated_uncompressed  -- Adjust 600 to your avg row size
    FROM pg_class
    WHERE relname = 'your_pax_table'
)
SELECT
    relname,
    pg_size_pretty(compressed_size) AS compressed,
    pg_size_pretty(estimated_uncompressed::bigint) AS uncompressed_est,
    ROUND(estimated_uncompressed / compressed_size, 2) AS compression_ratio
FROM table_stats;

-- RED FLAG: compression_ratio < 3.0
-- Expected: 5-10x for typical PAX tables
```

### 🔍 Deeper Investigation (Weekly)

```sql
-- 4. Analyze bloom filter effectiveness
SELECT
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE tablename = 'your_pax_table'
  AND attname IN (
      -- List your bloomfilter_columns here
      SELECT unnest(string_to_array(
          regexp_replace(
              (SELECT unnest(reloptions)
               FROM pg_class
               WHERE relname = 'your_pax_table'
               AND unnest(reloptions) LIKE 'bloomfilter_columns=%'),
              'bloomfilter_columns=', ''),
          ','))
  );

-- RED FLAG: Any column with ABS(n_distinct) < 1000
```

```sql
-- 5. Check clustering effectiveness
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM your_pax_table
WHERE cluster_col1 = 'value1'
  AND cluster_col2 = 'value2';

-- RED FLAG: "Rows Removed by Filter" > 50% of Seq Scan rows
-- Indicates clustering not helping
```

### 📊 Performance Baselines

Establish baselines after initial deployment:

```sql
-- Create baseline tracking table
CREATE TABLE pax_performance_baseline (
    table_name TEXT,
    measurement_date DATE,
    total_size_mb BIGINT,
    compression_ratio NUMERIC,
    avg_query_time_ms NUMERIC,
    max_memory_mb NUMERIC,
    PRIMARY KEY (table_name, measurement_date)
);

-- Record baseline
INSERT INTO pax_performance_baseline
SELECT
    'your_pax_table',
    CURRENT_DATE,
    pg_total_relation_size('your_pax_table') / 1024 / 1024,
    -- Add other metrics
    ...;
```

**Alert thresholds:**
- Storage growth > 10% week-over-week
- Compression ratio drop > 20%
- Query time increase > 50%
- Memory usage spike > 3x baseline

---

## Recovery Procedures

### Scenario 1: Bloom Filter Misconfiguration Detected

**Symptoms:** 80%+ storage bloat, high memory usage, compression < 2x

**Recovery Steps:**

```sql
-- 1. Identify misconfigured columns
psql -f sql/07_inspect_pax_internals.sql

-- 2. Create corrected table definition
CREATE TABLE your_table_fixed (LIKE your_table_broken)
USING pax WITH (
    compresstype='zstd',
    compresslevel=5,
    minmax_columns='<same as before>',
    bloomfilter_columns='<ONLY high-cardinality>',  -- Fixed
    cluster_columns='<same as before>',
    cluster_type='zorder',
    storage_format='porc'
);

-- 3. Copy data (no clustering yet)
INSERT INTO your_table_fixed SELECT * FROM your_table_broken;

-- 4. Compare sizes
SELECT
    'broken' AS version,
    pg_size_pretty(pg_total_relation_size('your_table_broken')) AS size
UNION ALL
SELECT
    'fixed' AS version,
    pg_size_pretty(pg_total_relation_size('your_table_fixed')) AS size;

-- 5. If size improved, proceed with clustering
SET maintenance_work_mem = '<calculated_value>';
CLUSTER your_table_fixed;

-- 6. Swap tables (in transaction)
BEGIN;
ALTER TABLE your_table_broken RENAME TO your_table_old;
ALTER TABLE your_table_fixed RENAME TO your_table_broken;
DROP TABLE your_table_old;  -- Only after validation
COMMIT;
```

**Downtime:** ~30-60 minutes for 100M rows

**Alternative (Zero Downtime):**
- Use partitioned tables
- Migrate one partition at a time
- Swap partitions when validated

---

### Scenario 2: Low maintenance_work_mem Bloat

**Symptoms:** 2-3x storage after clustering, normal memory usage

**Recovery Steps:**

```sql
-- 1. Drop clustered table and recreate from source
DROP TABLE your_table_pax;

CREATE TABLE your_table_pax (LIKE your_table_source)
USING pax WITH (
    -- Same configuration as before
    ...
);

-- 2. Load data
INSERT INTO your_table_pax SELECT * FROM your_table_source;

-- 3. Set HIGHER maintenance_work_mem
SET maintenance_work_mem = '8GB';  -- Increase from previous 2GB

-- 4. Cluster with sufficient memory
CLUSTER your_table_pax;

-- 5. Verify size
SELECT pg_size_pretty(pg_total_relation_size('your_table_pax'));
```

**Downtime:** ~60-120 minutes for 100M rows

---

### Scenario 3: Clustering Provides No Benefit

**Symptoms:** 26%+ storage overhead, no query speedup

**Recovery Steps:**

```sql
-- Option 1: Drop clustering, keep other PAX features
CREATE TABLE your_table_no_cluster (LIKE your_table_clustered)
USING pax WITH (
    compresstype='zstd',
    compresslevel=5,
    minmax_columns='<same>',
    bloomfilter_columns='<same>',
    -- NO cluster_columns
    storage_format='porc'
);

-- Load data
INSERT INTO your_table_no_cluster SELECT * FROM your_table_source;

-- Compare performance
psql -f sql/05_test_sample_queries.sql
```

**Storage savings:** -20-30% (no clustering overhead)

**Option 2: Revert to AOCO**

If PAX provides no benefits:
```sql
CREATE TABLE your_table_aoco (LIKE your_table_source)
WITH (appendoptimized=true, orientation=column, compresstype=zstd);

INSERT INTO your_table_aoco SELECT * FROM your_table_source;
```

---

### Scenario 4: Emergency Rollback to AOCO

**When to use:** Production outage, cannot fix PAX config quickly

```sql
-- 1. Create AOCO copy (parallel to PAX)
CREATE TABLE your_table_aoco_backup (LIKE your_table_pax)
WITH (appendoptimized=true, orientation=column, compresstype=zstd)
DISTRIBUTED BY (same_as_pax);

-- 2. Copy data
INSERT INTO your_table_aoco_backup SELECT * FROM your_table_pax;

-- 3. Analyze
ANALYZE your_table_aoco_backup;

-- 4. Quick validation
SELECT COUNT(*), SUM(key_column) FROM your_table_aoco_backup;
SELECT COUNT(*), SUM(key_column) FROM your_table_pax;
-- Ensure results match

-- 5. Atomic swap (requires exclusive lock)
BEGIN;
ALTER TABLE your_table_pax RENAME TO your_table_pax_broken;
ALTER TABLE your_table_aoco_backup RENAME TO your_table_pax;
COMMIT;
```

**Downtime:** 5-15 minutes (exclusive lock duration)

**Note:** AOCO provides stable baseline performance while you fix PAX configuration offline.

---

## Case Studies

### Case Study 1: The 81% Storage Bloat (October 2025)

**Background:**
- Table: 10M rows, 25 columns
- Initial configuration: 3 bloom filter columns

**Misconfiguration:**
```sql
bloomfilter_columns='transaction_hash,customer_id,product_id'
```

**Actual cardinality:**
- `transaction_hash`: n_distinct = -1 (constant/very low)
- `customer_id`: n_distinct = -0.46 (very low)
- `product_id`: 99,671 (high - appropriate)

**Impact:**
- Storage: 745 MB → 1,350 MB (+81%)
- Memory: 159 KB → 8,683 KB (+5,360%)
- Compression: 3.36x → 1.85x (-45%)
- Query performance: 2-3x slower than AOCO

**Root Cause:**
Assumed `customer_id` had high cardinality without validation. In reality, synthetic data generation produced low cardinality.

**Fix:**
```sql
bloomfilter_columns='product_id'  -- Only high-cardinality
```

**After Fix:**
- Storage: 1,350 MB → 942 MB (-30%, -408 MB saved)
- Memory: 8,683 KB → 2,982 KB (-66%)
- Compression: 1.85x → 6.52x (+252%)
- Query performance: Tied to 1.4x faster than AOCO

**Lesson:** **NEVER assume cardinality. ALWAYS validate with pg_stats.**

**Detection Time:** 3 hours (during benchmark analysis)
**Fix Time:** 5 minutes (config change)
**Retest Time:** 10 minutes (10M row test)

---

### Case Study 2: The Silent Memory Leak (Hypothetical)

**Background:**
- Table: 500M rows, deployed to production
- Queries started consuming excessive memory after 2 weeks

**Symptoms:**
- Query memory usage: 45 MB per query (was 2 MB initially)
- Out of memory errors on complex queries
- Connection pooler running out of connections

**Investigation:**
```sql
-- Check bloom filter columns
SELECT unnest(reloptions)
FROM pg_class
WHERE relname = 'problem_table'
  AND unnest(reloptions) LIKE 'bloom%';

-- Result: bloomfilter_columns='status,type,category'

-- Check cardinality
SELECT attname, n_distinct FROM pg_stats
WHERE tablename = 'problem_table'
  AND attname IN ('status', 'type', 'category');

-- Results:
-- status: n_distinct = 8
-- type: n_distinct = 12
-- category: n_distinct = 45
```

**Root Cause:**
All 3 bloom filter columns had very low cardinality (<100), but:
- Initial data had only 3 status values
- Over time, data diversity didn't increase
- Bloom filters became pure overhead

**Fix:**
Recreated table without bloom filters (all moved to minmax).

**Impact After Fix:**
- Memory: 45 MB → 1.8 MB per query (-96%)
- Storage: -18% (bloom filter overhead removed)
- Query time: -12% (less memory thrashing)

**Lesson:** **Cardinality can change over time. Monitor in production.**

---

### Case Study 3: The Clustering Misalignment (Hypothetical)

**Background:**
- Table: 1B rows, 200 GB
- Configured: `cluster_columns='date,customer_id'`
- Storage: 265 GB (+33% vs no-cluster)

**Analysis:**
```sql
-- Check query patterns
SELECT query, calls
FROM pg_stat_statements
WHERE query LIKE '%your_table%'
ORDER BY calls DESC
LIMIT 20;
```

**Finding:**
- 80% of queries: `WHERE date = X` (single column)
- 15% of queries: `WHERE customer_id = Y` (single column)
- 5% of queries: `WHERE date = X AND customer_id = Y` (both columns)

**Root Cause:**
Clustering optimized for 5% of queries while adding 33% storage overhead for all queries.

**Fix:**
Removed clustering, relied on minmax statistics only.

**Impact:**
- Storage: 265 GB → 205 GB (-60 GB, -23%)
- Query performance: No degradation (minmax sufficient)
- Maintenance: No periodic re-clustering needed

**Lesson:** **Cluster only if >50% of queries use all clustered columns.**

---

## Safe Configuration Templates

### Template 1: High-Cardinality OLTP (Transactional)

**Use case:** Order tables, transaction logs, event streams

```sql
CREATE TABLE transactions (
    transaction_id BIGINT,
    timestamp TIMESTAMP,
    customer_id BIGINT,
    amount NUMERIC,
    status VARCHAR(20),
    payment_method VARCHAR(50),
    ...
) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: All filterable columns (low overhead)
    minmax_columns='timestamp,transaction_id,customer_id,amount,status',

    -- Bloom: ONLY genuinely high-cardinality
    -- Validate: n_distinct > 1000 for each
    bloomfilter_columns='transaction_id,customer_id',

    -- NO clustering (OLTP has random access patterns)

    storage_format='porc'
) DISTRIBUTED BY (transaction_id);
```

**Validation:**
```sql
-- Check cardinality
SELECT attname, n_distinct FROM pg_stats
WHERE tablename = 'transactions'
  AND attname IN ('transaction_id', 'customer_id');
-- Both should show n_distinct in millions
```

---

### Template 2: Time-Series OLAP (Analytical)

**Use case:** Metrics, logs, sensor data, events

```sql
CREATE TABLE metrics (
    measurement_time TIMESTAMP,
    sensor_id INT,
    region VARCHAR(50),
    metric_type VARCHAR(50),
    value DOUBLE PRECISION,
    ...
) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Time + all filterable dimensions
    minmax_columns='measurement_time,sensor_id,region,metric_type',

    -- Bloom: High-cardinality sensors only
    -- Validate: n_distinct(sensor_id) > 1000
    bloomfilter_columns='sensor_id',

    -- Clustering: Time + primary dimension
    cluster_columns='measurement_time,region',
    cluster_type='zorder',

    storage_format='porc'
) DISTRIBUTED BY (sensor_id);

-- Set memory before clustering
SET maintenance_work_mem = '4GB';  -- For 50M rows
CLUSTER metrics;
```

**Validation:**
```sql
-- Verify clustering helps
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM metrics
WHERE measurement_time BETWEEN '2023-01-01' AND '2023-01-31'
  AND region = 'North America';
-- Check "Rows Removed by Filter" - should be low
```

---

### Template 3: Fact Table with Dimensions (Data Warehouse)

**Use case:** Sales, orders, inventory fact tables

```sql
CREATE TABLE fact_sales (
    sale_date DATE,
    sale_timestamp TIMESTAMP,
    customer_key INT,
    product_key INT,
    store_key INT,
    quantity INT,
    amount NUMERIC,
    discount NUMERIC,
    ...
) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: All dimensions + measures
    minmax_columns='sale_date,customer_key,product_key,store_key,quantity,amount',

    -- Bloom: High-cardinality foreign keys
    -- Validate each: n_distinct > 1000
    bloomfilter_columns='customer_key,product_key',

    -- Clustering: Date + primary dimension (most common query pattern)
    cluster_columns='sale_date,customer_key',
    cluster_type='zorder',

    storage_format='porc'
) DISTRIBUTED BY (customer_key);
```

---

### Template 4: Conservative (Minimal Risk)

**Use case:** When uncertain about cardinality or query patterns

```sql
CREATE TABLE your_table (
    ...
) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: All filterable columns (safe)
    minmax_columns='col1,col2,col3,col4,col5',

    -- NO bloom filters (avoid risk)

    -- NO clustering (avoid 26% overhead)

    storage_format='porc'
) DISTRIBUTED BY (key_column);
```

**Benefits:**
- Safe baseline configuration
- 5-10x compression
- 5% storage overhead vs AOCO
- No catastrophic misconfiguration risk

**When to use:**
- Initial PAX deployment
- Unknown workload characteristics
- Storage-critical applications
- Testing/validation phase

---

## Configuration Decision Matrix

| Scenario | Bloom Filters | Clustering | Rationale |
|----------|---------------|------------|-----------|
| **Unknown cardinality** | NO | NO | Avoid risk until validated |
| **OLTP workload** | 1-2 high-card | NO | Random access, no clustering benefit |
| **OLAP time-series** | 1-2 high-card | YES (date+dim) | Sequential access, clustering helps |
| **Storage critical** | NO | NO | Minimize overhead (5% vs 33%) |
| **Query speed critical** | 2-3 high-card | YES | Maximize pruning |
| **Mixed workload** | 1 high-card | NO | Balance safety and performance |
| **First PAX deployment** | NO | NO | Establish baseline, add later |

---

## Summary

### The Golden Rules

1. **🔴 ALWAYS validate cardinality BEFORE configuring bloom filters**
   - Use `sql/07_inspect_pax_internals.sql`
   - Only use bloom filters for n_distinct > 1000
   - Low-cardinality bloom filters cause 80%+ bloat

2. **🟠 ALWAYS calculate maintenance_work_mem BEFORE clustering**
   - Use `sql/04a_validate_clustering_config.sql`
   - Formula: (rows × bytes × 2) / 1MB
   - Too low causes 2-3x bloat

3. **🟠 ONLY cluster on correlated columns**
   - Analyze query patterns first
   - Only if >50% of queries use all clustered columns
   - Otherwise waste 26% storage

4. **🟢 When in doubt, use conservative configuration**
   - Minmax only (no bloom filters)
   - No clustering
   - Still get 5-10x compression and competitive performance

### Risk Levels

| Configuration | Risk | Storage Overhead | Misconfiguration Impact |
|---------------|------|------------------|------------------------|
| MinMax only | 🟢 LOW | +5% | Minor (wasted statistics) |
| + Bloom (validated) | 🟢 LOW | +5% | N/A (validated) |
| + Bloom (unvalidated) | 🔴 CRITICAL | +80% | Catastrophic |
| + Clustering (appropriate) | 🟠 MEDIUM | +26% | Wasted storage |
| + Clustering (inappropriate) | 🟠 MEDIUM | +26% | No benefit, wasted storage |

### When PAX Is Right for You

✅ **Use PAX when:**
- You can validate configuration thoroughly
- You have time to test before production
- You can monitor performance in production
- Storage efficiency is important
- Query patterns are understood

❌ **Don't use PAX when:**
- Cannot validate cardinality
- Need immediate production deployment
- No monitoring capability
- Storage is unlimited
- AOCO already meets requirements

---

**Document Version:** 1.0
**Last Updated:** October 29, 2025
**Based on:** PAX benchmark 10M row testing and configuration analysis

**Feedback:** Report issues or suggestions at your project repository or Apache Cloudberry issues.
