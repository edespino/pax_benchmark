# Log Analytics Benchmark

Validates PAX storage for application observability workloads with sparse columns and high-cardinality identifiers.

---

## Quick Start

```bash
cd benchmarks/log_analytics
./scripts/run_log_benchmark.sh
```

**Runtime**: 3-6 minutes | **Dataset**: 10M log entries (~5-10GB total)

---

## What This Tests

### PAX Advantages for Log Data

1. **Sparse Column Filtering** 🌟 **KEY ADVANTAGE**
   - `stack_trace`: 95% NULL (only ERROR/FATAL logs)
   - `error_code`: 95% NULL (only ERROR/FATAL logs)
   - `user_id`: 30% NULL (anonymous/system logs)
   - PAX saves massive storage on NULL values

2. **High-Cardinality Bloom Filters**
   - `trace_id`: ~10M unique (distributed tracing)
   - `request_id`: ~10M unique (per-request tracking)
   - Enables fast lookup by trace/request ID

3. **Z-order Clustering**
   - Multi-dimensional: `(log_date, application_id)`
   - Optimizes time-range queries filtered by application

4. **Text Compression**
   - Log messages, stack traces, HTTP paths
   - Tests ZSTD effectiveness on text-heavy data

---

## Dataset Characteristics

**10 million log entries** simulating real observability platform:

| Aspect | Details |
|--------|---------|
| **Applications** | 200 microservices (auth, payment, user, etc.) |
| **Log Levels** | 80% INFO, 15% WARN, 4% ERROR, 1% FATAL |
| **Sparse Fields** | stack_trace (95% NULL), error_code (95% NULL), user_id (30% NULL) |
| **High-Cardinality** | trace_id, request_id (~10M unique) |
| **Moderate-Cardinality** | user_id (~5M unique, 70% present) |
| **Low-Cardinality** | log_level (6), application_id (200), region (6) |
| **Time Range** | 28 hours of logs (2025-10-01) |
| **Frequency** | ~10 logs per second |

---

## Query Categories (12 Queries)

**A. Time Range Filtering** - Tests sparse filtering (zone maps)
- Q1: Recent logs (last 2 hours)

**B. Bloom Filter Tests** - Tests high-cardinality filtering
- Q2: Trace ID lookup
- Q3: Request ID IN list

**C. Z-order Clustering Tests** - Tests multi-dimensional queries
- Q4: Application logs in time range

**D. Sparse Column Tests** - Tests PAX advantage on NULL-heavy data
- Q5: Error analysis (95% NULL filter)
- Q6: Stack trace search (text search on sparse column)

**E. Log Level Analysis** - Tests low-cardinality filtering (minmax only)
- Q7: Error rate by application

**F. HTTP Performance Analysis** - Tests moderately sparse columns (40% NULL)
- Q8: Slow requests (response_time filtering)
- Q9: HTTP status code distribution

**G. Multi-Dimensional Analysis** - Tests combined PAX features
- Q10: Regional error analysis (Z-order + sparse)
- Q11: User session analysis (bloom + sparse)
- Q12: Full scan aggregation (compression efficiency)

---

## Storage Variants (4 Tested)

1. **AO** - Append-Only row-oriented (baseline)
2. **AOCO** - Append-Only column-oriented (current best practice)
3. **PAX (no-cluster)** - PAX without clustering (control group)
4. **PAX (clustered)** - PAX with Z-order clustering

---

## Validation Framework

**Pre-Flight Checks** (Before table creation):
- ✅ **Cardinality validation** - Ensures bloom filters only on high-cardinality columns
- ✅ **Memory calculation** - Sets maintenance_work_mem appropriately
- ✅ **Auto-config generation** - Prevents manual configuration errors

**Post-Flight Checks** (After execution):
- ✅ **Bloat detection** - Validates storage overhead acceptable
- ✅ **Sparse column verification** - Confirms expected NULL percentages
- ✅ **Cardinality verification** - Validates bloom filter effectiveness
- ✅ **Row count consistency** - Ensures data loaded correctly

---

## Expected Results

### Storage (With Optimal Configuration)

```
AO (baseline):        ~1,200 MB (row-oriented, no compression)
AOCO:                 ~400-500 MB (column-oriented, ZSTD)
PAX (no-cluster):     ~420-550 MB (5-10% overhead vs AOCO)
PAX (clustered):      ~480-650 MB (10-30% overhead vs no-cluster)
```

**Key Metrics**:
- PAX no-cluster: Expected **5-10% overhead** vs AOCO (sparse column savings offset bloom filter metadata)
- Clustering overhead: Expected **10-30%** (acceptable for multi-dimensional query benefit)
- Compression ratio: **8-10x** (text-heavy data compresses well)

### Performance (With Predicate Pushdown Enabled)

```
Q2 (Trace ID lookup):    PAX 2-3x faster (bloom filter)
Q4 (Time + application): PAX 2-4x faster (Z-order clustering)
Q5 (Error analysis):     PAX 3-5x faster (sparse filtering)
Q6 (Stack trace search): PAX 5-10x faster (NULL skipping)
```

**Note**: Current Cloudberry 3.0.0-devel has predicate pushdown disabled (pax_scanner.cc:366), so performance gains are muted. Configuration is production-ready once code-level fix is deployed.

---

## File Structure

```
benchmarks/log_analytics/
├── README.md                              # This file
├── scripts/
│   └── run_log_benchmark.sh               # Master script (one-command execution)
├── sql/
│   ├── 00_validation_framework.sql        # Safety gate functions
│   ├── 01_setup_schema.sql                # Applications, log_levels dimension tables
│   ├── 02_analyze_cardinality.sql         # CRITICAL: Validate bloom filter columns
│   ├── 03_generate_config.sql             # Auto-generate safe PAX configuration
│   ├── 04_create_variants.sql             # Create AO/AOCO/PAX/PAX-no-cluster tables
│   ├── 05_generate_data.sql               # Generate 10M log entries
│   ├── 06_optimize_pax.sql                # Z-order clustering + memory validation
│   ├── 07_run_queries.sql                 # 12 queries × 4 variants
│   ├── 08_collect_metrics.sql             # Storage, compression, sparse efficiency
│   └── 09_validate_results.sql            # Final validation gates
└── results/                                # Timestamped result directories
    └── run_YYYYMMDD_HHMMSS/
        ├── 02_cardinality_analysis.txt    # Bloom filter validation results
        ├── 03_generated_config.sql         # Auto-generated PAX config
        ├── 06_optimize.log                 # Clustering overhead analysis
        ├── 07_query_results.txt            # Query performance comparison
        ├── 08_metrics.txt                  # Final storage/compression metrics
        ├── 09_validation.txt               # Validation gate results
        └── timing.txt                      # Phase-by-phase timing
```

---

## Running Individual Phases

```bash
cd benchmarks/log_analytics

# Setup
psql -f sql/00_validation_framework.sql   # Validation functions (30 sec)
psql -f sql/01_setup_schema.sql           # Dimension tables (30 sec)

# CRITICAL: Validate bloom filter configuration
psql -f sql/02_analyze_cardinality.sql    # Cardinality analysis (1 min)
psql -f sql/03_generate_config.sql        # Auto-generate config (30 sec)

# Create and load data
psql -f sql/04_create_variants.sql        # 4 variants (30 sec)
psql -f sql/05_generate_data.sql          # 10M rows (2-3 min)

# Optimize and test
psql -f sql/06_optimize_pax.sql           # Z-order clustering (1-2 min)
psql -f sql/07_run_queries.sql            # Query suite (2-3 min)
psql -f sql/08_collect_metrics.sql        # Metrics collection (30 sec)
psql -f sql/09_validate_results.sql       # Validation (30 sec)
```

---

## Configuration Details

### PAX Clustered Configuration

```sql
CREATE TABLE logs.log_entries_pax (...) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax statistics (low overhead, all filterable columns)
    minmax_columns='log_date,log_timestamp,application_id,log_level,http_status_code,response_time_ms,environment,region',

    -- Bloom filters: ONLY high-cardinality columns (CRITICAL!)
    -- ⚠️  DO NOT add application_id, log_level, or other low-cardinality columns
    bloomfilter_columns='trace_id,request_id',

    -- Z-order clustering for time-series + application queries
    cluster_type='zorder',
    cluster_columns='log_date,application_id',

    storage_format='porc'
);
```

**Key Configuration Principles**:

1. **Bloom Filters** - ONLY on high-cardinality (>1000 unique)
   - ✅ `trace_id` (~10M unique)
   - ✅ `request_id` (~10M unique)
   - ❌ `application_id` (200 unique) - would cause 80%+ bloat
   - ❌ `log_level` (6 unique) - would cause massive bloat

2. **MinMax Columns** - Use liberally (low overhead)
   - All filterable columns regardless of cardinality

3. **Clustering** - 2-3 correlated dimensions
   - `log_date` (temporal access pattern)
   - `application_id` (common filter dimension)

4. **Memory** - Set BEFORE clustering
   - 10M rows: `maintenance_work_mem = '2GB'`
   - 100M rows: `maintenance_work_mem = '8GB'`

---

## Common Issues

### ❌ "PAX storage is 80%+ larger than AOCO"

**Cause**: Bloom filters on low-cardinality columns (application_id, log_level, environment, etc.)

**Fix**:
```bash
# Step 1: Check cardinality
psql -f sql/02_analyze_cardinality.sql

# Step 2: Review output - look for "❌ DANGEROUS" markers
# Step 3: Remove any low-cardinality columns from bloomfilter_columns
# Step 4: Recreate tables with corrected configuration
```

### ❌ "Clustering caused 2-3x storage bloat"

**Cause**: Insufficient `maintenance_work_mem` during CLUSTER

**Fix**:
```sql
-- BEFORE running sql/06_optimize_pax.sql:
ALTER SYSTEM SET maintenance_work_mem = '2GB';  -- For 10M rows
SELECT pg_reload_conf();

-- Then run clustering
psql -f sql/06_optimize_pax.sql
```

### ❌ "Queries not faster on PAX"

**Expected**: Predicate pushdown currently disabled in Cloudberry 3.0.0-devel

**Verify**:
```sql
-- Check if sparse filtering is enabled
SHOW pax.enable_sparse_filter;  -- Should be 'on'

-- Analyze query plan
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM logs.log_entries_pax
WHERE trace_id = 'trace-abc123';

-- Look for "Rows Removed by Filter" (high number indicates no pushdown)
```

Not a configuration issue - requires code-level fix in pax_scanner.cc.

### ❌ "Out of disk space"

**Cause**: 4 variants × ~500MB each + indexes + overhead

**Solution**:
```bash
# Reduce to 2 variants (AOCO + PAX clustered only)
# Edit sql/04_create_variants.sql to comment out AO and PAX no-cluster

# Or reduce dataset size:
# Edit sql/05_generate_data.sql, change:
FROM generate_series(1, 10000000) gs  -- Change to 1000000 for testing
```

---

## Key Learnings

### ✅ What Works Well

1. **Sparse column storage** - PAX saves massive space on 95% NULL columns
2. **High-cardinality bloom filters** - Fast trace/request ID lookups
3. **Z-order clustering** - Excellent for time + application queries
4. **Text compression** - ZSTD handles log messages/stack traces efficiently
5. **Validation framework** - Prevents misconfiguration disasters

### ⚠️  What to Watch

1. **Bloom filter cardinality** - ALWAYS validate with Phase 2 analysis
2. **Clustering memory** - Must set maintenance_work_mem BEFORE clustering
3. **Predicate pushdown** - Currently disabled in Cloudberry 3.0.0-devel
4. **Clustering overhead** - Can be 10-30% (acceptable for query benefit)

### ❌ What to Avoid

1. **Never** add low-cardinality columns to bloom filters
2. **Never** skip cardinality validation (Phase 2)
3. **Never** cluster without setting maintenance_work_mem
4. **Never** assume cardinality - always check with pg_stats

---

## Production Recommendations

**For Log/Observability Data**:

1. **Use PAX no-cluster** if:
   - Pure append-only workload (no updates)
   - Queries are simple (single dimension filtering)
   - Want minimal overhead vs AOCO

2. **Use PAX clustered** if:
   - Multi-dimensional queries (time + application + region)
   - Can tolerate 10-30% storage overhead
   - Query performance is critical

3. **Always validate**:
   - Run cardinality analysis on sample data first
   - Use validation framework to generate configuration
   - Test on 1M rows before scaling to production

4. **Maintenance considerations**:
   - Set `maintenance_work_mem` appropriately (2GB per 10M rows)
   - Re-cluster periodically if data distribution changes
   - Monitor bloom filter effectiveness with pg_stats

---

## Related Documentation

- **Main repo overview**: `../../README.md`
- **Benchmark suite overview**: `../README.md`
- **PAX technical architecture**: `../../docs/TECHNICAL_ARCHITECTURE.md`
- **Configuration guide**: `../../docs/CONFIGURATION_GUIDE.md`
- **Methodology**: `../../docs/METHODOLOGY.md`

---

## Benchmark Comparison

| Aspect | log_analytics | timeseries_iot | retail_sales |
|--------|---------------|----------------|--------------|
| **Runtime** | 3-6 min | 2-5 min | 2-4 hours |
| **Rows** | 10M | 10M | 200M |
| **Size** | ~5-10GB | ~3-5GB | ~210GB |
| **Key Feature** | Sparse columns (95% NULL) | Fast validation | Comprehensive |
| **Best For** | Log/APM testing | Quick iteration | Production validation |

---

_Last Updated: January 2025 (Initial Release)_
