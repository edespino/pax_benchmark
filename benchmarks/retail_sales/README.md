# Retail Sales Analytics Benchmark

**Original PAX benchmark** - Comprehensive sales analytics workload testing PAX storage performance.

---

## Overview

This is the original PAX benchmark that validates storage efficiency and query performance for a **retail sales analytics** workload. It tests:

- **Dataset**: 200M sales transactions (~70GB per variant, ~210GB total)
- **Variants**: AO (row-oriented), AOCO (column-oriented), PAX, PAX (no-cluster)
- **Workload**: 20 analytical queries testing various PAX features
- **Runtime**: 2-4 hours for full benchmark

---

## Dataset Schema

### Fact Table: `benchmark.sales_fact`
- **200M rows** of sales transactions
- **25 columns**: transaction details, customer/product IDs, amounts, dates, regions
- **Patterns**: Correlated dimensions (date+region), skewed distributions, sparse fields

### Dimension Tables:
- `benchmark.customers` - 10M customers (~5GB)
- `benchmark.products` - 100K products

---

## Quick Start

### Run Full Benchmark (200M rows, 2-4 hours)

```bash
cd retail_sales_benchmark
./scripts/run_full_benchmark.sh
```

### Run Small Test (1M rows, 10 minutes)

```bash
psql postgres -f sql/01_setup_schema.sql
psql postgres -f sql/02_create_variants.sql
psql postgres -f sql/03_generate_data_SMALL.sql  # 1M rows instead of 200M
psql postgres -f sql/04_optimize_pax.sql
psql postgres -f sql/05_test_sample_queries.sql
psql postgres -f sql/06_collect_metrics.sql
```

---

## File Structure

```
retail_sales_benchmark/
├── README.md                    # This file
├── scripts/
│   ├── run_full_benchmark.sh    # Master automation script
│   ├── generate_charts.py       # Generate PNG charts
│   └── parse_explain_results.py # Extract metrics from logs
├── sql/
│   ├── 01_setup_schema.sql              # Schema + dimension tables
│   ├── 02_create_variants.sql           # AO/AOCO/PAX/PAX-no-cluster
│   ├── 03_generate_data.sql             # 200M rows (large-scale)
│   ├── 03_generate_data_SMALL.sql       # 1M rows (quick test)
│   ├── 04_optimize_pax.sql              # Z-order clustering + GUCs
│   ├── 04a_validate_clustering_config.sql # Memory validation
│   ├── 05_queries_ALL.sql               # 20 analytical queries
│   ├── 05_test_sample_queries.sql       # Quick 2-query test
│   ├── 06_collect_metrics.sql           # Storage + performance metrics
│   ├── 07_inspect_pax_internals.sql     # PAX statistics analysis
│   └── 08_analyze_query_plans.sql       # Detailed EXPLAIN ANALYZE
└── results/
    └── run_YYYYMMDD_HHMMSS/             # Generated during execution
```

---

## Benchmark Phases

### Phase 1: Schema Setup (5-10 min)
Creates benchmark schema, customers dimension (10M rows), products dimension (100K rows).

### Phase 2: Create Variants (2 min)
Creates 4 table variants:
1. **AO** - Append-Only row-oriented (baseline)
2. **AOCO** - Append-Only column-oriented (current best practice)
3. **PAX** - PAX with Z-order clustering
4. **PAX (no-cluster)** - PAX without clustering (control group)

### Phase 3: Data Generation (30-60 min)
Generates 200M sales transactions across all 4 variants.

**For quick testing**: Use `03_generate_data_SMALL.sql` instead (1M rows, ~2 min).

### Phase 4: Optimization & Clustering (10-20 min)
- Sets PAX GUCs (sparse filtering, bloom filter memory)
- Runs Z-order clustering on `sales_fact_pax`
- **Critical**: Sets `maintenance_work_mem=2GB` to prevent storage bloat

### Phase 5: Query Execution (1-2 hours)
Runs 20 queries on each variant (3 runs each, 60 queries per variant).

**Query categories**:
- **A (Q1-Q3)**: Sparse filtering effectiveness
- **B (Q4-Q6)**: Bloom filter effectiveness
- **C (Q7-Q9)**: Z-order clustering benefits
- **D (Q10-Q12)**: Compression efficiency
- **E (Q13-Q15)**: Complex analytics
- **F (Q16-Q18)**: MVCC operations
- **G (Q19-Q20)**: Edge cases

### Phase 6: Metrics Collection (2 min)
Collects storage sizes, compression ratios, and performance metrics.

---

## Expected Results (October 2025 Testing)

Based on **10M row test** with optimized configuration:

### Storage Comparison

| Variant | Size | vs AOCO | Assessment |
|---------|------|---------|------------|
| **AO** | 607 MB | 1.52x | Baseline row-oriented |
| **AOCO** | 710 MB | 1.00x | Baseline column-oriented |
| **PAX (no-cluster)** | 745 MB | 1.05x | ✅ **5% overhead** |
| **PAX (clustered)** | 942 MB | 1.33x | ⚠️ **26% overhead** (higher than expected) |

### Key Metrics
- **PAX no-cluster**: Production-ready (5% overhead)
- **Compression**: PAX 6.5x, AOCO 8.7x, AO 3.1x
- **Z-order clustering**: 3-5x speedup on multi-dimensional range queries (when file-level pruning enabled)

---

## Configuration Highlights

### PAX Table Configuration (sql/02_create_variants.sql)

**✅ Optimized (October 2025)**:
```sql
CREATE TABLE benchmark.sales_fact_pax (...) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Low overhead, use liberally (6-12 columns)
    minmax_columns='date,id,amount,region,status,category',

    -- Bloom: High overhead, use selectively (1-3 columns)
    -- CRITICAL: ONLY high-cardinality (>1000 distinct values)
    bloomfilter_columns='product_id',  -- 99K unique ✅

    -- Z-order clustering (2-3 correlated dimensions)
    cluster_columns='date,region',
    cluster_type='zorder',

    storage_format='porc'
);
```

**⚠️ Critical Lesson**: Low-cardinality bloom filters cause **80%+ storage bloat**.
- Always validate cardinality with `sql/07_inspect_pax_internals.sql` before configuring bloom filters
- Use `sql/04a_validate_clustering_config.sql` to check memory requirements

---

## Validation & Analysis Tools

### Pre-Flight Validation
```bash
# Check memory requirements BEFORE clustering
psql postgres -f sql/04a_validate_clustering_config.sql
```

### Post-Deployment Analysis
```bash
# Analyze PAX statistics and cardinality
psql postgres -f sql/07_inspect_pax_internals.sql

# Review detailed query plans
psql postgres -f sql/08_analyze_query_plans.sql
```

---

## Known Limitations

1. **File-level predicate pushdown**: Disabled in Cloudberry 3.0.0-devel (code-level issue)
   - PAX queries may not show full performance benefits
   - Feature works in production Cloudberry builds

2. **Z-order clustering overhead**: 26% larger than no-cluster variant (expected <5%)
   - Requires investigation
   - May be related to maintenance_work_mem or data characteristics

---

## Customization

### Change Dataset Size
Edit `sql/03_generate_data.sql`:
```sql
-- Line ~45: Change 200000000 to desired size
FROM generate_series(1, 50000000) gs  -- 50M instead of 200M
```

### Add Custom Queries
Edit `sql/05_queries_ALL.sql`:
```sql
-- Add at end (after Q20)
\echo 'Q21: Your custom query'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT ... FROM benchmark.sales_fact_TABLE_VARIANT WHERE ...;
```

### Tune PAX Configuration
Edit `sql/02_create_variants.sql` (lines 111-141) - **see Configuration Highlights above**.

---

## Results Analysis

After benchmark completion, review:

1. **Storage comparison**: `results/run_YYYYMMDD_HHMMSS/Phase6_Metrics_*.log`
2. **Query performance**: `results/run_YYYYMMDD_HHMMSS/queries/`
3. **Timing breakdown**: Check phase completion times in logs

### Generate Charts
```bash
python3 scripts/generate_charts.py results/run_YYYYMMDD_HHMMSS/
```

### Parse Query Results
```bash
python3 scripts/parse_explain_results.py results/run_YYYYMMDD_HHMMSS/
```

---

## Historical Context

This benchmark was used for the **October 2025 PAX optimization testing** that discovered:
- **Critical issue**: Low-cardinality bloom filters cause 81% storage bloat
- **Solution**: Validate cardinality BEFORE configuring bloom filters
- **Production guidance**: PAX no-cluster variant is production-ready (5% overhead)

See `../results/` for historical test results and analysis.

---

## Related Benchmarks

- **timeseries_iot_benchmark**: IoT sensor data (fast iteration, 2-5 min)
- **financial_trading_benchmark**: High-frequency trading ticks (medium iteration, 4-8 min)

This retail sales benchmark is the **most comprehensive** (2-4 hours) but provides the most realistic large-scale validation.
