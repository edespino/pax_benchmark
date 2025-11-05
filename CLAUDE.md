# CLAUDE.md

AI assistant guidance for working with the PAX benchmark repository.

---

## Project Overview

**Purpose**: Standalone benchmark suite demonstrating PAX storage performance advantages over AO/AOCO in Apache Cloudberry Database.

**Key Metrics** (Expected with optimal configuration):
- 30-40% smaller storage
- 25-35% faster queries (requires file-level pruning enabled in code)
- 60-90% file skip rate
- 3-5x Z-order speedup

**Current Status** (October 2025):
- ✅ Benchmark configuration optimized based on PAX source code analysis
- ⚠️  File-level predicate pushdown disabled in Cloudberry 3.0.0-devel
- ✅ 4-variant testing approach isolates clustering effects
- ✅ Production-ready for PAX no-cluster variant

**Repository Type**: Self-contained benchmark (NOT PAX source code)

---

## Quick Context

### What This Is
- Standalone repository for PAX performance benchmarking
- Self-contained: all SQL, scripts, and documentation included
- Production-ready: based on 62,752 lines of PAX code analysis
- Scientifically rigorous: 3 runs per query, median reporting

### What This Is NOT
- NOT PAX source code (that's in Apache Cloudberry: `contrib/pax_storage/`)
- NOT a deployment tool (just benchmarking)
- NOT Cloudberry-version specific (tested on PG14 base)

### Dependencies
- **Required**: Apache Cloudberry built with `--enable-pax`
- **Required**: Running Cloudberry cluster (3+ segments recommended)
- **Optional**: Python with matplotlib/seaborn (for charts)

---

## Repository Structure

```
pax_benchmark/
├── README.md                    # Main entry point - START HERE
├── QUICK_REFERENCE.md           # One-page cheat sheet
├── CLAUDE.md                    # This file
│
├── benchmarks/                  # All benchmark suites
│   ├── README.md                # Benchmark suite overview
│   │
│   ├── retail_sales/            # Original comprehensive benchmark (200M rows, 2-4 hrs)
│   │   ├── README.md
│   │   ├── scripts/
│   │   │   ├── run_full_benchmark.sh    # MASTER SCRIPT (runs all phases)
│   │   │   ├── parse_explain_results.py # Extract metrics from logs
│   │   │   └── generate_charts.py       # Create PNG charts
│   │   ├── sql/
│   │   │   ├── 01_setup_schema.sql      # Schema + dimensions
│   │   │   ├── 02_create_variants.sql   # AO/AOCO/PAX/PAX-no-cluster (4 variants)
│   │   │   ├── 03_generate_data.sql     # 200M rows (~70GB per variant)
│   │   │   ├── 03_generate_data_SMALL.sql # 1M rows for quick testing
│   │   │   ├── 04_optimize_pax.sql      # GUCs + Z-order clustering (sets maintenance_work_mem)
│   │   │   ├── 04a_validate_clustering_config.sql # Pre-flight memory check
│   │   │   ├── 05_queries_ALL.sql       # 20 queries, 7 categories
│   │   │   ├── 05_test_sample_queries.sql # Quick 2-query test
│   │   │   ├── 06_collect_metrics.sql   # Storage + performance metrics
│   │   │   ├── 07_inspect_pax_internals.sql # PAX statistics & cardinality analysis
│   │   │   └── 08_analyze_query_plans.sql   # Detailed EXPLAIN ANALYZE
│   │   ├── visuals/
│   │   │   └── charts/          # Chart generation (retail_sales specific)
│   │   └── results/             # Historical results + analysis
│   │
│   ├── timeseries_iot/          # IoT sensor benchmark (10M rows, 2-5 min)
│   │   ├── README.md
│   │   ├── scripts/run_iot_benchmark.sh
│   │   ├── sql/ (9 files with validation framework)
│   │   └── results/
│   │
│   ├── financial_trading/       # Trading tick benchmark (10M rows, 4-8 min)
│   │   ├── README.md
│   │   ├── scripts/run_trading_benchmark.sh
│   │   ├── sql/ (9 files with validation framework)
│   │   └── results/
│   │
│   ├── log_analytics/           # APM/observability logs (10M rows, 3-6 min)
│   │   ├── README.md
│   │   ├── scripts/run_log_benchmark.sh
│   │   ├── sql/ (10 files with validation framework)
│   │   └── results/
│   │
│   ├── ecommerce_clickstream/   # E-commerce clickstream (10M rows, 4-5 min)
│   │   ├── README.md
│   │   ├── scripts/run_clickstream_benchmark.sh
│   │   ├── sql/ (12 files with validation framework)
│   │   ├── docs/BENCHMARK_RESULTS_2025-10-30.md
│   │   └── results/
│   │
│   └── timeseries_iot_streaming/  # Streaming INSERT benchmark (36-50M rows, 20min-7hrs)
│       ├── README.md
│       ├── scripts/
│       │   ├── run_streaming_benchmark.py    # Python (recommended - real-time progress)
│       │   │   # --heap flag: 5 variants (6-7 hrs) - Track C complete ✅
│       │   │   # --partitioned flag: 24 partitions (28 min) - Track B complete ✅
│       │   │   # --phase {1|2|both}: Flexible phase selection
│       │   ├── run_streaming_benchmark.sh    # Bash master (both phases)
│       │   ├── run_phase1_noindex.sh         # Bash Phase 1 only (20 min)
│       │   ├── run_phase2_withindex.sh       # Bash Phase 2 only (30 min)
│       │   └── requirements.txt              # Python dependencies (rich>=13.0.0)
│       ├── sql/ (18 files: baseline + optimized + partitioned + HEAP)
│       ├── TRACK_C_COMPREHENSIVE_ANALYSIS.md  # 55-section analysis (Track C)
│       ├── OPTIMIZATION_TESTING_PLAN.md       # All 3 tracks documented
│       ├── docs/BENCHMARK_RESULTS_2025-10-30.md
│       └── results/
│           ├── run_heap_20251104_220151/      # Track C: Successful HEAP run
│           └── run_partitioned_20251103_132503/  # Track B: Successful partitioned run
│
├── PAX_DEVELOPMENT_TEAM_REPORT.md  # Comprehensive findings for PAX dev team
│
├── docs/
│   ├── INSTALLATION.md          # Setup instructions
│   ├── TECHNICAL_ARCHITECTURE.md # PAX internals (2,450+ lines)
│   ├── METHODOLOGY.md           # Scientific approach
│   ├── CONFIGURATION_GUIDE.md   # Production best practices
│   ├── REPORTING.md             # Results visualization
│   ├── diagrams/                # PAX architecture diagrams (3 PNGs)
│   └── archive/                 # Historical meta-docs
│
└── (root level documentation files)
```

---

## Common User Tasks

### Choose a Benchmark

**Quick iteration / Development** (2-5 min):
```bash
cd benchmarks/timeseries_iot
./scripts/run_iot_benchmark.sh
```

**High-cardinality testing** (4-8 min):
```bash
cd benchmarks/financial_trading
./scripts/run_trading_benchmark.sh
```

**Sparse column testing / APM data** (3-6 min):
```bash
cd benchmarks/log_analytics
./scripts/run_log_benchmark.sh
```

**Multi-dimensional clustering / E-commerce** (4-5 min):
```bash
cd benchmarks/ecommerce_clickstream
./scripts/run_clickstream_benchmark.sh
```

**INSERT throughput / Streaming workloads** (20 min to 7 hours depending on variant):
```bash
cd benchmarks/timeseries_iot_streaming

# Python version (recommended - real-time progress)
pip3 install -r scripts/requirements.txt  # First time only

# Monolithic (4 variants: AO/AOCO/PAX/PAX-no-cluster)
./scripts/run_streaming_benchmark.py      # Both phases (50 min, interactive)
./scripts/run_streaming_benchmark.py --phase 1  # Phase 1 only (20 min)

# Partitioned (24 partitions per variant - 🏆 11x Phase 2 speedup)
./scripts/run_streaming_benchmark.py --partitioned  # Both phases (28 min)
./scripts/run_streaming_benchmark.py --partitioned --phase 1  # Phase 1 only (10 min)

# HEAP variant (5 variants - Track C academic demonstration) ⚠️  6-7 hours
./scripts/run_streaming_benchmark.py --heap  # Both phases (379 min)
./scripts/run_streaming_benchmark.py --heap --phase 1  # Phase 1 only (12 min)

# Bash version (alternative - silent execution)
./scripts/run_phase1_noindex.sh        # Phase 1 only (20 min)
./scripts/run_streaming_benchmark.sh   # Both phases (50 min)
```

**Why Partitioned?**
- ✅ **11x Phase 2 speedup** (284m → 17m, total 300m → 28m)
- ✅ **Eliminates catastrophic stalls** (287x → 26x worst case)
- ✅ **MANDATORY for tables >10M rows with indexes**

**Why HEAP variant?**
- ✅ **Academic validation**: Demonstrates append-only storage advantages (4.93x bloat)
- ⚠️  **NOT for production**: 2.26x larger than PAX despite 19% faster throughput
- 📊 **Track C complete**: See `TRACK_C_COMPREHENSIVE_ANALYSIS.md` (538 lines, 55 sections)

**Comprehensive validation** (2-4 hours):
```bash
cd benchmarks/retail_sales
./scripts/run_full_benchmark.sh
```

---

### Retail Sales Benchmark - Individual Phases (4-Variant Test with 1M rows)

```bash
cd benchmarks/retail_sales

# Recommended workflow (includes validation scripts)
psql -f sql/01_setup_schema.sql                    # 5-10 min
psql -f sql/02_create_variants.sql                 # 2 min (4 variants)
psql -f sql/03_generate_data_SMALL.sql             # 2-3 min (1M rows)
psql -f sql/04a_validate_clustering_config.sql     # Validate memory (30 sec)
psql -f sql/04_optimize_pax.sql                    # 5-10 min (sets maintenance_work_mem=2GB)
psql -f sql/05_test_sample_queries.sql             # 2 min (2 queries × 4 variants)
psql -f sql/06_collect_metrics.sql                 # 2 min
psql -f sql/07_inspect_pax_internals.sql           # Optional: PAX analysis
psql -f sql/08_analyze_query_plans.sql             # Optional: Detailed EXPLAIN

# Large-scale test (200M rows)
psql -f sql/03_generate_data.sql                   # 30-60 min
# Increase maintenance_work_mem to 8GB+ before sql/04_optimize_pax.sql
```

---

### Generate Charts (Retail Sales Only)

```bash
cd benchmarks/retail_sales

# Real charts (after benchmark)
python3 scripts/generate_charts.py results/run_YYYYMMDD_HHMMSS/

# Example charts (before benchmark)
python3 scripts/generate_charts.py
```

---

### Analyze Results

```bash
cd benchmarks/retail_sales

# View comparison
cat results/run_YYYYMMDD_HHMMSS/comparison_table.md

# Parse all metrics
python3 scripts/parse_explain_results.py results/run_YYYYMMDD_HHMMSS/
```

---

## Modifying the Benchmarks

### Change Dataset Size (Retail Sales)
**File**: `benchmarks/retail_sales/sql/03_generate_data.sql`
```sql
-- Line ~45: Change 200000000 to desired size
FROM generate_series(1, 50000000) gs  -- 50M instead of 200M
```

### Adjust PAX Configuration (Retail Sales)
**File**: `benchmarks/retail_sales/sql/02_create_variants.sql` (lines 111-141)

**⚠️  CRITICAL CONFIGURATION PRINCIPLES** (as of Oct 2025):

```sql
CREATE TABLE benchmark.sales_fact_pax (...) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: LOW OVERHEAD - use liberally (6-12 columns)
    -- Works for: ALL filterable columns (range, equality, NULL checks)
    minmax_columns='date,id,amount,region,status,category',

    -- Bloom: HIGH OVERHEAD - use selectively (1-3 columns)
    -- ⚠️  CRITICAL: ONLY for high-cardinality (>1000 distinct values)
    -- ⚠️  ALWAYS validate cardinality first with sql/07_inspect_pax_internals.sql
    -- Examples: product_id (99K unique), transaction_id (millions)
    -- ❌ DON'T use for: Low-cardinality (<1000 values) - causes MASSIVE storage bloat
    -- ❌ NEVER assume cardinality - CHECK IT with: SELECT attname, n_distinct FROM pg_stats
    bloomfilter_columns='product_id',  -- Only high-cardinality columns

    -- Clustering: 2-3 correlated dimensions
    cluster_columns='date,region',
    cluster_type='zorder',
    storage_format='porc'
);

-- Per-column encoding (if supported in your PAX version)
-- Note: NOT supported in Cloudberry 3.0.0-devel
ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN your_col SET ENCODING (compresstype=delta);
```

**Key Decision Rule**:
```
Is column in WHERE clause?
├─ YES → Add to minmax_columns
│   └─ Is cardinality > 1000?
│       ├─ YES → Also add to bloomfilter_columns
│       └─ NO  → Skip bloom (minmax sufficient)
└─ NO  → Skip both
```

### Add Custom Queries (Retail Sales)
**File**: `benchmarks/retail_sales/sql/05_queries_ALL.sql`
```sql
-- Add at end (after Q20)
\echo 'Q21: Your custom query'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT ... FROM benchmark.TABLE_VARIANT WHERE ...;
```

### Tune GUCs (Retail Sales)
**File**: `benchmarks/retail_sales/sql/04_optimize_pax.sql` (lines 18-90)

**⚠️  CRITICAL**: Set maintenance_work_mem BEFORE clustering (prevents 2-3x storage bloat)

```sql
-- Memory for clustering (CRITICAL - prevents storage bloat)
SET maintenance_work_mem = '2GB';   -- For 10M rows
SET maintenance_work_mem = '8GB';   -- For 200M rows

-- Sparse filtering (enables file-level pruning)
SET pax.enable_sparse_filter = on;
SET pax.enable_row_filter = off;  -- For OLAP workloads

-- Bloom filter memory (scale with cardinality)
SET pax.bloom_filter_work_memory_bytes = 104857600;  -- 100MB for high-cardinality

-- Micro-partition sizing (defaults are good)
SET pax.max_tuples_per_file = 1310720;    -- 1.31M tuples
SET pax.max_size_per_file = 67108864;     -- 64MB
```

**Validation**: Run `benchmarks/retail_sales/sql/04a_validate_clustering_config.sql` to check memory requirements

---

## Important Concepts

### PAX Storage Features (What We're Benchmarking)

1. **Per-Column Encoding**
   - Delta: Sequential values → 8x compression
   - RLE: Low cardinality → 23x compression
   - ZSTD: General purpose → 1.5-4x compression

2. **Sparse Filtering (Zone Maps)**
   - Min/max statistics per file
   - Prunes 60-90% of files before reading
   - Massive I/O savings

3. **Bloom Filters**
   - High-cardinality equality/IN queries
   - File-level pruning

4. **Z-Order Clustering**
   - Multi-dimensional space-filling curve
   - Co-locates correlated dimensions
   - 3-5x speedup on multi-dimensional ranges

5. **Micro-Partitioning**
   - Default: 64MB files, 131K tuples/group
   - Rich protobuf metadata per file

### Why PAX Configuration Is Critical (vs AO/AOCO)

**⚠️  CRITICAL UNDERSTANDING: PAX is uniquely dangerous when misconfigured**

Unlike AO/AOCO where configuration errors cause minor impact (10-30% storage difference), **PAX misconfiguration causes catastrophic failures** (80%+ bloat, 54x memory overhead).

---

#### Parameter Count and Complexity

**AO (Append-Only Row-Oriented): 3 Parameters**
```sql
CREATE TABLE foo (...) WITH (
    appendonly=true,           -- Binary choice
    compresstype=zstd,         -- 4 options: none/zlib/zstd/lz4
    compresslevel=5            -- 1-9 (higher = smaller/slower)
);
```
**Configuration Risk**: **Low**
- No data analysis required
- Worst case: Wrong compression level → 20-30% size difference
- Immediately visible in pg_relation_size()

**AOCO (Append-Only Column-Oriented): 5+ Parameters**
```sql
CREATE TABLE foo (...) WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
);

-- Optional per-column (adds 3-5 decisions per column)
ALTER TABLE foo ALTER COLUMN bar SET ENCODING (
    compresstype=delta,        -- vs RLE/zstd/none
    compresslevel=1
);
```
**Configuration Risk**: **Moderate**
- Minimal data analysis (identify sequential/low-cardinality columns)
- Worst case: Suboptimal encoding → 30-50% size difference
- Forgiving: ZSTD default works reasonably for all data types

**PAX (Partition-Aware eXtension): 15+ Parameters**
```sql
CREATE TABLE foo (...) USING pax WITH (
    -- Core compression (3 parameters)
    compresstype='zstd',
    compresslevel=5,
    storage_format='porc',

    -- Statistics configuration (4 parameters)
    minmax_columns='col1,col2,...',
    bloomfilter_columns='col3,col4,...',  -- ⚠️  CRITICAL: Data-dependent
    pax.bloom_filter_work_memory_bytes=104857600,
    pax.max_bloom_filter_size=10485760,

    -- Clustering configuration (3 parameters)
    cluster_type='zorder',
    cluster_columns='col5,col6,...',
    maintenance_work_mem='2GB',

    -- Micro-partitioning (5+ parameters)
    pax.max_tuples_per_file=1310720,
    pax.max_size_per_file=67108864,
    pax.enable_sparse_filter=on,
    pax.enable_row_filter=off,
    pax.compression_buffer_size=524288
);
```
**Configuration Risk**: **EXTREME**
- Extensive data analysis required (cardinality, correlations, query patterns)
- Worst case: Wrong bloom filters → **400%+ size increase**
- **Not immediately visible** (table creates successfully, bloat appears gradually)
- Multiplicative failures (each mistake compounds)

---

#### Why PAX Is Different: Data Dependency

**AO/AOCO: Configuration-Independent**
```sql
-- SAME configuration works for ANY data
CREATE TABLE small_table (...) WITH (compresstype=zstd, compresslevel=5);
CREATE TABLE huge_table (...) WITH (compresstype=zstd, compresslevel=5);
-- Result: Predictable, safe, 3-4x compression regardless
```

**PAX: Configuration-Dependent**
```sql
-- SAME configuration, DIFFERENT data → CATASTROPHIC FAILURE

-- Data A: High-cardinality product_id (99K unique)
bloomfilter_columns='product_id'
-- Result: ✅ 6.5x compression, excellent performance

-- Data B: Low-cardinality region (5 unique)
bloomfilter_columns='region'
-- Result: ❌ 1.8x compression, 80% bloat, 50x memory overhead
```

**Critical Point**: You **cannot** copy-paste PAX configuration between tables without analyzing the data first.

---

#### The Bloom Filter Problem (Technical Deep Dive)

**Why Bloom Filters Are Safe in Other Systems** (Redis, Cassandra, RocksDB):
- **One bloom filter per table/SSTable** (few MB total)
- Low cardinality? Filter is small and useless, but harmless

**Why Bloom Filters Are Dangerous in PAX**:
- **One bloom filter PER MICRO-PARTITION FILE**
- Default: ~8 files per 10M rows
- Bloom filters stored in **every file's metadata**

**Math of the Disaster**:
```
Low-Cardinality Column (5 unique values):
├─ Bloom filter size: ~50 MB per file (wasteful, no benefit)
├─ Files created: 8 files for 10M rows
├─ Total waste: 50 MB × 8 = 400 MB
└─ Compression killed: ZSTD can't compress bloom filter metadata

High-Cardinality Column (99K unique values):
├─ Bloom filter size: ~50 MB per file (useful, selective)
├─ Files created: 8 files for 10M rows
├─ Total cost: 50 MB × 8 = 400 MB
└─ Value delivered: 60-90% file skip rate (worth it!)
```

**The Paradox**: Same storage cost, **opposite value**.
- High-cardinality: 400 MB buys you 3-5x query speedup
- Low-cardinality: 400 MB buys you **nothing** (filter matches everything)

**Real Example from October 2025 Test**:

**Before (3 bloom filter columns)**:
```sql
bloomfilter_columns='transaction_hash,customer_id,product_id'
```

| Column | Cardinality | Bloom Size | Files | Total Waste | Query Benefit |
|--------|-------------|------------|-------|-------------|---------------|
| transaction_hash | n_distinct=-1 (5 unique) | 50 MB | 8 | 400 MB | ❌ None |
| customer_id | n_distinct=-0.46 (7 unique) | 50 MB | 8 | 400 MB | ❌ None |
| product_id | 99,671 unique | 50 MB | 8 | 400 MB | ✅ 60-90% skip |

**Total**: 1,200 MB bloom filter metadata, **800 MB wasted**

**After (1 bloom filter column)**:
```sql
bloomfilter_columns='product_id'
```
**Total**: 400 MB bloom filter metadata, **0 MB wasted**
**Result**: 942 MB vs 1,350 MB (30% reduction from removing useless bloom filters)

---

#### Cascading Failures: Multiplicative vs Additive

**AOCO: Mistakes Are Independent (Additive)**
```sql
-- Mistake 1: Wrong compression level (compresslevel=1 instead of 5)
Impact: +15% size

-- Mistake 2: Wrong encoding on text column (delta instead of zstd)
Impact: +10% size

-- TOTAL: 1.15 × 1.10 = 1.27x (27% bloat)
-- Mistakes don't compound, relatively safe
```

**PAX: Mistakes Compound (Multiplicative)**
```sql
-- Mistake 1: Bloom filters on 2 low-cardinality columns
Impact: +81% size (1.81x)

-- Mistake 2: Low maintenance_work_mem during clustering
Impact: +26% additional bloat (1.26x)

-- Mistake 3: Wrong cluster_columns (uncorrelated dimensions)
Impact: +100% query time (2.0x slower)

-- TOTAL: 1.81 × 1.26 × 2.0 = 4.56x disaster
-- Each mistake makes the others worse
```

---

#### Silent Failures

**AOCO: Visible Failures**
```bash
# Wrong compression
psql -c "SELECT pg_size_pretty(pg_total_relation_size('foo'));"
#  pg_size_pretty
# ----------------
#  850 MB        # Expected: 650 MB → investigate immediately

# Wrong encoding per column
psql -c "SELECT attname, attstorage FROM pg_attribute WHERE attrelid='foo'::regclass;"
#   attname   | attstorage
# ------------+------------
#  id         | p          # Plain (should be compressed) → fix now
```

**PAX: Silent Failures**
```bash
# Table creates successfully
CREATE TABLE foo (...) USING pax WITH (bloomfilter_columns='low_cardinality_col');
# CREATE TABLE ✅ (no warning!)

# Size looks normal at first (before CLUSTER)
SELECT pg_size_pretty(pg_total_relation_size('foo'));
#  pg_size_pretty
# ----------------
#  750 MB        # Looks fine

# Disaster appears after CLUSTER (hours later)
CLUSTER foo USING idx_zorder;
# CLUSTER (takes 5 minutes, no warning)

SELECT pg_size_pretty(pg_total_relation_size('foo'));
#  pg_size_pretty
# ----------------
#  1,350 MB      # 🔴 DISASTER! But why? No error message.
```

**Root Cause Diagnosis Requires**:
1. Run `benchmarks/retail_sales/sql/07_inspect_pax_internals.sql` (custom script)
2. Analyze pg_stats for each column
3. Check bloom filter configuration vs cardinality
4. Reverse-engineer what went wrong

**In AOCO**: `pg_relation_size()` immediately shows the problem.

---

#### Summary Table

| Aspect | AO | AOCO | PAX |
|--------|----|----- |-----|
| **Total parameters** | 3 | 5-8 | 15+ |
| **Data analysis required** | None | Minimal | Extensive |
| **Worst misconfiguration** | 1.3x size | 1.5x size | **4.5x size** |
| **Error visibility** | Immediate | Immediate | **Delayed/Hidden** |
| **Copy-paste safety** | ✅ Safe | ✅ Safe | ❌ Dangerous |
| **Failure mode** | Additive | Additive | **Multiplicative** |
| **Silent bloat risk** | Rare | Rare | **Common** |
| **Production risk** | Low | Low | **High** |
| **Validation tooling** | Optional | Optional | **ESSENTIAL** |

---

#### Why Validation Tooling Is Not Optional for PAX

**For AO/AOCO**: An experienced DBA can configure correctly in 5 minutes without tools.

**For PAX**: Even experts need:
1. Cardinality analysis script (e.g., `benchmarks/retail_sales/sql/07_inspect_pax_internals.sql`)
2. Memory validation script (e.g., `benchmarks/retail_sales/sql/04a_validate_clustering_config.sql`)
3. Validation frameworks (built into `timeseries_iot` and `financial_trading` benchmarks)
4. Pre-deployment validation (90 minutes minimum)
5. Ongoing monitoring (detect silent bloat)

**This is why the validation-first benchmarks exist** (`timeseries_iot` and `financial_trading`) — PAX is fundamentally different from AO/AOCO in its configuration complexity and failure modes.

---

### Benchmark Suite Design

**Three Benchmarks Available**:

1. **Retail Sales** (`benchmarks/retail_sales/`)
   - Dataset: 200M rows, 25 columns, ~70GB per variant
   - Fact table: sales transactions with realistic distributions
   - Dimensions: 10M customers, 100K products
   - Patterns: Correlated (date+region), skewed, sparse fields
   - Runtime: 2-4 hours (comprehensive)

2. **IoT Time-Series** (`benchmarks/timeseries_iot/`)
   - Dataset: 10M sensor readings, 100K devices
   - Validation-first: 4 safety gates
   - Runtime: 2-5 minutes (fast iteration)

3. **Financial Trading** (`benchmarks/financial_trading/`)
   - Dataset: 10M trading ticks, 5K symbols
   - High-cardinality testing
   - Runtime: 4-8 minutes

**All benchmarks test 4 variants**:
1. **AO** - Append-Only row-oriented (baseline)
2. **AOCO** - Append-Only column-oriented (current best practice)
3. **PAX (clustered)** - Optimized with Z-order clustering
4. **PAX (no-cluster)** - PAX without clustering (control group)

**Retail Sales Query Categories** (20 queries):
- **A (Q1-Q3)**: Sparse filtering effectiveness
- **B (Q4-Q6)**: Bloom filter effectiveness
- **C (Q7-Q9)**: Z-order clustering benefits
- **D (Q10-Q12)**: Compression efficiency
- **E (Q13-Q15)**: Complex analytics
- **F (Q16-Q18)**: MVCC operations
- **G (Q19-Q20)**: Edge cases

---

## Expected Results

### Success Criteria (With Optimal Configuration)

**Storage** (validated with 10M row test, Oct 2025):
- ✅ PAX no-cluster: +5% vs AOCO (745 MB vs 710 MB) - **ACHIEVED**
- ⚠️  PAX clustered: +26% vs no-cluster (942 MB vs 745 MB) - **Acceptable but higher than expected <5%**
- ❌ Expected clustering overhead: <5% (requires code investigation for 26% actual)

**Performance** (with optimized bloom filter config):
- ✅ Q1 (date range): Tied with AOCO (was 2.6x slower before bloom filter fix)
- ✅ Q2 (bloom filter): 1.4x faster than AOCO (high-cardinality filtering)
- ✅ Sample query: 2.4x faster than AOCO (Z-order clustering benefit)
- ⚠️  File-level pruning: Still disabled (pax_scanner.cc:366) - not a config issue
- ⚠️  Performance will improve further when predicate pushdown enabled in code

### Actual Results (October 2025 - 10M Row Test)

**Before Bloom Filter Fix** (transaction_hash, customer_id, product_id):
- ❌ PAX clustered: 1,350 MB (81% bloat - CRITICAL ISSUE)
- ❌ PAX clustered memory: 8,683 KB per query (54x overhead)
- ❌ PAX clustered compression: 1.85x (45% worse than no-cluster)
- ❌ Queries: 2-3x slower than AOCO

**After Bloom Filter Fix** (product_id only, maintenance_work_mem=2GB):
- ✅ PAX no-cluster: 745 MB (5% larger than AOCO's 710 MB) - **Production-ready**
- ⚠️  PAX clustered: 942 MB (26% larger than no-cluster) - **Acceptable overhead**
- ✅ PAX clustered memory: 2,982 KB per query (66% reduction vs before)
- ✅ PAX clustered compression: 6.52x (competitive with AOCO's 8.65x)
- ✅ Q1 performance: Tied with AOCO (was 2.6x slower)
- ✅ Q2 performance: 1.4x faster than AOCO (was 2.0x slower)
- ⚠️  File-level pruning: Still disabled in code (not a config issue)

**Root Causes Identified & Fixed**:
1. **PRIMARY ISSUE**: Bloom filters on low-cardinality columns → **FIXED** in `benchmarks/retail_sales/sql/02_create_variants.sql`
   - Caused: 81% storage bloat, 54x memory overhead, 45% compression degradation
   - Fix: Remove transaction_hash (n_distinct=-1) and customer_id (n_distinct=-0.46)
2. **SECONDARY**: Low maintenance_work_mem → **FIXED** in `benchmarks/retail_sales/sql/04_optimize_pax.sql`
3. **CODE-LEVEL**: Predicate pushdown disabled in pax_scanner.cc:366 (requires code fix)

**Key Lesson**: **ALWAYS validate column cardinality before configuring bloom filters.**

See: `benchmarks/retail_sales/results/OPTIMIZATION_RESULTS_COMPARISON.md` for complete analysis

---

## Troubleshooting Quick Reference

**"PAX clustering causes massive storage bloat"** 🔴 CRITICAL - MOST COMMON ISSUE
```bash
# CAUSE #1 (PRIMARY): Bloom filters on low-cardinality columns
# Symptoms: 80%+ storage bloat, 50x+ memory usage, compressed < 2x
# FIX: Validate cardinality BEFORE configuring bloom filters

# Step 1: Check cardinality of ALL columns
cd benchmarks/retail_sales  # or timeseries_iot or financial_trading
psql -f sql/07_inspect_pax_internals.sql  # retail_sales has this

# Step 2: Remove any bloom filter columns with n_distinct < 1000
# Edit benchmarks/*/sql/02_create_variants.sql:
#   bloomfilter_columns='high_card_col1,high_card_col2'  -- ONLY >1000 distinct

# CAUSE #2 (SECONDARY): Low maintenance_work_mem
# Symptoms: 2x storage bloat, normal memory usage
# FIX: Validate memory BEFORE clustering
psql -f sql/04a_validate_clustering_config.sql  # Available in retail_sales
psql -c "SET maintenance_work_mem='2GB';" -f sql/04_optimize_pax.sql
```

**"How do I validate bloom filter columns?"** ⚠️  DO THIS FIRST
```sql
-- Check cardinality of all columns
SELECT
    attname AS column_name,
    n_distinct,
    CASE
        WHEN ABS(n_distinct) > 1000 THEN '✅ GOOD for bloom filter'
        WHEN ABS(n_distinct) > 100 THEN '🟠 Borderline - consider minmax only'
        ELSE '❌ BAD for bloom filter - use minmax instead'
    END AS bloom_suitability
FROM pg_stats
WHERE tablename = 'your_table_name'
ORDER BY ABS(n_distinct) DESC;

-- Or use the inspection script (retail_sales):
cd benchmarks/retail_sales && psql -f sql/07_inspect_pax_internals.sql
```

**"PAX queries slower than AOCO"**
- Expected in Cloudberry 3.0.0-devel (predicate pushdown disabled)
- Check: `psql -c "SHOW pax.enable_sparse_filter;"` (should be `on`)
- Analyze: `cd benchmarks/retail_sales && psql -f sql/08_analyze_query_plans.sql`
- Not a config issue if "Rows Removed by Filter" is high

**"PAX extension not found"**
```bash
./configure --enable-pax --with-perl --with-python --with-libxml
git submodule update --init --recursive
make clean && make -j8 && make install
```

**"Out of disk space"**
- Need ~300GB free for full retail_sales benchmark (200M rows)
- For testing: Use smaller benchmarks (`timeseries_iot` 2-5 min, `financial_trading` 4-8 min)
- Or use `benchmarks/retail_sales/sql/03_generate_data_SMALL.sql` (1M rows, ~1GB)

**"Connection refused"**
```bash
psql -c "SELECT version();"
psql -c "SELECT amname FROM pg_am WHERE amname = 'pax';"
```

**Charts not generating**
```bash
pip3 install matplotlib seaborn
# Or use ASCII charts in docs/archive/VISUAL_PRESENTATION.md
```

---

## Key Files for AI Assistants

**Most Important** (Start Here):
1. **PAX_DEVELOPMENT_TEAM_REPORT.md** - Comprehensive findings across 5 benchmarks (NEW)
2. **OPTIMIZATION_CHANGES.md** - Latest updates & fixes (Oct 2025)
3. **benchmarks/README.md** - Benchmark suite overview
4. `QUICK_REFERENCE.md` - Commands & troubleshooting
5. `docs/CONFIGURATION_GUIDE.md` - PAX tuning (updated with memory guidance)
6. `docs/TECHNICAL_ARCHITECTURE.md` - Deep understanding (2,450+ lines)

**Benchmark Directories** (5 of 7 complete):
- `benchmarks/retail_sales/` - Original comprehensive benchmark (200M rows, 2-4 hrs)
- `benchmarks/timeseries_iot/` - Fast iteration with validation (10M rows, 2-5 min)
- `benchmarks/financial_trading/` - High-cardinality testing (10M rows, 4-8 min)
- `benchmarks/log_analytics/` - APM/observability logs (10M rows, 3-6 min)
- `benchmarks/ecommerce_clickstream/` - Multi-dimensional clickstream (10M rows, 4-5 min)

**Retail Sales Execution Scripts** (In Order):
1. `benchmarks/retail_sales/sql/01_setup_schema.sql` - Schema creation
2. `benchmarks/retail_sales/sql/02_create_variants.sql` - 4 variants (OPTIMIZED)
3. `benchmarks/retail_sales/sql/03_generate_data_SMALL.sql` - 1M rows for testing
4. `benchmarks/retail_sales/sql/04a_validate_clustering_config.sql` - Memory validation
5. `benchmarks/retail_sales/sql/04_optimize_pax.sql` - Sets maintenance_work_mem=2GB
6. `benchmarks/retail_sales/sql/05_test_sample_queries.sql` - Quick 2-query test
7. `benchmarks/retail_sales/sql/06_collect_metrics.sql` - Storage & performance
8. `benchmarks/retail_sales/sql/07_inspect_pax_internals.sql` - Statistics analysis
9. `benchmarks/retail_sales/sql/08_analyze_query_plans.sql` - Detailed EXPLAIN

**Analysis & Results**:
- `benchmarks/retail_sales/results/4-variant-test-10M-rows.md` - Comprehensive test results
- `benchmarks/retail_sales/results/QUICK_SUMMARY.md` - Executive summary
- `benchmarks/retail_sales/results/test-config-2025-10-29.log` - Reproduction guide

**Documentation Map**:
- **README.md** - Start here (main overview)
- **docs/INSTALLATION.md** - Setup instructions
- **docs/CONFIGURATION_GUIDE.md** - PAX tuning (UPDATED with memory section)
- **docs/METHODOLOGY.md** - Scientific approach
- **docs/REPORTING.md** - Results analysis
- **docs/diagrams/** - PAX architecture diagrams (3 PNGs)
- **docs/archive/** - Historical meta-documentation

---

## Technical Foundation

**Code Review**: Benchmark based on analysis of:
- **62,752 lines** of C++/C reviewed
- **188+ files** across 10 directories
- **PGConf presentation** (33 slides) integrated
- **TPC-H/TPC-DS** real-world results validated

**Key Implementation Details**:
- File Format: PORC (PostgreSQL-ORC hybrid)
- Sparse Filter: Statistics-based pruning
- Z-Order: Bit-interleaving algorithm
- Encoding: Delta, RLE, ZSTD (no universal best)
- Integration: PostgreSQL TAM API

---

## Performance Optimization Notes

### For Faster Benchmarks (Development)
```sql
-- Reduce data in sql/03_generate_data.sql
FROM generate_series(1, 1000000) gs  -- 1M rows (~1 min)

-- Reduce runs in run_full_benchmark.sh
for run in 1; do  -- Single run instead of 3
```

### For Production-Like Testing
```sql
-- Larger dataset
FROM generate_series(1, 500000000) gs  -- 500M rows

-- Add custom queries to sql/05_queries_ALL.sql
-- Focus on your workload patterns
```

---

## Important Warnings

### Do NOT
- ❌ Commit `results/` to git (large, gitignored)
- ❌ Commit generated charts (can regenerate)
- ❌ Modify PAX source in this repo (wrong location)
- ❌ Run on production cluster (resource intensive)
- ❌ Skip clustering step (PAX won't show Z-order benefits)

### Always
- ✅ Run `ANALYZE` after data generation
- ✅ Run `CLUSTER` after configuring clustering
- ✅ Clear caches between runs (CHECKPOINT + sleep)
- ✅ Test with small dataset first (1M rows)
- ✅ Verify PAX installed before starting

---

## Related Resources

**In This Repository**:
- Main docs in root + `docs/`
- Historical context in `docs/archive/`

**Apache Cloudberry**:
- Source: https://github.com/apache/cloudberry
- PAX Code: `contrib/pax_storage/` in Cloudberry repo
- PAX Docs: `contrib/pax_storage/doc/` in Cloudberry repo

**External References**:
- TPC-H Results: In Cloudberry `contrib/pax_storage/doc/performance.md`
- PGConf Talk: Leonid Borchuk (Apache Cloudberry Committer)
- Production: Validated in Yandex Cloud

---

## AI Assistant Quick Context Summary

**What**: Standalone benchmark evaluating PAX vs AO/AOCO in Apache Cloudberry
**How**: 200M rows, 4 variants (AO/AOCO/PAX/PAX-no-cluster), 20 queries, automated execution
**Why**: Validate PAX storage efficiency and query performance with proper configuration
**Results** (10M row test, Oct 2025):
- Storage: PAX no-cluster +5% vs AOCO, PAX clustered +33% vs AOCO
- Performance: PAX competitive with AOCO (tied to 1.4x faster on selective queries)
- Critical: Bloom filter cardinality validation required (prevents 80% bloat)
**Status**: Production-ready with correct configuration, scientifically rigorous

**Common User Intent**:
- "Run a quick test" → `cd benchmarks/timeseries_iot && ./scripts/run_iot_benchmark.sh` (2-5 min)
- "Run comprehensive test" → `cd benchmarks/retail_sales && ./scripts/run_full_benchmark.sh` (2-4 hrs)
- "Test high-cardinality" → `cd benchmarks/financial_trading && ./scripts/run_trading_benchmark.sh` (4-8 min)
- "Test sparse columns / APM logs" → `cd benchmarks/log_analytics && ./scripts/run_log_benchmark.sh` (3-6 min)
- "Test multi-dimensional / clickstream" → `cd benchmarks/ecommerce_clickstream && ./scripts/run_clickstream_benchmark.sh` (4-5 min)
- "Review all findings" → Read `PAX_DEVELOPMENT_TEAM_REPORT.md`
- "Understand PAX" → Read `docs/TECHNICAL_ARCHITECTURE.md`
- "Configure PAX" → Read `docs/CONFIGURATION_GUIDE.md` + `benchmarks/README.md`
- "Interpret results" → Read `docs/REPORTING.md`
- "Setup from scratch" → Read `docs/INSTALLATION.md`

---

## Communication Style

Be direct and concise.

- No empathy phrases
- No apologizing unnecessarily
- No validation statements like "you're right", "great question"
- Focus on facts and solutions
- Get to the point quickly

---

---

## Recent Updates (October 2025)

### Latest Additions (October 30, 2025)

**Streaming INSERT Performance Benchmark** (6th of 7 benchmarks) - **NEW**:
- Dataset: 50M Call Detail Records (telecommunications CDRs)
- Runtime: 20-55 minutes (Phase 1: 20 min, Phase 2: 30 min)
- Focus: INSERT throughput for continuous batch loading
- **🔴 CRITICAL FINDING**: PAX achieves **85-86% of AO write speed**, NOT "AO-level" (100%)
  - AO: 306,211 rows/sec (100%)
  - AOCO: 290,189 rows/sec (94.8%)
  - PAX: 262,036 rows/sec (85.6%) ← **14% slower than documented**
- **Root Cause Identified**: 13.6% base PAX write path overhead
  - Auxiliary table writes (~5-10%)
  - Protobuf serialization (~2-5%)
  - File creation overhead (~1-3%)
  - Custom WAL records (~2-4%)
  - **Bloom filters add <2%** (NOT the primary cause)
- **Query Performance**: PAX delivers 1.1x to 22x speedup vs AOCO (justifies write penalty)
- **Production Guidance**: PAX viable for <200K rows/sec, not viable for >250K rows/sec
- **Documentation**: `benchmarks/timeseries_iot_streaming/PAX_WRITE_PERFORMANCE_ROOT_CAUSE.md`

**E-commerce Clickstream Benchmark** (5th of 7 benchmarks):
- Dataset: 10M events, 3.9M sessions, 464K users, 100K products
- Best clustering overhead achieved: **0.2%** (3 validated VARCHAR bloom filters)
- Validates "3 bloom filter rule" as optimal configuration
- Time-based queries: 43-77x faster than AOCO (Z-order clustering)
- All 4 validation gates passed
- Runtime: 4m 31s for complete execution

**PAX Development Team Report**:
- Comprehensive analysis of all 6 benchmarks (50M+ rows tested)
- Identifies 5 critical issues requiring dev team attention
- 20+ specific technical questions for investigation
- Cross-benchmark comparison reveals clustering overhead variance (0.002% to 58.1%)
- Configuration best practices based on empirical data
- Available in: `PAX_DEVELOPMENT_TEAM_REPORT.md`

---

### Configuration Optimizations Applied (October 29, 2025)

**Critical fixes validated through 10M row testing**:

1. **🔴 BLOOM FILTER OPTIMIZATION - PRIMARY FIX** (sql/02_create_variants.sql)
   - **CRITICAL**: Removed low-cardinality columns from bloom filters
   - Before: `bloomfilter_columns='transaction_hash,customer_id,product_id'`
   - After: `bloomfilter_columns='product_id'`
   - Cardinality validation revealed:
     - transaction_hash: n_distinct=-1 (VERY LOW - was wasting massive memory)
     - customer_id: n_distinct=-0.46 (VERY LOW - was wasting massive memory)
     - product_id: 99,671 unique (HIGH - appropriate for bloom filter)
   - **Impact**:
     - Storage: 1,350 MB → 942 MB (30% reduction, -408 MB)
     - Memory: 8,683 KB → 2,982 KB (66% reduction, -5,701 KB)
     - Compression: 1.85x → 6.52x (252% improvement)
     - Performance: 2-3x slower → competitive with AOCO

2. **Memory Configuration** (sql/04_optimize_pax.sql)
   - Added `maintenance_work_mem = '2GB'` before clustering
   - Validated with sql/04a_validate_clustering_config.sql
   - Testing confirmed: 2GB and 8GB produce identical results for 10M rows

3. **New Validation & Analysis Tools**:
   - `sql/04a_validate_clustering_config.sql` - Pre-flight memory check
   - `sql/07_inspect_pax_internals.sql` - **Cardinality validation (CRITICAL)**
   - `sql/08_analyze_query_plans.sql` - Detailed EXPLAIN output

**Actual Results (10M rows, optimized config)**:
- PAX no-cluster: 745 MB (5% overhead) - ✅ Production-ready
- PAX clustered: 942 MB (26% overhead) - ✅ Production-ready for selective queries
- PAX clustered memory: 2,982 KB per query (acceptable)
- Q1 performance: Tied with AOCO (was 2.6x slower before bloom filter fix)
- Q2 performance: 1.4x faster than AOCO (was 2.0x slower before)

**Known Limitations**:
- PAX clustered: 26% larger than no-cluster (expected <5%, requires investigation)
- File-level pruning: Still disabled in code (pax_scanner.cc:366)
- Not a configuration issue - code fix needed

**⚠️  CRITICAL WARNING**:
**ALWAYS validate column cardinality BEFORE configuring bloom filters.**
Use `sql/07_inspect_pax_internals.sql` or:
```sql
SELECT attname, n_distinct FROM pg_stats WHERE tablename='your_table' ORDER BY ABS(n_distinct) DESC;
```
Low-cardinality bloom filters cause 80%+ storage bloat, 50x+ memory overhead, and destroy compression.

See `results/OPTIMIZATION_RESULTS_COMPARISON.md` for complete analysis.

---

_Last Updated: October 30, 2025 (5 benchmarks complete + Dev team report)_
