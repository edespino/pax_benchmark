# Known Limitations - Streaming INSERT Benchmark

This document tracks limitations discovered during benchmark development and execution.

---

## 1. TIMESTAMP Type Not Supported for Z-Order Clustering

**Discovered**: October 30, 2025
**Cloudberry Version**: 3.0.0-devel+dev.2154.gda0b9d4fe08
**Error**: `the type of column call_timestamp does not support zorder cluster (pax_access_handle.cc:1093)`

### Issue

PAX's Z-order clustering does not support TIMESTAMP columns in the current Cloudberry version. Attempting to use a TIMESTAMP column in `cluster_columns` results in table creation failure.

### Original Configuration (Failed)
```sql
CREATE TABLE cdr.cdr_pax (...) USING pax WITH (
    cluster_type='zorder',
    cluster_columns='call_timestamp,cell_tower_id',  -- ❌ TIMESTAMP not supported
    ...
);
```

### Workaround Applied
```sql
CREATE TABLE cdr.cdr_pax (...) USING pax WITH (
    cluster_type='zorder',
    cluster_columns='call_date,cell_tower_id',  -- ✅ DATE type works
    ...
);
```

### Impact

**Clustering Granularity**:
- **Original intent**: Cluster by timestamp (second-level precision) + cell_tower_id
- **Actual implementation**: Cluster by date (day-level precision) + cell_tower_id
- **Effect**: Coarser clustering than intended, but still provides multi-dimensional benefits

**Query Performance**:
- Queries filtering by exact timestamp: May scan entire day's data
- Queries filtering by date range: Should see full Z-order benefits
- Recommendation: Add `call_hour` to `minmax_columns` for finer-grained pruning within dates

**Storage Efficiency**:
- Clustering overhead may be slightly lower (fewer unique combinations)
- Data locality within day + tower still provides compression benefits

### Supported Types for Z-Order (Observed)

**Confirmed Working**:
- INTEGER
- BIGINT
- DATE
- TEXT/VARCHAR

**Confirmed NOT Working**:
- TIMESTAMP
- TIMESTAMPTZ

**Not Yet Tested**:
- NUMERIC
- FLOAT/REAL
- SMALLINT

### Recommendations

1. **For time-series data**: Use DATE + separate hour/minute columns
   ```sql
   cluster_columns='event_date,event_hour,location_id'
   minmax_columns='event_date,event_hour,event_minute,...'
   ```

2. **For high-precision timestamps**: Convert to BIGINT (epoch milliseconds)
   ```sql
   -- Add derived column
   timestamp_ms BIGINT GENERATED ALWAYS AS
       (EXTRACT(EPOCH FROM event_timestamp) * 1000) STORED

   -- Use in clustering
   cluster_columns='timestamp_ms,location_id'
   ```

3. **For this benchmark**: Current DATE-based approach is acceptable
   - Still tests Z-order clustering fundamentals
   - Still validates multi-dimensional performance
   - Documents real limitation for production users

### Future Work

- Test workaround #2 (BIGINT epoch timestamps) in separate benchmark
- File issue with Cloudberry team to add TIMESTAMP support
- Update PAX documentation to clarify supported types

---

## 2. Missing Heap Table Baseline

**Gap Identified**: November 1, 2025
**Impact**: Academic completeness, write speed baseline
**Severity**: LOW (by design, not a bug)
**Status**: Documented for future enhancement

### Issue

The benchmark tests 4 append-only storage variants (AO, AOCO, PAX, PAX-no-cluster) but omits standard PostgreSQL **Heap storage**. This creates a gap in the storage type spectrum tested.

**Current Coverage**:
- ✅ AO (row-oriented, compressed, append-only)
- ✅ AOCO (column-oriented, compressed, append-only)
- ✅ PAX (hybrid, compressed, append-only)
- ✅ PAX-no-cluster (control group)
- ❌ **Heap (standard PostgreSQL, NOT append-only)**

### Why Heap Matters

**1. True Write Speed Baseline**:
- Heap may have **fastest INSERT speed** (no compression overhead, simple page append)
- Current "baseline" is AO, but AO has compression cost
- Question: Is AO actually slow, or is Heap just impractical at scale?

**2. UPDATE/DELETE Performance Reference**:
- Heap excels at in-place updates (HOT optimization)
- AO/AOCO/PAX struggle with updates (append + visimap overhead)
- Benchmark is currently 100% INSERT-only, missing mutable workload testing

**3. Educational Value**:
- Demonstrates **why** append-only storage exists
- Shows Heap bloat and VACUUM challenges at scale
- Helps users understand storage type trade-offs

**4. Academic Completeness**:
- Research benchmarks should test full PostgreSQL range
- Missing Heap leaves gap in literature

### Heap vs Append-Only Trade-offs

| Aspect | Heap (Standard PostgreSQL) | AO/AOCO/PAX (Cloudberry) |
|--------|----------------------------|--------------------------|
| **INSERT Speed** | Potentially **fastest** (no compression) | Slower (compression overhead) |
| **Storage Efficiency** | **Worst** (no compression, 8KB pages) | **Best** (compressed, dense packing) |
| **UPDATE/DELETE** | **Fast** (in-place HOT) | **Slow** (append + visimap) |
| **Bloat** | **High** (dead tuples remain until VACUUM) | **Lower** (append-only semantics) |
| **VACUUM** | **Required frequently** (reclaim space) | Less critical (no in-place updates) |
| **Page Contention** | **Higher** (multiple transactions on same page) | **Lower** (append to new pages) |
| **Production Viability (50M rows)** | ❌ **NOT recommended** (bloat disaster) | ✅ **Designed for this** |
| **Best Use Case** | OLTP with frequent updates | OLAP with append-heavy workloads |

### Why Currently Excluded

**Design Decision - Not an Oversight**:

1. **Not Production-Viable for 50M Rows**:
   - Heap at this scale = catastrophic table bloat
   - Requires aggressive VACUUM (expensive, blocks access)
   - Page-level locking contention on hot pages
   - Cloudberry users would **never** choose Heap for data warehousing

2. **Benchmark Focus Mismatch**:
   - Benchmark designed for **streaming INSERT** workloads
   - Heap designed for **transactional UPDATE** workloads
   - Comparing apples to oranges

3. **Misleading Results Potential**:
   - Heap might show "fastest INSERT" initially
   - But catastrophic storage/VACUUM costs later
   - Users might misinterpret as recommended option

4. **Runtime Impact**:
   - 5th variant adds +20-30% execution time
   - More complex to maintain
   - Testing infrastructure not designed for Heap-specific issues

5. **Cloudberry Best Practices**:
   - Documentation assumes AO/AOCO as baseline for large tables
   - Heap only recommended for small tables (<threshold)
   - Benchmark aligns with production recommendations

### Impact Assessment

**What We're Missing**:
- Empirical data on Heap INSERT speed at scale
- Heap bloat behavior with continuous streaming load
- VACUUM overhead measurements
- UPDATE/DELETE performance comparison

**What We Have**:
- Complete append-only storage comparison (the actual production choice)
- Scientifically sound PAX evaluation
- Realistic production-like testing

**Severity**: **LOW** - Missing data is academic, not critical for PAX evaluation

### Recommendation for Future Enhancement

**If Heap testing is desired**, implement as **optional 5th variant**:

#### Implementation Approach

**1. Add Heap Variant** (sql/04_create_variants.sql):
```sql
-- =====================================================
-- Variant 5: Heap (OPTIONAL - NOT RECOMMENDED FOR PRODUCTION)
-- For academic comparison only
-- =====================================================

\echo 'Creating Variant 5: Heap (PostgreSQL standard storage)...'
\echo '⚠️  WARNING: Heap not recommended for 50M+ rows'
\echo '⚠️  This variant for comparison purposes only'
\echo ''

CREATE TABLE cdr.cdr_heap (
    call_id TEXT,
    call_timestamp TIMESTAMP,
    -- ... same schema as other variants
) DISTRIBUTED BY (call_id);
-- NO WITH clause = Heap storage (default PostgreSQL)

\echo '  ✓ cdr.cdr_heap created (Heap - standard PostgreSQL)'
\echo '  ⚠️  Expect table bloat and slow performance at scale'
\echo ''
```

**2. Add Script Flag**:
```bash
# Python version
./scripts/run_streaming_benchmark.py --include-heap

# Bash version
./scripts/run_streaming_benchmark.sh --include-heap
```

**3. Update Documentation**:
- README.md: Explain Heap trade-offs and flag usage
- Metrics: Flag Heap bloat as expected (not failure)
- Warnings: Clear "NOT FOR PRODUCTION" notices

**4. Validation Adjustments**:
- Gate 2 (bloat check): Heap expected to be worst (don't fail)
- Gate 3 (throughput): Heap may be fastest (document)
- New Gate 5 (Heap-specific): VACUUM overhead, bloat ratio

#### Estimated Effort

- Core implementation (SQL + scripts): 4-5 hours
- Testing (test run + production run): 2-3 hours
- Documentation updates: 1 hour
- **Total: 1 working day**

#### Benefits

- ✅ Complete PostgreSQL storage spectrum
- ✅ True write speed baseline
- ✅ Educational value for users
- ✅ Backward compatible (opt-in flag)
- ✅ Academic rigor

#### Risks

- ⚠️ Users may misinterpret Heap as viable option
- ⚠️ Runtime increase (5 variants vs 4)
- ⚠️ Maintenance complexity

### Workaround (Manual Heap Testing)

Users who want Heap comparison can manually add it:

```bash
# 1. Create Heap table
psql -c "CREATE TABLE cdr.cdr_heap (LIKE cdr.cdr_ao) DISTRIBUTED BY (call_id);"

# 2. Run INSERT workload manually
psql -c "INSERT INTO cdr.cdr_heap SELECT * FROM cdr.generate_cdr_batch(...);"

# 3. Measure storage
psql -c "SELECT pg_size_pretty(pg_total_relation_size('cdr.cdr_heap'));"

# 4. Observe bloat
psql -c "VACUUM VERBOSE cdr.cdr_heap;"
```

**Expected Results** (extrapolated from similar tests):
- INSERT speed: 10-20% faster than AO (no compression)
- Storage: 2-3x larger than AO (no compression)
- Bloat: Significant after 50M rows (dead tuples accumulate)
- VACUUM: Required, expensive (minutes to hours)

### Related Gaps

While documenting the Heap gap, other testing gaps were identified:

**HIGH Priority** (production-relevant):
- UPDATE/DELETE performance (benchmark is INSERT-only)
- Concurrent workloads (readers during writes)
- Table partitioning (single 50M table vs daily partitions)

**MEDIUM Priority**:
- VACUUM overhead measurement
- Index type comparison (B-tree vs Bitmap vs GIN)
- Long-term behavior (24+ hour sustained load)

**LOW Priority**:
- Failure recovery testing
- Network profiling (segment-level analysis)
- External data ingestion (COPY, foreign tables)

These may warrant separate benchmark enhancements or documentation.

---

## 3. Other Limitations (To Be Documented)

### Placeholder for Future Discoveries

As the benchmark executes and is tested in different environments, additional limitations may be discovered and documented here.

---

**Last Updated**: November 1, 2025
**Benchmark Version**: Phase 2 (PROCEDURE implementation)
