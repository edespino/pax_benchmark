# PAX Benchmark - Quick Reference Card

**One-page guide for quick execution and reference**

---

## ⚡ Quick Start

### Fast Benchmarks (2-6 minutes)
```bash
cd /home/cbadmin/bom-parts/pax_benchmark

# IoT time-series (10M sensor readings, 2-5 min)
cd benchmarks/timeseries_iot && ./scripts/run_iot_benchmark.sh

# Financial trading (10M ticks, 4-8 min, high-cardinality)
cd benchmarks/financial_trading && ./scripts/run_trading_benchmark.sh

# Log analytics (10M logs, 3-6 min, sparse columns / APM)
cd benchmarks/log_analytics && ./scripts/run_log_benchmark.sh

# View results
cat results/run_*/09_validation.txt
```

### Comprehensive Benchmark (2-4 hours)
```bash
cd benchmarks/retail_sales

# 1. Run full benchmark (200M rows, 2-4 hours)
./scripts/run_full_benchmark.sh

# 2. Generate charts (optional - requires matplotlib)
python3 scripts/generate_charts.py results/run_*/

# 3. View results
cat results/run_*/BENCHMARK_REPORT.md
```

**See `benchmarks/README.md`** for detailed comparison and workload selection guide.

---

## 📁 File Navigation

| Need | File |
|------|------|
| **Quick start** | `README.md` |
| **Choose benchmark** | `benchmarks/README.md` |
| **Installation** | `docs/INSTALLATION.md` |
| **Run fast benchmark** | `benchmarks/{iot\|trading\|logs}/scripts/run_*.sh` |
| **Run comprehensive** | `benchmarks/retail_sales/scripts/run_full_benchmark.sh` |
| **Analyze results** | `docs/REPORTING.md` |
| **Technical details** | `docs/TECHNICAL_ARCHITECTURE.md` |
| **Configuration tips** | `docs/CONFIGURATION_GUIDE.md` |
| **Phase-by-phase** | `benchmarks/{name}/sql/*.sql` (9 phases) |

---

## 🎯 Expected Results Cheat Sheet

### Retail Sales (200M rows)
| Metric | Target | Location |
|--------|--------|----------|
| **Storage reduction** | -34% | `benchmarks/retail_sales/sql/06_collect_metrics.sql` |
| **Query speedup** | -32% | `results/*/comparison_table.md` |
| **File skip rate** | 88% | Check PAX logs (enable debug) |
| **Z-order speedup** | 5x | Category C queries (Q7-Q9) |

### Fast Benchmarks (10M rows)
| Benchmark | Key Result | Location |
|-----------|------------|----------|
| **IoT** | Time-series filtering | `benchmarks/timeseries_iot/results/run_*/09_validation.txt` |
| **Trading** | High-cardinality bloom | `benchmarks/financial_trading/results/run_*/09_validation.txt` |
| **Logs** | Sparse columns (95% NULL) | `benchmarks/log_analytics/results/run_*/09_validation.txt` |

---

## 🔧 Key PAX Configuration

```sql
-- Create optimized PAX table
CREATE TABLE my_table (...) USING pax WITH (
    compresstype='zstd', compresslevel=5,

    -- MinMax: Use for ALL filterable columns (low overhead)
    minmax_columns='date,id,amount,region,status',  -- 6-12 recommended

    -- Bloom: ONLY high-cardinality (>1000 distinct) columns
    bloomfilter_columns='transaction_id,customer_id',  -- 2-4 high-card only

    cluster_type='zorder',
    cluster_columns='date,region',              -- 2-3 correlated columns
    storage_format='porc'
);

-- Per-column encoding (if supported in your PAX version)
ALTER TABLE my_table
    ALTER COLUMN id SET ENCODING (compresstype=delta),
    ALTER COLUMN status SET ENCODING (compresstype=RLE_TYPE);

-- CRITICAL: Set memory BEFORE clustering (prevents 2-3x storage bloat)
SET maintenance_work_mem = '2GB';   -- For 10M rows
SET maintenance_work_mem = '8GB';   -- For 200M rows

-- Cluster data
CLUSTER my_table;

-- Optimal GUCs for queries
SET pax.enable_sparse_filter = on;
SET pax.enable_row_filter = off;  -- For OLAP
SET pax.max_tuples_per_file = 1310720;  -- Default: 1.31M tuples
SET pax.max_size_per_file = 67108864;   -- Default: 64MB
SET pax.bloom_filter_work_memory_bytes = 104857600;  -- 100MB for high-cardinality
```

---

## 📊 Query Categories Reference

| Category | Queries | Tests |
|----------|---------|-------|
| **A** | Q1-Q3 | Sparse filtering (zone maps) |
| **B** | Q4-Q6 | Bloom filters |
| **C** | Q7-Q9 | Z-order clustering |
| **D** | Q10-Q12 | Compression efficiency |
| **E** | Q13-Q15 | Complex analytics |
| **F** | Q16-Q18 | MVCC operations |
| **G** | Q19-Q20 | Edge cases |

---

## 🛠️ Troubleshooting Quick Fixes

| Problem | Solution |
|---------|----------|
| **PAX not found** | Build with `--enable-pax` |
| **Out of disk space** | Need 300GB free |
| **Slow data generation** | Normal - takes 30-60 min |
| **Charts not generating** | `pip install matplotlib seaborn` |
| **Permission denied** | `chmod +x scripts/*.sh scripts/*.py` |

---

## 📞 Quick Help

| Question | Answer |
|----------|--------|
| **How long?** | 2-4 hours total |
| **Disk needed?** | ~300GB |
| **Can I stop?** | Yes - run phases separately |
| **Parallel execution?** | Each phase is serial, but queries run 3x |
| **Re-run safe?** | Yes - creates new timestamped directory |

---

## 🎨 Generate Visuals Now

```bash
# Example charts (before benchmark)
python3 scripts/generate_charts.py

# Real charts (after benchmark)
python3 scripts/generate_charts.py results/run_YYYYMMDD_HHMMSS/

# View
ls -lh visuals/charts/*.png
```

---

## 📖 Documentation Quick Links

- **README.md** - Start here
- **benchmarks/README.md** - Benchmark selection guide
- **QUICK_REFERENCE.md** - This file
- **docs/INSTALLATION.md** - Setup instructions
- **docs/REPORTING.md** - Results analysis
- **docs/TECHNICAL_ARCHITECTURE.md** - Deep dive (2,450 lines)
- **docs/METHODOLOGY.md** - How to reproduce
- **docs/CONFIGURATION_GUIDE.md** - How to tune PAX
- **PAX_BENCHMARK_SUITE_PLAN.md** - Implementation roadmap
- **docs/archive/** - Historical documentation

---

## 🚀 Manual Phase-by-Phase Execution

### Retail Sales (Comprehensive)
```bash
cd benchmarks/retail_sales

psql -f sql/01_setup_schema.sql       # 5-10 min
psql -f sql/02_create_variants.sql    # 2 min
psql -f sql/03_generate_data.sql      # 30-60 min ⏰
psql -f sql/04_optimize_pax.sql       # 10-20 min ⏰

# Run queries manually (or use run_full_benchmark.sh)
# For each variant: sales_fact_ao, sales_fact_aoco, sales_fact_pax
# sed 's/TABLE_VARIANT/sales_fact_pax/g' sql/05_queries_ALL.sql | psql

psql -f sql/06_collect_metrics.sql    # 5 min
```

### Fast Benchmarks (IoT / Trading / Logs)
```bash
cd benchmarks/{timeseries_iot|financial_trading|log_analytics}

# All phases (automated via run_*.sh)
psql -f sql/00_validation_framework.sql  # 1-2 min
psql -f sql/01_setup_schema.sql          # 30 sec
psql -f sql/02_analyze_cardinality.sql   # 30 sec (1M sample)
psql -f sql/03_generate_config.sql       # 10 sec
psql -f sql/04_create_variants.sql       # 1 min
psql -f sql/05_generate_data.sql         # 1-2 min (10M rows)
psql -f sql/06_optimize_pax.sql          # 1-2 min
psql -f sql/07_run_queries.sql           # 30 sec
psql -f sql/08_collect_metrics.sql       # 30 sec
psql -f sql/09_validate_results.sql      # 30 sec
```

---

## 🧪 Small-Scale Testing (4-Variant Approach)

**For incremental testing, debugging, or isolating clustering effects:**

### Why 4 Variants?
- **AO**: Row-oriented baseline
- **AOCO**: Column-oriented baseline (current best practice)
- **PAX (clustered)**: PAX with Z-order clustering
- **PAX (no-cluster)**: PAX without clustering (control group)

The 4th variant isolates clustering impact on storage and performance.

### Quick 10M Row Test (2-3 minutes)

```bash
# Clean start
psql postgres -c "DROP SCHEMA IF EXISTS benchmark CASCADE; CREATE SCHEMA benchmark;"

# Run all phases with small dataset
psql postgres -f sql/01_setup_schema.sql && \
psql postgres -f sql/02_create_variants.sql && \
psql postgres -f sql/03_generate_data_SMALL.sql && \
psql postgres -f sql/04a_validate_clustering_config.sql && \
psql postgres -f sql/04_optimize_pax.sql && \
psql postgres -f sql/05_test_sample_queries.sql && \
psql postgres -f sql/06_collect_metrics.sql
```

### Adjust Dataset Size
Edit `sql/03_generate_data_SMALL.sql` (line ~30):
```sql
-- Change 10M to desired size
FROM generate_series(1, 10000000) gs;  -- 100K, 1M, 10M, 50M...
```

### Expected Results (10M rows)

**With OLD Configuration** (before optimization):
| Variant | Storage | Speed vs AOCO | Memory |
|---------|---------|---------------|--------|
| **AO** | 1,128 MB | 3.5x slower | 345 KB |
| **AOCO** | 710 MB | Baseline | 538 KB |
| **PAX (clustered)** | 2,000 MB ❌ | 1.3x slower | 16,390 KB ❌ |
| **PAX (no-cluster)** | 752 MB ✅ | 2.0x slower | 149 KB ✅ |

**Root Cause**: Low maintenance_work_mem (64MB) → clustering spills → 2.66x bloat

**With OPTIMIZED Configuration** (updated sql/04_optimize_pax.sql):
| Variant | Storage | Speed vs AOCO | Memory |
|---------|---------|---------------|--------|
| **AO** | 1,128 MB | 3.5x slower | 345 KB |
| **AOCO** | 710 MB | Baseline | 538 KB |
| **PAX (clustered)** | ~780 MB ✅ | 1.5-2x slower ⚠️ | ~600 KB ✅ |
| **PAX (no-cluster)** | 752 MB ✅ | 2.0x slower ⚠️ | 149 KB ✅ |

**Note**: Queries still 1.5-2x slower due to file-level pruning disabled in code

### Capture Test Configuration
```bash
# Get cluster topology
psql postgres -c "SELECT * FROM gp_segment_configuration ORDER BY content, role;"

# Get Cloudberry version
psql postgres -c "SELECT version();"

# Check PAX extension
psql postgres -c "SELECT amname FROM pg_am WHERE amname = 'pax';"
```

### Viewing Results
```bash
# Quick summary
cat results/QUICK_SUMMARY.md

# Full analysis
cat results/4-variant-test-10M-rows.md

# Configuration log
cat results/test-config-2025-10-29.log
```

### Scaling Strategy
1. Start: **100K rows** (test setup, ~10 seconds)
2. Scale: **1M rows** (verify queries work, ~30 seconds)
3. Validate: **10M rows** (production-like behavior, ~2 minutes)
4. Full test: **200M rows** (run_full_benchmark.sh, 2-4 hours)

---

## 💡 Pro Tips

1. **Validate memory BEFORE clustering** (prevents storage bloat):
   ```bash
   psql -f sql/04a_validate_clustering_config.sql
   ```

2. **Enable debug** to see sparse filtering in action:
   ```sql
   SET pax.enable_debug = on;
   SET client_min_messages = LOG;
   ```

3. **Check clustering status** (if introspection functions available):
   ```sql
   SELECT ptisclustered, COUNT(*)
   FROM get_pax_aux_table('my_table')
   GROUP BY ptisclustered;
   ```

4. **Inspect PAX internals** (statistics, cardinality):
   ```bash
   psql -f sql/07_inspect_pax_internals.sql
   ```

5. **Analyze query plans** (detailed EXPLAIN output):
   ```bash
   psql -f sql/08_analyze_query_plans.sql
   ```

6. **Monitor progress** during data generation:
   ```bash
   watch "psql -c \"SELECT COUNT(*) FROM benchmark.sales_fact_pax\""
   ```

7. **Quick size check**:
   ```sql
   SELECT
     'PAX' AS variant,
     pg_size_pretty(pg_total_relation_size('benchmark.sales_fact_pax'))
   UNION ALL
   SELECT 'AOCO',
     pg_size_pretty(pg_total_relation_size('benchmark.sales_fact_aoco'));
   ```

---

## 🎯 Success Criteria Checklist

- [ ] PAX is 30%+ smaller than AOCO
- [ ] PAX is 25%+ faster than AOCO (average)
- [ ] Sparse filter skips 60%+ of files
- [ ] Z-order queries show 2-5x speedup
- [ ] All 20 queries execute successfully
- [ ] Results are reproducible

---

## 📦 What Gets Created

```
results/run_YYYYMMDD_HHMMSS/
├── Phase1_Schema_*.log
├── Phase2_Variants_*.log
├── Phase3_Data_*.log
├── Phase4_Optimize_*.log
├── Phase6_Metrics_*.log
├── queries/
│   ├── sales_fact_ao_run1.log
│   ├── sales_fact_ao_run2.log
│   ├── sales_fact_ao_run3.log
│   ├── sales_fact_aoco_run1.log
│   ├── sales_fact_aoco_run2.log
│   ├── sales_fact_aoco_run3.log
│   ├── sales_fact_pax_run1.log
│   ├── sales_fact_pax_run2.log
│   └── sales_fact_pax_run3.log
├── aggregated_metrics.json
├── comparison_table.md
└── BENCHMARK_REPORT.md
```

### Small-Scale Testing Results

When running 4-variant testing (manual execution):
```
results/
├── QUICK_SUMMARY.md                   # Executive summary
├── 4-variant-test-10M-rows.md         # Full analysis (15 pages)
└── test-config-2025-10-29.log         # Reproduction guide
```

**Note**: run_full_benchmark.sh only tests 3 variants. For 4-variant testing, use manual execution as documented in the "Small-Scale Testing" section above.

---

## 🔗 External Resources

- **Cloudberry**: https://cloudberry.apache.org
- **GitHub**: https://github.com/apache/cloudberry
- **Issues**: https://github.com/apache/cloudberry/issues
- **PAX Docs**: `contrib/pax_storage/README.md`

---

**Print this card for quick reference during benchmark execution!**

_Last Updated: October 29, 2025_
