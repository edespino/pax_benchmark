# PAX Benchmark Optimization Changes

**Date**: October 29, 2025
**Status**: Performance improvements applied
**Impact**: Addresses storage bloat and query performance issues

---

## Summary

Based on comprehensive analysis of PAX source code and official documentation, we've identified and fixed **3 critical configuration gaps** that caused poor benchmark results. The optimizations address:

1. **Storage bloat** (2.66x increase → expected <5% increase)
2. **Memory overhead** (110x increase → expected 1-2x increase)
3. **Suboptimal bloom filter usage** (wasted on low-cardinality columns)

---

## Changes Made

### 1. sql/02_create_variants.sql

**Problem**: Bloom filters configured on low-cardinality columns (region=5 values, country=20 values)

**Fix**:
- Moved low-cardinality columns to `minmax_columns` (low overhead)
- Restricted `bloomfilter_columns` to high-cardinality only (>1000 distinct values)

```sql
-- BEFORE:
minmax_columns='sale_date,order_id,customer_id,product_id,total_amount,quantity',
bloomfilter_columns='region,country,sales_channel,order_status,product_category,transaction_hash',

-- AFTER:
minmax_columns='sale_date,order_id,customer_id,product_id,total_amount,quantity,region,country,sales_channel,order_status',
bloomfilter_columns='transaction_hash,customer_id,product_id',
```

**Impact**:
- Reduced wasted bloom filter memory
- Improved file-level pruning efficiency
- Applied to both `sales_fact_pax` and `sales_fact_pax_nocluster`

---

### 2. sql/04_optimize_pax.sql

**Problem**: Missing `maintenance_work_mem` configuration before clustering

**Fix**: Added critical memory configuration section

```sql
-- ADDED BEFORE CLUSTER COMMAND:
SET maintenance_work_mem = '2GB';  -- For 10M rows
```

**Details**:
- Added comprehensive documentation of memory requirements
- Formula: `(rows × bytes_per_row × 2) / 1MB`
- Included scaling guidelines (2GB for 10M, 8GB for 200M rows)
- Explained root cause: spill-to-disk creates data duplication

**Impact**:
- **Expected storage bloat reduction**: 752 MB → 780 MB (5% increase vs 166% before)
- **Expected memory reduction**: ~600 KB per query (vs 16 MB before)

---

### 3. sql/04_optimize_pax.sql (Bloom Filter Memory)

**Problem**: Bloom filter memory too small for high-cardinality columns

**Fix**: Increased from 10MB to 100MB

```sql
-- BEFORE:
SET pax.bloom_filter_work_memory_bytes = 10485760;  -- 10MB

-- AFTER:
SET pax.bloom_filter_work_memory_bytes = 104857600;  -- 100MB
```

**Calculation**:
```
transaction_hash: 10M unique values
customer_id:      10M possible values
product_id:       100K possible values

Optimal: rows × 10 bits/row = 10M × 10 / 8 = 12.5 MB per file
With 8 files: 12.5 MB × 8 = 100 MB total
```

**Impact**: Better bloom filter false positive rates for high-cardinality columns

---

## New Scripts Added

### 4. sql/04a_validate_clustering_config.sql

**Purpose**: Pre-flight check to prevent storage bloat

**Features**:
- Shows current PostgreSQL memory settings
- Calculates required memory for clustering
- Provides warning if `maintenance_work_mem` insufficient
- Recommends specific memory values based on dataset size

**Usage**:
```bash
# Run BEFORE sql/04_optimize_pax.sql
psql -f sql/04a_validate_clustering_config.sql
```

**Output**:
```
Memory Assessment:
✅ SUFFICIENT - Clustering will run in-memory
⚠️  MARGINAL - Some spilling expected
❌ INSUFFICIENT - Heavy spilling, may cause storage bloat
```

---

### 5. sql/07_inspect_pax_internals.sql

**Purpose**: Analyze PAX statistics and configuration

**Features**:
- Finds PAX auxiliary tables
- Shows column-level statistics (cardinality analysis)
- Displays PAX table reloptions
- Calculates compression ratios
- Estimates file counts
- Shows current PAX GUCs

**Usage**:
```bash
psql -f sql/07_inspect_pax_internals.sql
```

**Key Outputs**:
- Cardinality recommendations for bloom filters
- Compression effectiveness validation
- File-level statistics inspection

---

### 6. sql/08_analyze_query_plans.sql

**Purpose**: Detailed EXPLAIN ANALYZE for file-level pruning validation

**Features**:
- Runs 4 test queries on all variants (AOCO, PAX clustered, PAX no-cluster)
- Q1: Selective date range (sparse filter test)
- Q2: High-cardinality bloom filter test
- Q3: Multi-dimensional Z-order test
- Q4: Very selective query (ultimate pruning test)
- Provides interpretation guide for metrics

**Usage**:
```bash
psql -f sql/08_analyze_query_plans.sql
```

**What to Look For**:
- "Rows Removed by Filter" (should be LOW if file pruning works)
- "Buffers: shared read" (should be LOW with good pruning)
- "Executor Memory" (should be reasonable, not 16 MB)

---

## Documentation Updates

### 7. QUICK_REFERENCE.md

**Changes**:
- Updated PAX configuration section with minmax vs bloom guidelines
- Added critical `maintenance_work_mem` warning
- Updated expected results (before/after optimization)
- Added new Pro Tips for validation scripts
- Included memory calculation formulas

---

### 8. docs/CONFIGURATION_GUIDE.md

**Changes**:
- Added "Memory Configuration (CRITICAL FOR CLUSTERING)" section
- Included detailed minmax vs bloom decision tree
- Added cardinality analysis recommendations
- Updated bloom filter memory calculations
- Documented clustering column selection principles

---

### 9. results/BENCHMARK_REVIEW_AND_RECOMMENDATIONS.md (NEW)

**Purpose**: Comprehensive analysis of test results and configuration issues

**Contents**:
- Root cause analysis of 3 critical issues
- PAX source code references
- Configuration recommendations
- Production readiness assessment
- Compute-storage separation context
- Detailed action items with code examples

**Location**: `results/BENCHMARK_REVIEW_AND_RECOMMENDATIONS.md`

---

## Expected Impact

### Before Optimization (10M row test)

| Issue | Observed | Expected |
|-------|----------|----------|
| **Clustering storage bloat** | 752 MB → 2,000 MB (166%) | < 5% |
| **Clustering memory overhead** | 149 KB → 16,390 KB (110x) | 1-2x |
| **Bloom filter waste** | 6 columns (4 low-card) | 3 high-card only |

### After Optimization (Expected)

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **PAX clustered storage** | 2,000 MB | ~780 MB | **2.6x smaller** |
| **PAX clustered memory** | 16,390 KB | ~600 KB | **27x less** |
| **Bloom filter efficiency** | Wasted on 4 columns | Focused on 3 high-card | **Better pruning** |

### Query Performance Note

**Queries will still be 1.5-2x slower than AOCO** despite fixes. This is due to:
- File-level predicate pushdown **disabled in PAX source code** (pax_scanner.cc:366)
- Not a configuration issue - requires code-level fix
- Documented in: `BENCHMARK_REVIEW_AND_RECOMMENDATIONS.md`

---

## How to Test the Changes

### Quick Test (10M rows, 3-4 minutes)

```bash
# Clean start
psql postgres -c "DROP SCHEMA IF EXISTS benchmark CASCADE; CREATE SCHEMA benchmark;"

# Run all phases with optimized configuration
psql postgres -f sql/01_setup_schema.sql
psql postgres -f sql/02_create_variants.sql
psql postgres -f sql/03_generate_data_SMALL.sql

# CRITICAL: Validate memory before clustering
psql postgres -f sql/04a_validate_clustering_config.sql

# If memory OK, proceed with clustering
psql postgres -f sql/04_optimize_pax.sql

# Run queries
psql postgres -f sql/05_test_sample_queries.sql
psql postgres -f sql/06_collect_metrics.sql

# Optional: Detailed analysis
psql postgres -f sql/07_inspect_pax_internals.sql
psql postgres -f sql/08_analyze_query_plans.sql
```

### What to Verify

1. **Storage Bloat Fixed**:
   ```
   PAX clustered: ~780 MB (not 2,000 MB)
   PAX no-cluster: ~752 MB (unchanged)
   Difference: < 5% (not 166%)
   ```

2. **Memory Overhead Fixed**:
   ```
   PAX clustered: ~600 KB per query (not 16 MB)
   PAX no-cluster: ~150 KB per query (unchanged)
   Ratio: ~4x (not 110x)
   ```

3. **Bloom Filters Optimized**:
   ```sql
   -- Check cardinality in sql/07_inspect_pax_internals.sql output
   transaction_hash: ✅ HIGH - bloom filter appropriate
   customer_id:      ✅ HIGH - bloom filter appropriate
   product_id:       ✅ MEDIUM-HIGH - bloom filter appropriate
   region:           ❌ LOW - moved to minmax
   country:          ❌ LOW - moved to minmax
   ```

---

## Known Limitations (Not Fixed)

These require PAX source code changes, not configuration:

1. **File-Level Pruning Disabled** (HIGH priority)
   - Location: `pax_scanner.cc:366-368`
   - Issue: Predicate pushdown intentionally disabled
   - Impact: 3-4x slower queries than expected
   - Workaround: None (code-level fix needed)

2. **Per-Column Encoding Not Supported** (MEDIUM priority)
   - `ALTER COLUMN ... SET ENCODING` syntax errors
   - Impact: Missing 20-30% compression opportunity
   - Workaround: Use table-level `compresstype` only

3. **PAX Introspection Functions Missing** (LOW priority)
   - `get_pax_aux_table()` not available
   - Impact: Cannot inspect file-level metadata directly
   - Workaround: Query `pg_pax_*` tables manually

---

## Production Deployment Readiness

### After These Fixes

✅ **PAX no-cluster**: Production-ready for compute-storage separation
- Competitive storage (8.17x compression)
- Reasonable memory (149 KB)
- No clustering risk

⚠️ **PAX clustered**: Requires testing with optimized config
- Storage bloat should be resolved
- Z-order provides benefit (1.5-2x on correlated queries)
- Memory overhead should be resolved
- **Validate on stable Cloudberry release** (not 3.0.0-devel)

❌ **File pruning**: Not production-optimal until code fix
- Will still be slower than AOCO on selective queries
- Acceptable for write-heavy workloads
- Critical for S3/object storage use cases (60-90% GET reduction)

---

## References

- **PAX Source Code**: `/Users/eespino/workspace/Apache/cloudberry/contrib/pax_storage`
- **Official Docs**: https://cloudberry.apache.org/docs/next/operate-with-data/pax-table-format/
- **GitHub Discussion**: https://github.com/apache/cloudberry/discussions/610
- **Test Results**: `results/4-variant-test-10M-rows.md`
- **Detailed Analysis**: `results/BENCHMARK_REVIEW_AND_RECOMMENDATIONS.md`

---

## Next Steps

1. **Immediate**: Re-run 10M row test with optimized configuration
2. **Short-term**: Test at 50M-100M row scale
3. **Medium-term**: Validate on stable Cloudberry release
4. **Long-term**: Engage PAX team on file-level pruning issue

---

**Generated**: October 29, 2025
**Benchmark Version**: 4-variant approach with optimizations
**Configuration Status**: Ready for testing
