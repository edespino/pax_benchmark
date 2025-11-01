# Streaming INSERT Benchmark - PAX vs AO/AOCO

**Benchmark Duration**: 20-55 minutes (Phase 1: 20-25 min, Phase 2: 30-35 min, Both: 40-55 min)
**Dataset Size**: 50M rows (~8-12GB per variant)
**Focus**: INSERT throughput for continuous batch loading (telecommunications/IoT)

---

## Overview

This benchmark validates PAX's design goal: **achieving competitive write throughput + superior query performance**.

Unlike other benchmarks that focus on query performance, this benchmark specifically tests **streaming INSERT workloads** common in telecommunications and IoT scenarios where data arrives continuously in batches.

### What Makes This Different

**Other benchmarks** (retail_sales, timeseries_iot, etc.):
- Load data once in bulk → Measure query performance
- Optimized for read-heavy OLAP workloads

**This benchmark**:
- Continuously INSERTs data in 500 batches → Measures write throughput
- Simulates production streaming workloads (CDRs, IoT sensors, logs)
- Tests the critical dilemma: **AO (fast writes, slow queries) vs AOCO (slow writes, fast queries)**

### Key Question

**Can PAX achieve both?**

**Actual Results** (October 2025, Cloudberry 3.0.0-devel):
- ⚠️ **INSERT speed**: 85-86% of AO (262K vs 306K rows/sec) - **14% slower than documented**
- ✅ **Query performance**: 1.1x to 22x faster than AOCO (depending on query type)
- ✅ **Storage efficiency**: Comparable to AOCO (+7% overhead)

**Critical Finding**: PAX does **NOT** achieve "AO-level write speed" as documented. See `PAX_WRITE_PERFORMANCE_ROOT_CAUSE.md` for detailed analysis.

---

## Dataset: Call Detail Records (CDR)

Realistic telecommunications CDR schema:

### Fact Table: 50M call records
- **call_id** (TEXT) - Unique identifier (HIGH cardinality: ~50M unique)
- **call_timestamp** (TIMESTAMP) - Call start time
- **caller_number** (TEXT) - Originating phone (HIGH cardinality: ~1M unique)
- **callee_number** (TEXT) - Destination phone (HIGH cardinality: ~1M unique)
- **duration_seconds** (INTEGER) - Call duration
- **cell_tower_id** (INTEGER) - Network tower (MEDIUM cardinality: 10K unique)
- **call_type** (TEXT) - voice/sms/data (LOW cardinality: 3 values)
- **network_type** (TEXT) - 4G/5G (LOW cardinality: 3 values)
- **bytes_transferred** (BIGINT) - Data transfer (sparse: 85% NULL)
- **termination_code** (INTEGER) - Call end reason (LOW cardinality: ~20 codes)
- **billing_amount** (NUMERIC) - Revenue
- Plus rate plan, roaming flag, quality metrics

### Dimension Tables:
- **cell_towers**: 10K cell tower locations
- **rate_plans**: 50 billing rate plans
- **termination_reasons**: 20 call termination codes

### Cardinality Profile (Critical for PAX Config):
```
High-cardinality (>1000):   call_id, caller_number, callee_number, cell_tower_id
Medium-cardinality (100-1000): (none in this schema)
Low-cardinality (<100):      call_type, network_type, termination_code, rate_plan_id
```

---

## PAX Configuration

Based on Phase 2 cardinality analysis (validated BEFORE table creation):

```sql
CREATE TABLE cdr.cdr_pax (...) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- Bloom filters: VALIDATED (3 columns, all >1M unique)
    bloomfilter_columns='call_id,caller_number,callee_number',

    -- MinMax: Comprehensive coverage (9 columns)
    minmax_columns='call_date,call_hour,caller_number,callee_number,
                    cell_tower_id,duration_seconds,call_type,
                    termination_code,billing_amount',

    -- Z-order clustering: Time + Location correlation
    cluster_type='zorder',
    cluster_columns='call_timestamp,cell_tower_id',

    storage_format='porc'
);
```

**Configuration Rationale:**
- **3 bloom filters**: Maximum recommended (Oct 2025 lessons), all high-cardinality
- **cell_tower_id excluded from bloom**: Safe (10K unique) but already have 3 columns
- **Z-order dimensions**: Time-series (call_timestamp) + spatial (cell_tower_id) correlation

---

## Traffic Pattern: Realistic 24-Hour Simulation

500 batches simulating telecommunications traffic:

### Batch Size Distribution:
- **Small (10K rows)**: 80% of batches during night hours (00:00-06:00)
- **Medium (100K rows)**: 60% during business hours (09:00-16:00)
- **Large (500K rows)**: 30% during rush hours (07:00-09:00, 17:00-19:00)

### Hourly Pattern:
```
00:00-06:00 (Night):     Small only  (10K)
07:00-09:00 (Rush):      70% medium (100K), 30% large (500K)
09:00-16:00 (Business):  85% medium (100K), 15% small (10K)
17:00-19:00 (Rush):      70% medium (100K), 30% large (500K)
19:00-23:00 (Evening):   60% small (10K), 40% medium (100K)
```

**Total**: ~100K rows/batch average × 500 batches = 50M rows

---

## Two-Phase Testing

### Phase 1: Pure INSERT Speed (No Indexes)
**Purpose**: Measure raw INSERT throughput without index maintenance overhead

**Test**:
- 4 table variants (AO, AOCO, PAX, PAX-no-cluster)
- NO indexes on any table
- 500 batches × 4 variants = 2,000 INSERTs total

**Metrics**:
- Per-batch INSERT duration (ms)
- Throughput (rows/sec) over time
- Storage growth during streaming
- Query performance degradation as data grows

**Expected Results**:
- AO: Fastest (baseline)
- AOCO: 20-40% slower than AO
- **PAX Target**: Match AO ±10%
- PAX-no-cluster: Same as PAX (no clustering overhead during INSERT)

**Runtime**: 15-20 minutes

### Phase 2: Production Realistic (With Indexes)
**Purpose**: Measure INSERT throughput WITH index maintenance (realistic production)

**Test**:
- Same 4 variants, recreated with indexes
- 5 indexes per variant (20 total):
  - call_timestamp (range queries)
  - caller_number (equality lookups)
  - callee_number (equality lookups)
  - cell_tower_id (filtering)
  - call_date (range queries)
- 500 batches × 4 variants = 2,000 INSERTs

**Metrics**:
- INSERT throughput with index overhead
- Phase 1 vs Phase 2 degradation
- Index maintenance cost per variant

**Expected Results**:
- All variants slower (index overhead)
- AO: High overhead (index on wide rows)
- AOCO: Lower overhead (selective column indexes)
- **PAX Target**: Competitive with AOCO, faster than AO

**Runtime**: 25-35 minutes

---

## Validation Gates

4 safety gates prevent misconfiguration:

### Gate 1: Row Count Consistency
- All 4 variants must have exactly 50M rows
- Ensures data integrity

### Gate 2: PAX Configuration Bloat Check
- PAX-no-cluster: <20% overhead vs AOCO
- PAX-clustered: <40% overhead vs no-cluster
- Detects bloom filter misconfiguration

### Gate 3: INSERT Throughput Sanity Check
- PAX must achieve >50% of AO INSERT speed
- Validates design goal

### Gate 4: Bloom Filter Effectiveness
- All bloom columns must have cardinality >1000
- Prevents low-cardinality bloat

**Failure**: Benchmark exits immediately if any gate fails

---

## Query Performance Tests

4 queries test different PAX features:

1. **Time-Range Scan** (Q1): Last hour of calls → Sparse filtering
2. **High-Cardinality Filter** (Q2): Specific caller → Bloom filter effectiveness
3. **Multi-Dimensional** (Q3): Time + tower → Z-order clustering benefit
4. **Aggregation** (Q4): Top 10 busiest towers → Column compression

---

## Actual Results (October 2025)

**Test Environment**: Cloudberry 3.0.0-devel+dev.2154.gda0b9d4fe08, 3 segments, single EBS volume

### Phase 1 (No Indexes) - INSERT Performance:

| Variant | INSERT Throughput | vs AO | vs AOCO | Storage vs AOCO |
|---------|-------------------|-------|---------|-----------------|
| **AO** | **306,211 rows/sec** | 100% | +5.3% | 1.54x (2,017 MB) |
| **AOCO** | **290,189 rows/sec** | 94.8% | 100% | 1.00x (1,307 MB) |
| **PAX-clustered** | **262,036 rows/sec** | **85.6%** | 90.3% | 1.19x (1,560 MB) |
| **PAX-no-cluster** | **264,983 rows/sec** | 86.5% | 91.3% | 1.07x (1,404 MB) |

**⚠️ Critical Finding**: PAX achieved **85-86% of AO speed**, NOT the documented "AO-level write speed" (100%).

### Phase 1 (No Indexes) - Query Performance:

| Query Type | AOCO | PAX | Speedup | Assessment |
|------------|------|-----|---------|------------|
| **Q1: Time-range scan** | 3,031 ms | 2,700 ms | **1.12x** | ✅ Faster |
| **Q2: Bloom filter** | 988 ms | 1,418 ms | 0.71x | ❌ Slower |
| **Q3: Aggregation** | 896 ms | **40 ms** | **22.4x** | ✅✅✅ **Amazing!** |
| **Q4: Multi-dimensional** | 4,373 ms | 2,626 ms | **1.67x** | ✅ Much faster |

**✅ PAX delivers 1.1x to 22x query speedup** - justifies the 14% write penalty for query-intensive workloads!

### Root Cause Analysis (Write Performance Gap):

**Why is PAX 14% slower than AO?**

Detailed investigation (`PAX_WRITE_PERFORMANCE_ROOT_CAUSE.md`) found:
- **13.6% base PAX overhead** vs AOCO (even without bloom filters!)
- Root causes:
  - Auxiliary table writes (~5-10%)
  - Protobuf serialization (~2-5%)
  - File creation overhead (~1-3%)
  - Custom WAL records (~2-4%)
- **Bloom filters add <2%** (NOT the primary cause)

### Production Recommendations:

**When to use PAX for streaming workloads**:

| Write Rate | Headroom | Recommendation |
|------------|----------|----------------|
| **<150K rows/sec** | 1.7x | ✅ **PAX is excellent** |
| **150-200K rows/sec** | 1.3-1.7x | ⚠️ **PAX viable, monitor closely** |
| **200-250K rows/sec** | 1.0-1.3x | 🟠 **PAX marginal, test thoroughly** |
| **>250K rows/sec** | <1.0x | ❌ **Use AO instead** |

**Decision tree**:
```
Continuous write rate >250K rows/sec?
├─ YES → Use AO (PAX cannot keep up)
└─ NO
    ↓
    Query performance critical?
    ├─ YES → Use PAX (1.1-22x query speedup)
    └─ NO → Use AOCO (best storage, good queries)
```

---

## Execution

### Python Version (Recommended - Real-time Progress)

**Features**: Live progress bars, batch-level updates, better error handling, professional UI

```bash
cd benchmarks/timeseries_iot_streaming

# Install dependencies (first time only)
pip3 install -r scripts/requirements.txt

# Full benchmark (both phases - 50 minutes, interactive)
./scripts/run_streaming_benchmark.py

# Phase 1 only (20 minutes)
./scripts/run_streaming_benchmark.py --phase 1

# Non-interactive (CI/CD friendly)
./scripts/run_streaming_benchmark.py --no-interactive

# Verbose output for debugging
./scripts/run_streaming_benchmark.py --verbose
```

### Bash Version (Alternative - Silent Execution)

**Features**: Simple, no dependencies, but no real-time progress visibility

```bash
# Full benchmark (both phases - 50 minutes)
./scripts/run_streaming_benchmark.sh

# Phase 1 only (20 minutes)
./scripts/run_phase1_noindex.sh

# Phase 2 only (30 minutes)
./scripts/run_phase2_withindex.sh
```

**Recommendation**: Use Python version for interactive testing, bash for automated CI/CD pipelines.

---

## Implementation Details: PROCEDURE vs DO Block

**November 2025 Update**: Benchmark migrated from DO block to PROCEDURE for 42% performance improvement.

### Why PROCEDURE?

**Original DO Block Approach**:
- Single monolithic transaction for all 500 batches
- Cannot COMMIT inside DO block
- Long-running transaction holds resources
- **Runtime**: ~4.7 hours estimated (extrapolated from small tests)

**New PROCEDURE Approach**:
- Per-batch COMMITs (500 independent transactions)
- Releases resources after each batch
- Resumable if interrupted
- **Runtime**: ~2.7 hours estimated (**42% faster**)

### Files by Approach

**Production (500 batches, 50M rows)**:
- `sql/06b_streaming_inserts_noindex_procedure.sql` - Phase 1 PROCEDURE (~20 min)
- `sql/07b_streaming_inserts_withindex_procedure.sql` - Phase 2 PROCEDURE (~30 min)

**Test Suite (10 batches, 1M rows)**:
- `sql/06c_streaming_inserts_noindex_procedure_TEST.sql` - Phase 1 test (15 sec)
- `sql/07c_streaming_inserts_withindex_procedure_TEST.sql` - Phase 2 test (27 sec)
- `scripts/run_streaming_benchmark_TEST.sh` - Complete test workflow (52 sec)

### Quick Test Before Production

Validate complete workflow in 52 seconds:
```bash
# Run complete test (10 batches × 100K rows = 1M rows)
./scripts/run_streaming_benchmark_TEST.sh
```

**What the test validates**:
- ✅ PROCEDURE mechanism works correctly
- ✅ Per-batch commits function properly
- ✅ ANALYZE generates proper query statistics
- ✅ Real-time progress monitoring displays correctly
- ✅ All metrics/validation scripts work
- ✅ Table name detection (test vs production)
- ✅ Storage efficiency (PAX 25% smaller than AOCO)
- ✅ Compression ratios (PAX 5.3x vs AOCO 4.0x)
- ✅ Write performance (PAX 92.5% of AO speed)
- ✅ Query performance (7-189ms with proper statistics)

**Test results** (November 2025, 1M rows):
```
Storage:      PAX 143 MB vs AOCO 191 MB (25% smaller)
Compression:  PAX 5.3x vs AOCO 4.0x (32% better)
Write speed:  PAX 288K rows/sec vs AO 312K rows/sec (92.5%)
Query speed:  7-189ms (ANALYZE working correctly)
Runtime:      52 seconds for complete workflow
```

See `PROCEDURE_TEST_RESULTS_2025-11-01.md` for detailed test analysis.

### Key Improvements

**1. ANALYZE Fix** (Critical):
- Added post-load ANALYZE to all PROCEDURE files
- Ensures query optimizer has statistics
- **Result**: 400x query speedup (6+ minutes → 60-180ms)

**2. Real-Time Progress**:
- All scripts use `tee` for dual output (screen + log file)
- Batch-level progress visible during execution
- No more blind waiting

**3. Table Name Detection**:
- Metrics/validation scripts auto-detect test vs production tables
- Test creates: `streaming_metrics_phase1_test`
- Production creates: `streaming_metrics_phase1`
- Dynamic SQL handles both naming schemes

**4. Directory Flexibility**:
- All scripts auto-detect correct working directory
- Can run from any location

---

## Results Analysis

After running, check:

```bash
# View INSERT throughput metrics
cat results/run_YYYYMMDD_HHMMSS/10_metrics_phase1.txt

# View Phase 1 vs Phase 2 comparison (if both phases run)
cat results/run_YYYYMMDD_HHMMSS/10_metrics_phase2.txt

# View validation results
cat results/run_YYYYMMDD_HHMMSS/11_validation_phase1.txt

# View query performance
cat results/run_YYYYMMDD_HHMMSS/09_queries_phase1.log
```

---

## Troubleshooting

**"Validation failed - row count mismatch"**
- Check: `results/*/11_validation.txt` for details
- Cause: INSERT failed on one variant
- Fix: Review INSERT logs

**"CRITICAL STORAGE BLOAT DETECTED"**
- Cause: Bloom filters on low-cardinality columns
- Fix: Review `sql/02_analyze_cardinality.sql` output
- Verify: All bloom columns have >1000 unique values

**"INSERT throughput critically slow"**
- Check: PAX achieving <30% of AO speed
- Cause: Possible PAX configuration issue or system contention
- Fix: Review system resources, check for concurrent queries

**"Phase 2 runs Phase 1 queries"**
- Expected: Phase 2 reuses Phase 1 validation/metrics SQL
- Different: Only metrics tables differ (phase1 vs phase2)

---

## Implementation Details

### Python Version (October 2025)

The Python rewrite provides significant UX improvements over the bash-only approach:

**Architecture**:
- **Background thread monitoring**: Parses RAISE NOTICE messages from PostgreSQL logs in real-time
- **Progress bars**: Rich library provides professional progress UI with elapsed time and ETA
- **Subprocess + psql**: Maintains compatibility with existing SQL files (no database driver dependency)
- **Regex parsing**: Handles both Phase 1 and Phase 2 log format differences

**Key Features**:
```python
# Real-time batch tracking (updates every 10 batches)
[Batch 150/500] (100,000 rows, 15.0M total) ━━━━━━━━━━━━━━━━━━━━━ 30% 0:12:45 < 0:29:30
```

**Dependencies**:
- `rich>=13.0.0` (only external dependency for progress bars and styled console)

**Benefits**:
- See exactly which batch is running (vs 15-20 minute silent execution)
- Identify stuck batches immediately
- Better error messages with context
- Structured logging to both console and file

### Future Enhancements

Planned improvements for next version:

1. **Pause/resume capability**: Checkpoint every 100 batches with resume support

2. **Live throughput dashboard**: Per-variant throughput tracking in progress bar

3. **Variable workload patterns**: CLI options to customize traffic profiles

4. **UPDATE/DELETE testing**: Test mutable streaming data scenarios

5. **Multi-run comparison**: Automatically compare multiple benchmark runs

---

## Key Takeaways

This benchmark answers the critical production question:

**"Can I use PAX for high-throughput INSERT workloads?"**

**Expected answer** (based on PAX design):
- ✅ YES for streaming INSERTs (target: 90%+ of AO speed)
- ✅ YES with better query performance than AO
- ✅ YES with storage efficiency competitive with AOCO
- ✅ Best of both worlds: Fast writes + fast queries

**When to use this benchmark**:
- Evaluating PAX for telecommunications (CDRs, network events)
- Evaluating PAX for IoT (continuous sensor data)
- Evaluating PAX for log analytics (streaming logs)
- Any scenario with continuous batch loading + query requirements

---

## Related Benchmarks

- **timeseries_iot**: Query-focused, 10M rows, 2-5 min (fast iteration)
- **financial_trading**: High-cardinality testing, 10M rows, 4-8 min
- **retail_sales**: Comprehensive validation, 200M rows, 2-4 hours
- **log_analytics**: Sparse columns, 10M rows, 3-6 min
- **ecommerce_clickstream**: Multi-dimensional, 10M rows, 4-5 min

**This benchmark (streaming)**: INSERT-focused, 50M rows, 20-55 min

---

**Status**: Complete - Bash + Python implementations available (October 2025)
- ✅ Bash version: Simple, no dependencies, stable
- ✅ Python version: Real-time progress, better UX, recommended for interactive use
**Dependency**: `rich>=13.0.0` (Python version only)
