# PAX Benchmark Methodology

## Overview

This document describes the methodology used in the PAX storage performance benchmark, ensuring reproducibility and scientific rigor.

---

## Benchmark Design Principles

### 1. Fair Comparison
- All three storage variants (AO, AOCO, PAX) use identical data
- Same distribution keys and cluster configuration
- Equivalent compression settings where applicable (zstd level 5)
- All tables analyzed before query execution

### 2. Realistic Workload
- 200M rows (~70GB per table variant)
- 25 columns with mixed types (numeric, text, dates, categorical)
- Realistic data distributions (skewed, correlated, sparse)
- Patterns that reflect actual analytical workloads

### 3. Comprehensive Coverage
- 20 queries across 7 categories
- Tests specific PAX features (sparse filtering, bloom filters, clustering)
- Includes simple and complex queries (aggregations, joins, window functions)
- Edge cases (NULLs, high cardinality, MVCC operations)

### 4. Statistical Validity
- 3 runs per query per variant
- Median values reported (reduces outlier impact)
- Cache clearing between runs (CHECKPOINT + sleep)
- Consistent execution order

---

## Hardware & Environment

### Recommended Cluster Configuration

```
Coordinator: 1 node
Segments: 3+ primary segments (+ 3 mirrors recommended)
Memory: 8GB+ per segment
CPU: 4+ cores per segment
Disk: SSD preferred, 300GB+ free space
```

### Software Requirements

```
Cloudberry Database: PostgreSQL 14+ base
PAX Extension: --enable-pax build flag
Dependencies:
  - GCC/G++ 8+
  - CMake 3.11+
  - Protobuf 3.5.0+
  - ZSTD 1.4.0+
```

---

## Data Generation Strategy

### Schema Design

**Fact Table: sales_fact**
- 200M rows
- 25 columns covering all data types
- Distributed by `order_id` (sequential, good for delta encoding)

**Key Design Choices:**
1. **Time dimensions** (`sale_date`, `sale_timestamp`): Correlated with region for Z-order benefit
2. **Sequential IDs** (`order_id`): Tests delta encoding effectiveness
3. **Categorical columns** (8 columns): Mix of low and high cardinality for RLE/bloom filter testing
4. **Sparse columns** (2 columns): Mostly NULL to test sparse storage
5. **Hash column** (`transaction_hash`): Tests bloom filter on high-entropy data

### Data Distribution

```
Regions: 5 values (skewed: 40% North America, 25% Europe, 20% Asia Pacific, 10% Latin America, 5% Middle East)
Countries: 20 values (realistic distribution)
Sales Channels: 3 values (Online 40%, Store 40%, Phone 20%)
Order Status: 4 values (Delivered 40%, Shipped 30%, Pending 20%, Cancelled 10%)
Dates: 4 years (2020-01-01 to 2023-12-31)
```

**Correlation**: `sale_date` and `region` have intentional correlation to benefit Z-order clustering.

---

## Storage Variant Configuration

### Variant 1: AO (Baseline)

```sql
CREATE TABLE sales_fact_ao (...) WITH (
    appendonly=true,
    orientation=row,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (order_id);
```

**Purpose**: Establish baseline for row-oriented append-only storage.

### Variant 2: AOCO (Current Best Practice)

```sql
CREATE TABLE sales_fact_aoco (...) WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (order_id);
```

**Purpose**: Represent current recommended columnar storage in Cloudberry.

### Variant 3: PAX (Optimized)

```sql
CREATE TABLE sales_fact_pax (...) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,
    minmax_columns='sale_date,order_id,customer_id,product_id,total_amount,quantity',
    bloomfilter_columns='region,country,sales_channel,order_status,product_category,transaction_hash',
    cluster_type='zorder',
    cluster_columns='sale_date,region',
    storage_format='porc'
) DISTRIBUTED BY (order_id);

-- Per-column encoding
ALTER TABLE sales_fact_pax
    ALTER COLUMN sale_date SET ENCODING (compresstype=delta),
    ALTER COLUMN order_id SET ENCODING (compresstype=delta),
    ALTER COLUMN quantity SET ENCODING (compresstype=delta),
    ALTER COLUMN priority SET ENCODING (compresstype=RLE_TYPE),
    ALTER COLUMN is_return SET ENCODING (compresstype=RLE_TYPE),
    ALTER COLUMN order_status SET ENCODING (compresstype=RLE_TYPE),
    ALTER COLUMN sales_channel SET ENCODING (compresstype=RLE_TYPE);

-- Execute Z-order clustering
CLUSTER sales_fact_pax;
```

**Purpose**: Showcase PAX with all optimizations enabled.

---

## Query Categories

### Category A: Sparse Filtering (Q1-Q3)
Tests zone map effectiveness (min/max statistics).

**Expected Behavior:**
- PAX should skip 60-90% of files on selective predicates
- Significant speedup on date range and numeric range queries

**Sample Query:**
```sql
SELECT SUM(total_amount)
FROM sales_fact_pax
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';
```

### Category B: Bloom Filters (Q4-Q6)
Tests bloom filter effectiveness on high-cardinality columns.

**Expected Behavior:**
- Fast equality/IN clause evaluation
- File-level pruning before scan

**Sample Query:**
```sql
SELECT COUNT(*)
FROM sales_fact_pax
WHERE country IN ('USA', 'Canada', 'UK')
  AND sales_channel = 'Online';
```

### Category C: Z-Order Clustering (Q7-Q9)
Tests multi-dimensional query performance.

**Expected Behavior:**
- 3-5x speedup on correlated dimension queries
- Better cache locality

**Sample Query:**
```sql
SELECT SUM(total_amount)
FROM sales_fact_pax
WHERE sale_date BETWEEN '2022-12-01' AND '2022-12-31'
  AND region = 'North America';
```

### Category D: Compression (Q10-Q12)
Tests I/O efficiency and compression effectiveness.

**Expected Behavior:**
- PAX 30-40% smaller than AOCO
- Faster full table scans due to better compression

### Category E: Complex Analytics (Q13-Q15)
Tests joins, window functions, subqueries.

**Expected Behavior:**
- Benefits compound across operations
- Join performance similar or better due to smaller data size

### Category F: MVCC (Q16-Q18)
Tests update/delete performance and visimap efficiency.

**Expected Behavior:**
- Comparable or better update performance
- Efficient visibility filtering

### Category G: Edge Cases (Q19-Q20)
Tests NULL handling and high cardinality.

**Expected Behavior:**
- Sparse column storage efficiency
- Graceful handling of challenging patterns

---

## Execution Protocol

### Pre-Execution Checklist
1. ✅ PAX extension installed and verified
2. ✅ Cluster healthy (all segments up)
3. ✅ Adequate disk space (300GB+ free)
4. ✅ No other workload running

### Execution Steps

```bash
# 1. Prepare environment
source /usr/local/cloudberry/greenplum_path.sh
cd pax_benchmark

# 2. Run full benchmark (automated)
./scripts/run_full_benchmark.sh

# 3. Manual execution (alternative)
psql -f sql/01_setup_schema.sql
psql -f sql/02_create_variants.sql
psql -f sql/03_generate_data.sql  # ~30-60 min
psql -f sql/04_optimize_pax.sql   # ~10-20 min
# Run queries (see next section)
psql -f sql/06_collect_metrics.sql
```

### Query Execution

For each query Q1-Q20:
1. Run on AO variant (3 times)
2. Run on AOCO variant (3 times)
3. Run on PAX variant (3 times)

Between each run:
```sql
CHECKPOINT;  -- Flush buffers
```
Then wait 2 seconds before next run.

### PAX-Specific Setup

```sql
-- Enable optimal GUCs before PAX queries
SET pax.enable_sparse_filter = on;
SET pax.enable_row_filter = off;
SET pax.max_tuples_per_file = 1310720;
SET pax.max_size_per_file = 67108864;
SET pax.bloom_filter_work_memory_bytes = 10485760;
```

---

## Metrics Collection

### Primary Metrics

From `EXPLAIN (ANALYZE, BUFFERS, TIMING)`:

1. **Execution Time**: Actual query execution (ms)
2. **Planning Time**: Query planning overhead (ms)
3. **Total Time**: Planning + Execution (ms)
4. **Rows Returned**: Result set size
5. **Buffers (hit/read)**: Cache efficiency
6. **Sparse Filter Info**: Files skipped (PAX only)

### Secondary Metrics

1. **Storage Size**: `pg_total_relation_size()`
2. **Compression Ratio**: Uncompressed estimate / Actual size
3. **Micro-Partition Stats**: File count, avg rows/file, clustering status

### Aggregation

- **Median** execution time across 3 runs (primary metric)
- **Min/Max** for variance analysis
- **Percentage improvement**: `100 * (AOCO_time - PAX_time) / AOCO_time`

---

## Reproducibility Guidelines

### To Reproduce This Benchmark

```bash
# 1. Clone repository
git clone https://github.com/apache/cloudberry.git
cd cloudberry

# 2. Build with PAX
./configure --enable-pax --with-perl --with-python --with-libxml
git submodule update --init --recursive
make -j8 && make -j8 install

# 3. Create cluster
make create-demo-cluster
source gpAux/gpdemo/gpdemo-env.sh

# 4. Run benchmark
cd pax_benchmark
./scripts/run_full_benchmark.sh
```

### Expected Runtime

| Phase | Duration |
|-------|----------|
| Schema setup | 5-10 min |
| Data generation | 30-60 min |
| Clustering | 10-20 min |
| Query execution | 60-120 min |
| **Total** | **2-4 hours** |

### Verification

Compare your results against reference results:
- Storage: PAX should be 30-40% smaller than AOCO
- Performance: PAX should be 20-35% faster on average
- Sparse filtering: 60-90% file skip rate on selective queries

---

## Limitations & Considerations

### Known Limitations

1. **Cold cache effects**: First run may be slower; we use median of 3 runs
2. **Cluster size dependency**: Results scale with segment count
3. **Hardware variance**: SSD vs HDD significantly impacts results
4. **Data distribution**: Real data may have different characteristics

### Factors Not Tested

- **Write performance**: Benchmark focuses on read-heavy OLAP
- **Concurrent queries**: Single-query performance only
- **Very large datasets**: >1TB not tested in this benchmark
- **Vectorized execution**: PORC format tested, not PORC_VEC

### Potential Confounding Variables

- **OS page cache**: Mitigated by CHECKPOINT between runs
- **Segment placement**: Use consistent distribution key
- **Statistics staleness**: Run ANALYZE before queries
- **Resource contention**: Ensure no other workload running

---

## Interpretation Guidelines

### Success Criteria

The benchmark demonstrates PAX superiority if:
- ✅ PAX ≥ 20% faster than AOCO on average
- ✅ PAX ≥ 30% smaller than AOCO in storage
- ✅ Sparse filtering skips ≥ 60% of files
- ✅ Z-order queries show ≥ 2x speedup

### Red Flags

Investigate if:
- ❌ PAX slower than AOCO on most queries
- ❌ Sparse filter skip rate < 30%
- ❌ Compression ratio worse than AOCO
- ❌ Z-order clustering shows no benefit

Possible causes: Incorrect GUC settings, data not clustered, statistics not collected, or workload mismatch.

---

## References

- **TPC-H 1TB Results**: PAX 3:42 vs AOCO 4:25 (16% improvement)
- **TPC-DS 1TB Results**: PAX 13:29 vs AOCO 15:13 (11% improvement)
- **PAX Architecture**: Leonid Borchuk, PGConf St. Petersburg
- **Source Code**: `contrib/pax_storage/` (62K+ lines)

---

## Contact & Contributions

For questions, issues, or improvements to this benchmark:
- GitHub Issues: https://github.com/apache/cloudberry/issues
- Community: cloudberry.apache.org
