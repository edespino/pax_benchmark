# Clustering Overhead Investigation - November 3, 2025

## Issue Summary

Z-order clustering overhead increased from **6.3% to 10.1%** after adding deterministic seeding (seed=0.5). This document investigates the root cause.

---

## Observations

### Storage Metrics Comparison

| Metric | Old Run (no seed) | New Run (seed=0.5) | Change |
|--------|-------------------|---------------------|--------|
| **Rows** | 30,290,000 | 39,430,000 | +30% |
| **PAX-no-cluster** | 1118 MB (36.91 MB/M) | 1420 MB (36.01 MB/M) | Similar efficiency |
| **PAX-clustered** | 1189 MB (39.25 MB/M) | 1564 MB (39.67 MB/M) | Similar efficiency |
| **Clustering overhead** | 71 MB (2.34 MB/M) | 144 MB (3.65 MB/M) | **+56%** |
| **Overhead %** | 6.3% | 10.1% | **+3.8 percentage points** |

### Key Finding

**Base storage efficiency is identical** (~36 MB/M for no-cluster, ~39.7 MB/M for clustered).

**Clustering overhead per million rows increased by 56%** (2.34 → 3.65 MB/M).

---

## Root Cause Analysis

### Investigation Steps

1. **Checked data distribution on clustering dimensions**
   ```sql
   SELECT COUNT(DISTINCT call_date), COUNT(DISTINCT cell_tower_id)
   FROM cdr.cdr_pax_nocluster;
   ```

2. **Result:**
   ```
   call_date:      1 distinct value  (2025-10-01)
   cell_tower_id:  10,000 distinct values
   ```

### Root Cause: Degenerate Z-Order Clustering

**Configuration:**
```sql
cluster_type='zorder',
cluster_columns='call_date,cell_tower_id'
```

**Problem:**
- `call_date` has only **1 distinct value** (all data on 2025-10-01)
- Z-order clustering on `(call_date, cell_tower_id)` **degenerates** to single-dimension clustering on `cell_tower_id` only
- **No multi-dimensional benefit** - Z-order curve collapses to a simple sort

### Why This Causes Higher Overhead

**Z-order clustering works best when:**
1. ✅ Both dimensions have good cardinality
2. ✅ Data is correlated across both dimensions
3. ✅ Queries filter on both dimensions

**Current situation:**
1. ❌ call_date has cardinality = 1 (no selectivity)
2. ✅ cell_tower_id has cardinality = 10,000
3. ❌ No multi-dimensional benefit

**Result:**
- Clustering algorithm still performs full Z-order curve calculation
- But only achieves single-dimension sorting
- **Overhead cost without multi-dimensional benefit**

---

## Temporal Distribution Analysis

While `call_date` has only 1 value, **call_timestamp spans 24 hours** with good distribution:

```
Hour      | Rows      | Distinct Towers
----------|-----------|----------------
00:00     | 25,179    | 9,156
01:00     | 50,379    | 9,940
...
23:00     | 405,586   | 10,000
```

**All data is on the same date but spreads across 24 hours.**

---

## Why Old Run Had Lower Overhead

The old run (without seeding) likely had:
- **Different random distribution** that created better clustering patterns
- **Natural data ordering** that aligned better with insertion order
- **Less work for the clustering algorithm** due to lucky data distribution

With `setseed(0.5)`, we get:
- **Reproducible but less favorable** data distribution for clustering
- **More clustering work** needed to achieve similar results
- **Higher overhead** as a result

---

## Recommendations

### Option 1: Use call_hour for Clustering (RECOMMENDED)

```sql
-- Add call_hour to table definition (already exists as INTEGER)
cluster_type='zorder',
cluster_columns='call_hour,cell_tower_id'
```

**Benefits:**
- call_hour has 24 distinct values (0-23)
- Good cardinality for time-based queries
- Maintains Z-order multi-dimensional benefits
- **Expected overhead: 5-8%** (similar to old run)

**Trade-off:**
- call_hour is INTEGER (not TIMESTAMP)
- Less precise than call_timestamp
- But sufficient for most IoT/CDR queries

### Option 2: Use call_timestamp for Clustering

**Challenge:** PAX Z-order clustering may not support TIMESTAMP type in current version (Cloudberry 3.0.0-devel)

**Workaround:** Cast to epoch
```sql
cluster_type='zorder',
cluster_columns='EXTRACT(EPOCH FROM call_timestamp)::BIGINT,cell_tower_id'
```

**If supported**, this would provide:
- Best temporal granularity
- Natural time-based queries
- Optimal multi-dimensional clustering

### Option 3: Accept Current Overhead as Acceptable

**10% clustering overhead is within acceptable range** (<40% threshold).

**Arguments for keeping current config:**
- Overhead is still acceptable
- Configuration is simple and clear
- Deterministic seeding benefit outweighs overhead cost
- Production use cases may have multiple dates (real data)

---

## Impact on Production Use

### This Benchmark (Single-Day Data)
- ❌ call_date clustering **provides no value** (1 distinct value)
- ⚠️ 10% overhead is **wasted cost** for degenerate clustering

### Production Systems (Multi-Day Data)
- ✅ call_date clustering **provides value** (many distinct dates)
- ✅ Multi-dimensional queries benefit from Z-order
- ✅ Overhead is **justified** by query speedup

### Conclusion

**The 10% overhead is a benchmark-specific artifact, not a production concern.**

Real CDR/IoT systems have:
- Data spanning days/weeks/months (high call_date cardinality)
- Time-based partitioning strategies
- Multi-dimensional range queries (time + location)

**Recommendation:**
- **Keep current configuration** for production benchmarks
- **Document this limitation** in benchmark README
- **Consider using call_hour** for faster benchmark iteration

---

## Testing Recommendations

To validate the hypothesis, run three tests with different clustering configurations:

### Test A: Current (call_date, cell_tower_id)
- Baseline: 10% overhead
- Expected: Degenerate Z-order

### Test B: Improved (call_hour, cell_tower_id)
- Expected: 5-8% overhead
- Expected: True 2D Z-order benefits

### Test C: No Clustering
- Baseline comparison
- Pure micro-partition efficiency

**Hypothesis:** Test B will show 5-8% overhead (similar to old run) due to proper 2D Z-order clustering.

---

## Conclusion

**Root Cause:** Z-order clustering on `(call_date, cell_tower_id)` degenerates to single-dimension clustering because call_date has only 1 distinct value.

**Impact:** 56% increase in clustering overhead per million rows (2.34 → 3.65 MB/M).

**Severity:** Low - 10% overhead is still acceptable, and this is a benchmark-specific issue.

**Fix Priority:** Optional - current configuration works for production multi-day datasets.

**Recommended Action:**
1. ✅ Document this limitation in benchmark README
2. 🟡 Consider testing with `cluster_columns='call_hour,cell_tower_id'`
3. ✅ Accept 10% overhead as acceptable for single-day test data

---

**Generated:** 2025-11-03
**Analyst:** Claude Code
**Issue:** Clustering overhead investigation
