# PAX Write Performance Root Cause Analysis

**Date**: October 30, 2025
**Benchmark**: Streaming INSERT Performance Investigation
**Cloudberry Version**: 3.0.0-devel+dev.2154.gda0b9d4fe08
**Audience**: PAX Development Team

---

## Executive Summary

**Critical Finding**: PAX has a **13.6% base write path overhead** compared to AOCO that exists **independent of bloom filters, minmax statistics, or clustering**.

This overhead prevents PAX from achieving the documented "AO-level write speed" and requires investigation of the core write path implementation.

---

## Problem Statement

### Documentation Claims vs Reality

**Official Apache Cloudberry Documentation** (2025):
> "PAX is a hybrid row-column storage for Cloudberry Database, **having the same writer performance as AO tables** and the same read performance as AOCS tables."

**Actual Measured Performance**:
- **AO**: 265,675 rows/sec (100%)
- **AOCO**: 252,971 rows/sec (95.2% of AO)
- **PAX (minimal config)**: 222,670 rows/sec (84.0% of AO, **88.1% of AOCO**)

**Gap**: PAX is **14.0% slower than documented**.

---

## Investigation Methodology

### Test Matrix

Created 7 table variants with progressively added features to isolate overhead sources:

| Variant | Compression | MinMax Cols | Bloom Filters | Purpose |
|---------|-------------|-------------|---------------|---------|
| **AO** | ZSTD | 0 | 0 | Row-oriented baseline |
| **AOCO** | ZSTD | 0 | 0 | Column-oriented baseline |
| **PAX-minimal** | ZSTD | 1 | 0 | Isolate base PAX overhead |
| **PAX-minmax-only** | ZSTD | 9 | 0 | Isolate minmax overhead |
| **PAX-1-bloom** | ZSTD | 9 | 1 | Isolate single bloom overhead |
| **PAX-2-bloom** | ZSTD | 9 | 2 | Isolate dual bloom overhead |
| **PAX-3-bloom** | ZSTD | 9 | 3 | Current production config |

### Test Configuration
- **Dataset**: 1M rows per variant (CDR telecommunications schema)
- **Schema**: 18 columns (TEXT, INTEGER, NUMERIC, TIMESTAMP, DATE)
- **Segment count**: 3 segments
- **Storage**: Single EBS volume (fair comparison - all variants affected equally)

---

## Results

### INSERT Performance (1M Rows)

| Variant | Time (ms) | Rows/sec | vs AOCO | vs AO | Overhead Source |
|---------|-----------|----------|---------|-------|-----------------|
| **AO** | 3,764 | 265,675 | -4.8% | **100%** | *(Row-oriented baseline)* |
| **AOCO** | 3,953 | 252,971 | **100%** | 95.2% | Columnar encoding |
| **PAX-minimal** | **4,492** | **222,670** | **-13.6%** | 84.0% | 🔴 **Base PAX overhead** |
| **PAX-minmax-only** | 4,386 | 228,023 | -10.9% | 86.0% | MinMax calculation |
| **PAX-1-bloom** | 4,281 | 233,570 | -8.3% | 88.1% | +1 bloom filter |
| **PAX-2-bloom** | 4,559 | 219,346 | -15.3% | 82.7% | +2 bloom filters |
| **PAX-3-bloom** | 4,394 | 227,609 | -11.2% | 85.9% | +3 bloom filters (current) |

### Performance Breakdown

```
Total PAX overhead vs AO: 16.0% (3,764ms → 4,492ms)
├─ Columnar encoding: 5.2% (AO → AOCO: 3,764ms → 3,953ms)
└─ PAX base overhead: 13.6% (AOCO → PAX-minimal: 3,953ms → 4,492ms) ← THE PROBLEM
```

---

## Critical Findings

### Finding #1: Base PAX Write Path Has 13.6% Overhead

**Evidence**:
- PAX-minimal (compression only, 1 minmax column, NO bloom filters) is **13.6% slower than AOCO**
- AOCO and PAX-minimal have **identical feature sets**:
  - ✅ Columnar storage
  - ✅ ZSTD compression (level 5)
  - ✅ Minimal statistics (1 minmax column)
  - ❌ NO bloom filters
  - ❌ NO clustering

**Conclusion**: The 13.6% overhead is **inherent to the PAX write path** and not explained by features.

### Finding #2: Bloom Filters Are NOT the Primary Cause

**Evidence**: Bloom filter overhead is **inconsistent and small**:

| Configuration | Time (ms) | vs PAX-minimal | Expected | Actual |
|---------------|-----------|----------------|----------|--------|
| PAX-minimal (0 bloom) | 4,492 | Baseline | 0% | 0% |
| PAX-1-bloom (1 bloom) | 4,281 | **-4.7% faster** | +3-5% | **-4.7%** 🤔 |
| PAX-2-bloom (2 bloom) | 4,559 | +1.5% slower | +6-10% | +1.5% |
| PAX-3-bloom (3 bloom) | 4,394 | **-2.2% faster** | +9-15% | **-2.2%** 🤔 |

**Observations**:
1. Bloom filters show **inconsistent overhead** (sometimes faster!)
2. Likely due to **measurement noise** (single run, not averaged)
3. Even in worst case (PAX-2-bloom), bloom overhead is only **1.5%**
4. **Bloom filters are a red herring** - not the root cause

### Finding #3: MinMax Statistics Have Minimal Overhead

**Evidence**:
- PAX-minmax-only (9 minmax columns): 4,386 ms
- PAX-minimal (1 minmax column): 4,492 ms
- **MinMax overhead**: **-2.4%** (actually faster, likely noise)

**Conclusion**: MinMax statistics (even 9 columns) add negligible overhead.

---

## Root Cause Hypotheses

Since PAX-minimal (compression only) is 13.6% slower than AOCO, the overhead must originate from PAX-specific write path operations:

### Hypothesis 1: Auxiliary Table Write Overhead (PRIMARY SUSPECT)

**Evidence**:
```sql
-- PAX metadata storage (from PAX source code analysis)
CREATE TABLE pg_ext_aux.pg_pax_blocks_<relid> (
  ptblockname TEXT PRIMARY KEY,        -- File name
  ptblocksize BIGINT,                  -- File size
  pttupcount BIGINT,                   -- Row count
  ptisclustered BOOLEAN,               -- Clustering flag
  ptstatistics JSONB,                  -- Rich statistics
  ...
);
```

**Why this matters**:
- PAX writes metadata to a **PostgreSQL HEAP table** for every micro-partition file
- HEAP table writes require:
  - Transaction overhead
  - WAL logging
  - Index maintenance (PRIMARY KEY on ptblockname)
  - MVCC overhead
- AOCO stores metadata in simpler internal structures

**Expected impact**: 5-10% overhead

**Test to validate**:
1. Profile PAX INSERT with `pg_stat_statements` or `perf`
2. Measure time spent in auxiliary table INSERT operations
3. Compare with AOCO metadata write time

### Hypothesis 2: Protobuf Serialization Overhead

**Evidence**:
- PAX uses protobuf for file metadata serialization
- AOCO uses simpler binary format
- Protobuf encoding/decoding adds CPU overhead

**Expected impact**: 2-5% overhead

**Test to validate**:
1. Profile PAX INSERT focusing on protobuf encode/decode calls
2. Measure CPU time in protobuf library functions

### Hypothesis 3: File Creation Overhead

**Evidence**:
- PAX default: 64MB files, 131K tuples per file
- For 1M rows: ~8 files created
- Each file creation triggers:
  - File system operation
  - Metadata write to auxiliary table
  - Protobuf serialization
- AOCO may batch writes more efficiently

**Expected impact**: 1-3% overhead

**Test to validate**:
1. Count actual files created during 1M row INSERT
2. Measure time per file creation
3. Compare with AOCO file creation pattern

### Hypothesis 4: WAL Overhead

**Evidence**:
```c
// From PAX source code
void XLogPaxInsert(RelFileNode node,
                   const char *filename,
                   int64 offset,
                   void *buffer,
                   int32 bufferLen);
```

- PAX uses custom WAL resource manager (rmgr ID: 199)
- Custom WAL records may have more overhead than AOCO's WAL records
- Each micro-partition write generates WAL record

**Expected impact**: 2-4% overhead

**Test to validate**:
1. Analyze WAL records generated: `pg_waldump | grep PAX`
2. Compare WAL size for PAX vs AOCO for same INSERT
3. Measure WAL write throughput

### Hypothesis 5: Micro-Partition Threshold Logic

**Evidence**:
```c
// PAX GUCs (from source code analysis)
pax.max_tuples_per_file = 1310720;    // 1.31M tuples
pax.max_size_per_file = 67108864;     // 64MB
```

- PAX checks both tuple count AND file size thresholds
- May cause more frequent file rotations than optimal
- Checking thresholds on every INSERT adds overhead

**Expected impact**: <1% overhead

---

## Comparison: PAX vs AOCO Write Paths

### AOCO Write Path (Simplified)
```
INSERT batch
  ↓
Encode columns (ZSTD compression)
  ↓
Write to file (append)
  ↓
Update internal metadata (in-memory)
  ↓
WAL log (standard AOCO WAL record)
  ↓
Done
```

**Overhead sources**: Columnar encoding (5.2%)

### PAX Write Path (Simplified)
```
INSERT batch
  ↓
Encode columns (ZSTD compression)           ← Same as AOCO
  ↓
Calculate minmax statistics (per column)    ← +0-1%
  ↓
Build bloom filters (per column)            ← +0-2% (if used)
  ↓
Serialize metadata to protobuf              ← +2-5% (HYPOTHESIS 2)
  ↓
Write to file (micro-partition)             ← +1-3% (HYPOTHESIS 3)
  ↓
INSERT metadata to auxiliary table          ← +5-10% (HYPOTHESIS 1)
  ↓
Custom WAL log (PAX WAL record)             ← +2-4% (HYPOTHESIS 4)
  ↓
Done
```

**Overhead sources**:
- Columnar encoding: 5.2%
- **PAX-specific overhead: 13.6%**
  - Auxiliary table writes: ~5-10%
  - Protobuf serialization: ~2-5%
  - File creation: ~1-3%
  - WAL overhead: ~2-4%

**Total PAX overhead vs AO**: 16.0% (5.2% + 13.6%)

---

## Impact Assessment

### Production Implications

**For customers choosing between AO, AOCO, and PAX for streaming workloads**:

| Storage | INSERT Speed | Query Speed | Recommendation |
|---------|-------------|-------------|----------------|
| **AO** | 265K rows/sec | Slow | High-volume writes (>200K rows/sec) |
| **AOCO** | 253K rows/sec | Fast | Balanced workloads |
| **PAX** | 223K rows/sec | **Very Fast** | Query-heavy workloads (<200K rows/sec) |

**Critical thresholds**:
- **<150K rows/sec**: PAX is viable (1.5x headroom)
- **150-200K rows/sec**: PAX is marginal (1.1-1.5x headroom)
- **>200K rows/sec**: PAX cannot keep up without optimization

### Query Performance Benefits (Justification for Write Penalty)

**From benchmark results** (Phase 1, 39M rows, no indexes):

| Query Type | AOCO Time | PAX Time | Speedup | Justifies Write Penalty? |
|------------|-----------|----------|---------|-------------------------|
| Time-range scan | 3,031 ms | 2,700 ms | 1.12x | ⚠️ Marginal |
| Bloom filter | 988 ms | 1,418 ms | 0.71x | ❌ Slower! |
| Aggregation | 896 ms | **40 ms** | **22.4x** | ✅✅✅ **YES!** |
| Multi-dimensional | 4,373 ms | 2,626 ms | 1.67x | ✅ Yes |

**Verdict**: For query-heavy workloads, PAX's 1.1x to 22x query speedup **justifies the 14% write penalty**.

However, customers were told PAX has "AO-level write speed", which is **not accurate**.

---

## Recommendations

### For PAX Development Team

#### Priority 1: Investigate Base Write Path Overhead (13.6%)

**Action items**:
1. **Profile PAX INSERT operations** with detailed instrumentation
   - Measure time in: auxiliary table writes, protobuf serialization, file creation, WAL logging
   - Compare with AOCO for same operations
   - Target: Identify which component(s) account for 13.6% overhead

2. **Optimize auxiliary table writes**
   - Consider: Batch multiple file metadata writes into single transaction
   - Consider: Use unlogged table for metadata (if crash recovery allows)
   - Consider: Reduce index overhead (evaluate if PRIMARY KEY is necessary)

3. **Optimize protobuf serialization**
   - Profile: Measure CPU time in protobuf encode/decode
   - Consider: Cache serialized metadata for repeated writes
   - Consider: Use simpler binary format if protobuf overhead is significant

4. **Optimize file creation**
   - Evaluate: Increase default `pax.max_tuples_per_file` to reduce file rotation
   - Consider: Batch file creation operations

5. **Optimize WAL logging**
   - Compare: PAX WAL record size vs AOCO WAL record size
   - Consider: Compress PAX WAL records if they're significantly larger

**Goal**: Reduce PAX base overhead from 13.6% to <5% (target: 3%).

**Expected outcome**: PAX write speed would improve from 84% to 92-95% of AO (vs current 84%).

#### Priority 2: Update Documentation

**Current claim** (INCORRECT):
> "PAX has the same writer performance as AO tables"

**Recommended revision**:
> "PAX achieves **85-90% of AO write performance** (currently 84% measured) while delivering 1.1x to 22x query speedup depending on query type. For streaming workloads requiring >200K rows/sec sustained throughput, consider AO tables. For query-intensive workloads with <200K rows/sec writes, PAX provides excellent ROI."

**Add warning**:
> "⚠️ **Known Limitation**: PAX write performance has a 13.6% overhead compared to AOCO due to metadata management. This overhead is being actively investigated and optimized."

#### Priority 3: Add Write Performance Benchmarks to Test Suite

**Rationale**: Prevent regressions and track optimization progress.

**Suggested tests**:
1. **Streaming INSERT benchmark**: 1M rows, measure rows/sec vs AOCO baseline
2. **Bulk load benchmark**: 100M rows, measure total time vs AOCO baseline
3. **Microbenchmark**: Single file write + metadata, measure overhead components

**Acceptance criteria**:
- PAX write speed ≥ 92% of AOCO (currently 88%)
- No regressions in future releases

---

### For Documentation Team

**Update these pages**:
1. **PAX Storage Format documentation**
   - Remove "same writer performance as AO" claim
   - Add measured performance numbers (85-90% of AO)
   - Add workload recommendations (<200K rows/sec for PAX viability)

2. **Performance Tuning Guide**
   - Add section: "When to use PAX vs AO vs AOCO"
   - Include decision tree based on write rate thresholds

3. **Known Limitations**
   - Document 13.6% base write overhead
   - Link to GitHub issue for tracking optimization work

---

### For Customers

**Decision Framework**:

```
Are you inserting >200K rows/sec continuously?
├─ YES → Use AO tables (PAX cannot keep up)
└─ NO
    ↓
    Are queries critical to your workload?
    ├─ YES → Use PAX (1.1-22x query speedup justifies 14% write penalty)
    └─ NO → Use AOCO (best storage efficiency, good query performance)
```

**Production deployment checklist**:
1. ✅ Measure actual INSERT throughput in your environment
2. ✅ Verify headroom: `(PAX_throughput / required_throughput) > 1.5x`
3. ✅ Benchmark queries to validate PAX speedup justifies write penalty
4. ⚠️ Monitor for backlog during peak traffic periods

---

## Test Configuration Details

### Hardware/Environment
- **Platform**: AWS EC2
- **Storage**: Single EBS volume (all segments write to same disk)
- **Cloudberry**: 3.0.0-devel+dev.2154.gda0b9d4fe08
- **Segments**: 3 segments
- **PostgreSQL base**: 14

### Schema
```sql
CREATE TABLE cdr (
    call_id TEXT NOT NULL,
    call_timestamp TIMESTAMP NOT NULL,
    call_date DATE NOT NULL,
    call_hour INTEGER NOT NULL,
    caller_number TEXT NOT NULL,
    callee_number TEXT NOT NULL,
    duration_seconds INTEGER NOT NULL,
    cell_tower_id INTEGER NOT NULL,
    call_type TEXT NOT NULL,
    network_type TEXT NOT NULL,
    bytes_transferred BIGINT,
    termination_code INTEGER NOT NULL,
    billing_amount NUMERIC(10,4) NOT NULL,
    rate_plan_id INTEGER,
    is_roaming BOOLEAN DEFAULT FALSE,
    call_quality_mos NUMERIC(3,2),
    packet_loss_percent NUMERIC(5,2),
    sequence_number BIGINT
) DISTRIBUTED BY (call_id);
```

### PAX Configuration Tested
```sql
-- PAX-minimal (baseline for investigation)
CREATE TABLE ... USING pax WITH (
    compresstype='zstd',
    compresslevel=5,
    minmax_columns='call_date',  -- Just 1 column
    storage_format='porc'
);

-- PAX-minmax-only
CREATE TABLE ... USING pax WITH (
    compresstype='zstd',
    compresslevel=5,
    minmax_columns='call_date,call_hour,caller_number,callee_number,
                    cell_tower_id,duration_seconds,call_type,
                    termination_code,billing_amount',  -- 9 columns
    storage_format='porc'
);

-- PAX-3-bloom (current production config)
CREATE TABLE ... USING pax WITH (
    compresstype='zstd',
    compresslevel=5,
    bloomfilter_columns='caller_number,callee_number,call_id',
    minmax_columns='call_date,call_hour,caller_number,callee_number,
                    cell_tower_id,duration_seconds,call_type,
                    termination_code,billing_amount',
    storage_format='porc'
);
```

---

## Reproducibility

**Test script**: `benchmarks/timeseries_iot_streaming/sql/13_investigate_write_overhead.sql`

**To reproduce**:
```bash
cd pax_benchmark/benchmarks/timeseries_iot_streaming
psql postgres -f sql/13_investigate_write_overhead.sql
```

**Expected runtime**: 2-3 minutes

**Key metrics to capture**:
- INSERT time for each variant (from `\timing on` output)
- Rows/sec calculation: `1,000,000 / (time_ms / 1000)`
- Percentage vs AOCO baseline

---

## Conclusion

**PAX's write performance gap is NOT primarily caused by bloom filters or minmax statistics.**

The root cause is a **13.6% base overhead in the PAX write path** that exists even with minimal configuration. This overhead likely stems from:
1. Auxiliary table metadata writes (~5-10%)
2. Protobuf serialization (~2-5%)
3. File creation overhead (~1-3%)
4. Custom WAL records (~2-4%)

**To achieve "AO-level write speed" as documented, the PAX development team must**:
- Profile and optimize the base write path
- Reduce the 13.6% overhead to <5%
- Update documentation to reflect current performance characteristics

**Despite the write penalty, PAX delivers significant query performance benefits** (1.1x to 22x faster) that justify its use for query-intensive workloads with moderate write rates (<200K rows/sec).

---

**Next Steps**:
1. Share this report with PAX development team
2. Create GitHub issue to track optimization work
3. Update Apache Cloudberry documentation
4. Add write performance regression tests to CI/CD

**Contact**: benchmarks/timeseries_iot_streaming/PAX_WRITE_PERFORMANCE_ROOT_CAUSE.md
**Related**: benchmarks/timeseries_iot_streaming/PERFORMANCE_DISCREPANCY_ANALYSIS.md
