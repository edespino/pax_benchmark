# PAX Storage Configuration Guide

## Overview

This guide provides recommendations for configuring PAX storage for optimal performance based on the benchmark findings.

---

## Table Creation Best Practices

### Basic PAX Table

```sql
CREATE TABLE my_fact_table (...) USING pax WITH (
    -- Compression strategy
    compresstype='zstd',
    compresslevel=5,

    -- Storage format
    storage_format='porc'
)
DISTRIBUTED BY (primary_key);
```

### Advanced PAX Table with Full Optimization

```sql
CREATE TABLE optimized_fact_table (...) USING pax WITH (
    -- Compression
    compresstype='zstd',
    compresslevel=5,  -- Balance speed/ratio (1-19)

    -- Statistics for sparse filtering
    -- Choose 4-6 columns that are frequently used in WHERE clauses
    minmax_columns='date_col,amount_col,id_col,timestamp_col',

    -- Bloom filters for high-cardinality equality/IN predicates
    -- Choose categorical columns with many distinct values
    bloomfilter_columns='category,region,status,transaction_id',

    -- Z-order clustering for correlated dimensions
    -- Choose 2-3 columns that are frequently filtered together
    cluster_type='zorder',  -- or 'lexical' for simple ORDER BY
    cluster_columns='date_col,region',

    -- Storage format
    storage_format='porc'  -- Use 'porc_vec' for vectorized executor
)
DISTRIBUTED BY (id_col);
```

---

## Per-Column Encoding Strategies

### When to Use Each Encoding

| Encoding Type | Best For | Example Columns |
|---------------|----------|-----------------|
| **delta** | Sequential/monotonic values | order_id, date, timestamp, counters |
| **RLE_TYPE** | Low cardinality (<100 values) | status, priority, boolean flags, enum types |
| **zstd** (high level) | High cardinality text | descriptions, names, URLs, JSON |
| **zlib** | Alternative to zstd | Similar use case, slightly different trade-offs |
| **none** | Already compressed data | Binary blobs, pre-compressed fields |

### Example: Column-Specific Encoding

```sql
CREATE TABLE mixed_encoding (...) USING pax;

-- Sequential IDs and dates: delta encoding
ALTER TABLE mixed_encoding
    ALTER COLUMN order_id SET ENCODING (compresstype=delta);

ALTER TABLE mixed_encoding
    ALTER COLUMN sale_date SET ENCODING (compresstype=delta);

-- Low cardinality: RLE
ALTER TABLE mixed_encoding
    ALTER COLUMN status SET ENCODING (compresstype=RLE_TYPE);

ALTER TABLE mixed_encoding
    ALTER COLUMN priority SET ENCODING (compresstype=RLE_TYPE);

-- High cardinality text: aggressive ZSTD
ALTER TABLE mixed_encoding
    ALTER COLUMN description SET ENCODING (compresstype=zstd, compresslevel=9);
```

---

## GUC Parameter Tuning

### OLAP Workload (Recommended)

```sql
-- Enable sparse filtering (file pruning)
SET pax.enable_sparse_filter = on;

-- Disable row filtering (not needed for pure OLAP)
SET pax.enable_row_filter = off;

-- Optimize micro-partition sizing
SET pax.max_tuples_per_file = 1310720;    -- ~1.3M tuples
SET pax.max_size_per_file = 67108864;     -- 64MB
SET pax.max_tuples_per_group = 131072;    -- 128K tuples

-- Bloom filter memory
SET pax.bloom_filter_work_memory_bytes = 10485760;  -- 10MB

-- Buffer for scans
SET pax.scan_reuse_buffer_size = 8388608;  -- 8MB

-- Enable TOAST for large values
SET pax.enable_toast = on;
SET pax.min_size_of_compress_toast = 524288;     -- 512KB
SET pax.min_size_of_external_toast = 10485760;   -- 10MB
```

### Mixed OLAP/OLTP Workload

```sql
-- Enable both filtering strategies
SET pax.enable_sparse_filter = on;
SET pax.enable_row_filter = on;

-- Smaller micro-partitions for better concurrency
SET pax.max_tuples_per_file = 655360;     -- ~650K tuples
SET pax.max_size_per_file = 33554432;     -- 32MB
```

### Debug and Analysis

```sql
-- Enable debug output to see sparse filtering in action
SET pax.enable_debug = on;
SET pax.log_filter_tree = on;
SET client_min_messages = LOG;

-- Run query and check logs for:
-- "Sparse filter: skipped X files out of Y"
EXPLAIN ANALYZE SELECT ... WHERE date_col = '2023-01-01';
```

---

## Statistics Configuration

### Choosing Min/Max Columns

**Good candidates** for `minmax_columns`:
- Date/timestamp columns
- Sequential IDs (order_id, transaction_id)
- Numeric measures (amount, quantity, price)
- Monotonic or semi-ordered columns

**Poor candidates**:
- Random/hash values
- High-entropy columns with no natural ordering
- VARCHAR/TEXT with random content

### Choosing Bloom Filter Columns

**Good candidates** for `bloomfilter_columns`:
- High-cardinality categorical columns (region, product_id, customer_id)
- Status/enum fields used in equality predicates
- Hash values (transaction_hash, correlation_id)
- Frequently used in IN clauses

**Poor candidates**:
- Low-cardinality columns (better for min/max)
- Columns rarely used in WHERE clauses
- Extremely high cardinality (diminishing returns)

---

## Clustering Strategy

### Z-Order Clustering

Best for queries that filter on **multiple correlated dimensions**.

```sql
-- Example: Time + Geography correlation
CREATE TABLE events (...) USING pax WITH (
    cluster_type='zorder',
    cluster_columns='event_date,region'
);

-- Later, trigger clustering
CLUSTER events;
```

**When to use Z-order:**
- Multi-dimensional range queries
- Correlated columns (date+region, lat+lon)
- Complex WHERE clauses with multiple columns

### Lexical Clustering

Equivalent to `ORDER BY` - simpler, single-dimension sorting.

```sql
CREATE TABLE time_series (...) USING pax WITH (
    cluster_type='lexical',
    cluster_columns='timestamp'
);

CLUSTER time_series;
```

**When to use lexical:**
- Time-series data (single time dimension)
- Simple range scans on one column
- When Z-order overhead is not justified

### Clustering Maintenance

```sql
-- Check clustering status
SELECT ptblockname, ptisclustered
FROM get_pax_aux_table('my_table')
LIMIT 10;

-- Re-cluster after significant inserts
-- Only unclustered files will be processed
CLUSTER my_table;
```

---

## Storage Format: PORC vs PORC_VEC

| Format | Optimized For | When to Use |
|--------|---------------|-------------|
| **porc** (default) | Cloudberry executor | Standard OLAP queries, most use cases |
| **porc_vec** | Vectorized executor | Vectorization-enabled Cloudberry builds, extreme performance needs |

```sql
-- Standard format
CREATE TABLE standard (...) USING pax WITH (storage_format='porc');

-- Vectorized format (requires vectorization build)
CREATE TABLE vectorized (...) USING pax WITH (storage_format='porc_vec');
```

---

## Performance Tuning Checklist

### Pre-Deployment
- [ ] Analyze query patterns to choose statistics columns
- [ ] Profile data cardinality for encoding decisions
- [ ] Identify correlated dimensions for clustering
- [ ] Size micro-partitions based on workload

### Post-Deployment
- [ ] Run `ANALYZE` after initial load
- [ ] Execute `CLUSTER` after bulk inserts
- [ ] Monitor sparse filter effectiveness (check logs)
- [ ] Review and adjust GUCs based on workload

### Monitoring

```sql
-- Check table size and compression
SELECT pg_size_pretty(pg_total_relation_size('my_table')) AS size;

-- Review micro-partition statistics
SELECT COUNT(*) AS num_files,
       AVG((ptstatistics->>'numRows')::BIGINT) AS avg_rows,
       SUM(CASE WHEN ptisclustered THEN 1 ELSE 0 END) AS clustered
FROM get_pax_aux_table('my_table');

-- Sample query performance
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM my_table WHERE date_col = CURRENT_DATE;
```

---

## Common Pitfalls

### ❌ Too Many Statistics Columns

```sql
-- BAD: All columns with stats (high overhead)
CREATE TABLE bad (...) USING pax WITH (
    minmax_columns='col1,col2,col3,col4,col5,col6,col7,col8,col9,col10'
);
```

```sql
-- GOOD: Select 4-6 key columns
CREATE TABLE good (...) USING pax WITH (
    minmax_columns='date_col,amount_col,id_col,timestamp_col'
);
```

### ❌ Wrong Clustering Dimensions

```sql
-- BAD: Uncorrelated columns
CREATE TABLE bad (...) USING pax WITH (
    cluster_columns='random_uuid,hash_value'  -- No benefit
);
```

```sql
-- GOOD: Correlated columns
CREATE TABLE good (...) USING pax WITH (
    cluster_columns='event_date,user_region'  -- Often queried together
);
```

### ❌ Forgetting to Cluster

```sql
-- Create table with cluster config
CREATE TABLE my_table (...) USING pax WITH (cluster_columns='date,region');

-- Insert data
INSERT INTO my_table SELECT ...;

-- ❌ MISSING: Need to actually run CLUSTER command!
-- ✅ CORRECT: Execute clustering
CLUSTER my_table;
```

---

## Quick Reference

### Default PAX Settings

| Parameter | Default | Range |
|-----------|---------|-------|
| `pax.enable_sparse_filter` | `on` | on/off |
| `pax.enable_row_filter` | `off` | on/off |
| `pax.max_tuples_per_file` | 1,310,720 | 131,072 - 8,388,608 |
| `pax.max_size_per_file` | 67,108,864 (64MB) | 8MB - 320MB |
| `pax.max_tuples_per_group` | 131,072 | 5 - 524,288 |
| `pax.bloom_filter_work_memory_bytes` | 10,240 | 1KB - 2GB |
| `pax.default_storage_format` | `porc` | porc/porc_vec |

---

## Further Resources

- PAX Implementation: `contrib/pax_storage/README.md`
- Storage Format Details: `contrib/pax_storage/doc/README.format.md`
- Clustering Algorithm: `contrib/pax_storage/doc/README.clustering.md`
- Filtering Internals: `contrib/pax_storage/doc/README.filter.md`
