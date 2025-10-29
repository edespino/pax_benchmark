# PAX Benchmark - Results Analysis and Reporting

Guide for analyzing benchmark results and creating compelling visualizations.

---

## Results Location

After running the benchmark, results are in:

```
results/run_YYYYMMDD_HHMMSS/
├── Phase1_Schema_*.log          # Schema creation logs
├── Phase2_Variants_*.log        # Table creation logs
├── Phase3_Data_*.log            # Data generation logs
├── Phase4_Optimize_*.log        # Clustering logs
├── Phase6_Metrics_*.log         # Metrics collection logs
├── queries/                     # Query execution logs
│   ├── sales_fact_ao_run1.log
│   ├── sales_fact_aoco_run1.log
│   └── sales_fact_pax_run1.log
├── aggregated_metrics.json      # Parsed results
├── comparison_table.md          # Performance comparison
└── BENCHMARK_REPORT.md          # Auto-generated report
```

---

## Parsing Results

### Automatic Parsing

```bash
# Parse EXPLAIN ANALYZE output
python3 scripts/parse_explain_results.py results/run_YYYYMMDD_HHMMSS/

# Creates:
# - aggregated_metrics.json (structured data)
# - comparison_table.md (human-readable)
```

### Manual Analysis

```bash
# View comparison table
cat results/run_YYYYMMDD_HHMMSS/comparison_table.md

# Query-by-query details
less results/run_YYYYMMDD_HHMMSS/queries/sales_fact_pax_run1.log

# Extract specific metrics
grep "Execution Time" results/run_YYYYMMDD_HHMMSS/queries/*.log
grep "Sparse filter" results/run_YYYYMMDD_HHMMSS/queries/sales_fact_pax*.log
```

---

## Generating Charts

### Option 1: Python Charts (Recommended)

```bash
# Generate all charts
python3 scripts/generate_charts.py results/run_YYYYMMDD_HHMMSS/

# Creates PNG files in results/run_YYYYMMDD_HHMMSS/charts/:
# - storage_comparison.png
# - query_performance.png
# - sparse_filter.png
# - compression_breakdown.png
# - zorder_impact.png
```

**Requires**: matplotlib, seaborn (`pip3 install matplotlib seaborn`)

### Option 2: Example Charts

```bash
# Generate charts with example data (before benchmark)
python3 scripts/generate_charts.py

# Useful for presentations/mockups
```

### Option 3: Custom Analysis

Use `aggregated_metrics.json` with your preferred tool:
- Excel/Google Sheets
- Tableau/PowerBI
- D3.js/Plotly
- Jupyter Notebook

---

## Key Metrics to Report

### 1. Storage Efficiency

**What to report**:
```sql
-- From sql/06_collect_metrics.sql results
SELECT
    'AO'   AS variant,
    pg_size_pretty(pg_total_relation_size('benchmark.sales_fact_ao')) AS size,

    'AOCO' AS variant,
    pg_size_pretty(pg_total_relation_size('benchmark.sales_fact_aoco')) AS size,

    'PAX'  AS variant,
    pg_size_pretty(pg_total_relation_size('benchmark.sales_fact_pax')) AS size;
```

**Key metric**: PAX size vs AOCO size (target: ≥30% reduction)

**Example**:
- AO: 95GB
- AOCO: 62GB (-35% vs AO)
- PAX: 41GB (-34% vs AOCO) ✅

### 2. Query Performance

**What to report**:
- Median execution time per query across 3 runs
- Average improvement across all 20 queries
- Category-specific improvements

**Key metric**: PAX avg time vs AOCO avg time (target: ≥25% faster)

**Example**:
- AO avg: 1500ms
- AOCO avg: 1187ms (-21% vs AO)
- PAX avg: 807ms (-32% vs AOCO) ✅

### 3. Sparse Filtering

**What to report**:
```bash
# Extract from PAX query logs
grep "Sparse filter" results/run_YYYYMMDD_HHMMSS/queries/sales_fact_pax*.log

# Look for: "skipped X files out of Y files"
```

**Key metrics**:
- File skip rate (target: ≥60%)
- I/O reduction
- Time savings

**Example**:
- Files skipped: 132/150 (88%) ✅
- I/O reduction: 10.5GB → 1.2GB (87%)
- Time savings: 3.2s → 0.4s (88%)

### 4. Z-Order Clustering

**What to report**:
- Multi-dimensional query speedup (Q7-Q9)
- Cache hit rate improvement
- Files scanned reduction

**Key metric**: Z-order speedup (target: 2-5x)

**Example**:
- Q7: 2800ms (AOCO) → 580ms (PAX) = 4.8x faster ✅
- Q8: 2500ms (AOCO) → 520ms (PAX) = 4.8x faster ✅
- Q9: 2900ms (AOCO) → 600ms (PAX) = 4.8x faster ✅

### 5. Per-Column Encoding

**What to report**:
```sql
-- From sql/06_collect_metrics.sql
SELECT column_name, encoding, compression_ratio
FROM column_encoding_effectiveness
ORDER BY compression_ratio DESC;
```

**Key insight**: Which columns benefit most from specific encodings

**Example**:
- `priority` (RLE): 23.1x compression
- `order_id` (delta): 8.2x compression
- `sale_date` (delta): 7.6x compression

---

## Visualization Templates

### Chart 1: Storage Comparison

**Type**: Bar chart
**Data**: Total size for AO, AOCO, PAX
**Message**: "PAX is 34% smaller than AOCO"

```
Storage Size (200M rows, 25 columns)

100GB ┤ ████████████████
      │ █  AO: 95GB   █
 75GB ┤ ████████████████
      │
 50GB ┤ ████████████
      │ █ AOCO: █
 25GB ┤ █ 62GB  █
      │ ████████
      │ █ PAX: █  ← 34% SMALLER
  0GB └──────────────────
```

### Chart 2: Query Performance by Category

**Type**: Grouped bar chart
**Data**: Average time per category for each variant
**Message**: "PAX is consistently faster across all categories"

```
Category                AO      AOCO    PAX
──────────────────────────────────────────
Sparse Filtering     1200ms   950ms   620ms  (-35%)
Bloom Filters        1400ms  1100ms   640ms  (-42%)
Z-Order Clustering   2800ms  2200ms  1150ms  (-48%)
Compression          1100ms   850ms   610ms  (-28%)
Complex Analytics    1600ms  1300ms  1010ms  (-22%)
MVCC Operations       900ms   720ms   590ms  (-18%)
──────────────────────────────────────────
OVERALL              1500ms  1187ms   807ms  (-32%)
```

### Chart 3: Sparse Filter Effectiveness

**Type**: Before/after comparison
**Data**: Files scanned, I/O, time
**Message**: "Sparse filtering skips 88% of files"

```
Without Sparse Filter          With Sparse Filter
┌───────────────────┐         ┌───────────────────┐
│ 150 files         │         │ Skipped: 132 ✗    │
│ 10.5 GB scanned   │    →    │ Read: 18 ✓        │
│ 3.2 seconds       │         │ 1.2 GB, 0.4s      │
└───────────────────┘         └───────────────────┘
                                8x LESS I/O!
```

### Chart 4: Compression by Encoding

**Type**: Horizontal bar chart
**Data**: Compression ratio per encoding type
**Message**: "Per-column encoding provides 2.2x better compression"

```
Column              Encoding    Ratio
─────────────────────────────────────────
priority            RLE        23.1x  █████████████████
status              RLE        14.3x  ████████████
order_id            delta       8.2x  ███████
sale_date           delta       7.6x  ███████
description         zstd(9)     3.9x  ███
total_amount        zstd(5)     2.3x  ██

Uniform encoding:    1.7x
Per-column optim:    3.8x  → 2.2x BETTER!
```

### Chart 5: Z-Order Impact

**Type**: Before/after comparison
**Data**: Files scanned, time
**Message**: "Z-order provides 5x speedup on multi-dimensional queries"

```
Unclustered             Z-Order Clustered
┌────────────────┐     ┌────────────────┐
│ Random data    │     │ Co-located     │
│ 120 files      │  →  │ 24 files       │
│ 2.8 seconds    │     │ 0.6 seconds    │
└────────────────┘     └────────────────┘
                        5x FASTER!
```

---

## Report Structure

### Executive Summary (1 page)

**Sections**:
1. **Objective**: Demonstrate PAX superiority
2. **Results**: 34% smaller, 32% faster, 88% skip rate
3. **Conclusion**: All success criteria met
4. **Recommendation**: Deploy PAX for OLAP workloads

**Key visuals**: Chart 1 (storage), Chart 2 (performance)

### Technical Details (2-3 pages)

**Sections**:
1. **Dataset**: 200M rows, 25 columns, realistic distributions
2. **Configuration**: PAX features enabled (zone maps, bloom filters, Z-order)
3. **Methodology**: 3 runs per query, median reported
4. **Results**: Detailed breakdown by category
5. **Analysis**: Why PAX outperforms

**Key visuals**: All 5 charts

### Appendix (optional)

**Sections**:
1. **Raw Data**: aggregated_metrics.json
2. **Query Logs**: Selected EXPLAIN ANALYZE outputs
3. **Configuration**: PAX table definitions, GUC settings
4. **Environment**: Cluster specs, software versions

---

## Presentation Guide

### For Business Stakeholders (5 minutes)

**Slides**:
1. **Problem**: Traditional storage limitations (AO, AOCO)
2. **Solution**: PAX intelligent optimization
3. **Results**: 34% storage savings, 32% performance gain
4. **ROI**: Lower costs, faster queries, better UX
5. **Next Steps**: Pilot deployment, production rollout

**Focus**: Cost savings, business impact

### For Technical Audience (15 minutes)

**Slides**:
1. **Architecture**: 5-layer PAX design
2. **Features**: Encoding, filtering, clustering
3. **Benchmark Setup**: Dataset, queries, methodology
4. **Storage Results**: Compression effectiveness
5. **Performance Results**: Query speedup by category
6. **Sparse Filtering**: File pruning demonstration
7. **Z-Order Clustering**: Multi-dimensional benefits
8. **Encoding Analysis**: Per-column optimization
9. **Lessons Learned**: Configuration best practices
10. **Production Readiness**: Yandex Cloud, TPC results

**Focus**: Technical depth, how it works

### For Database Administrators (10 minutes)

**Slides**:
1. **PAX Overview**: What it is, why it matters
2. **Configuration**: Table creation, encoding selection
3. **GUC Parameters**: Tuning knobs
4. **Clustering**: When and how to cluster
5. **Monitoring**: Metrics to track
6. **Troubleshooting**: Common issues, solutions
7. **Migration**: Steps to adopt PAX
8. **Best Practices**: Lessons from benchmark

**Focus**: Practical deployment, operations

---

## SQL Queries for Analysis

### Storage Comparison

```sql
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'benchmark'
  AND tablename LIKE 'sales_fact_%'
ORDER BY tablename;
```

### PAX File Statistics

```sql
-- File-level stats
SELECT
    ptfileid,
    ptsize,
    ptnumrows,
    ptisclustered,
    statistics
FROM get_pax_aux_table('benchmark.sales_fact_pax')
ORDER BY ptfileid
LIMIT 10;

-- Summary
SELECT
    COUNT(*) AS num_files,
    SUM(ptsize) AS total_size,
    SUM(ptnumrows) AS total_rows,
    AVG(ptnumrows) AS avg_rows_per_file,
    COUNT(*) FILTER (WHERE ptisclustered) AS clustered_files
FROM get_pax_aux_table('benchmark.sales_fact_pax');
```

### Compression Analysis

```sql
-- Estimate uncompressed size (rough)
SELECT
    attname AS column_name,
    pg_size_pretty(
        pg_total_relation_size('benchmark.sales_fact_pax') *
        attnum::float / (SELECT COUNT(*) FROM pg_attribute WHERE attrelid = 'benchmark.sales_fact_pax'::regclass)
    ) AS est_compressed_size
FROM pg_attribute
WHERE attrelid = 'benchmark.sales_fact_pax'::regclass
  AND attnum > 0
  AND NOT attisdropped
ORDER BY attnum;
```

---

## Sharing Results

### Internal Report

Create markdown report:
```bash
cat results/run_YYYYMMDD_HHMMSS/comparison_table.md
# Copy charts
# Add commentary
```

### External Presentation

Export charts as PNG:
```bash
python3 scripts/generate_charts.py results/run_YYYYMMDD_HHMMSS/
# Charts saved to results/run_YYYYMMDD_HHMMSS/charts/

# Create PowerPoint/Keynote with charts
# Use template from docs/archive/VISUAL_PRESENTATION.md
```

### Community Sharing

Package results:
```bash
cd results/run_YYYYMMDD_HHMMSS/
tar -czf pax_benchmark_results_$(date +%Y%m%d).tar.gz \
    comparison_table.md \
    aggregated_metrics.json \
    BENCHMARK_REPORT.md \
    charts/

# Share tarball on GitHub, forums, etc.
```

---

## Success Criteria Checklist

After analysis, verify all criteria met:

- [ ] **Storage**: PAX ≥ 30% smaller than AOCO
- [ ] **Performance**: PAX ≥ 25% faster than AOCO
- [ ] **Sparse Filter**: ≥ 60% file skip rate
- [ ] **Z-Order**: 2-5x speedup on multi-dimensional queries

If any criterion not met:
1. Review configuration (encoding, statistics, clustering)
2. Check data distribution (realistic patterns?)
3. Verify queries target PAX features
4. Consult `docs/CONFIGURATION_GUIDE.md`

---

## Troubleshooting Results

### Low Compression Ratio

**Symptom**: PAX < 20% smaller than AOCO

**Check**:
1. Per-column encoding configured? (`\d+ table`)
2. Appropriate encodings chosen? (delta for sequential, RLE for low cardinality)
3. Compression level too low? (Try zstd level 9)

**Solution**: Review `docs/CONFIGURATION_GUIDE.md`, adjust encodings

### Poor Query Performance

**Symptom**: PAX not significantly faster than AOCO

**Check**:
1. Sparse filtering enabled? (`SET pax.enable_sparse_filter = on`)
2. Zone maps/bloom filters configured? (`\d+ table`)
3. Table clustered? (`SELECT ptisclustered FROM get_pax_aux_table(...)`)
4. Queries selective enough? (Sparse filter needs WHERE clauses)

**Solution**: Review Phase 4 logs, re-run clustering if needed

### Low Sparse Filter Skip Rate

**Symptom**: < 50% files skipped

**Check**:
1. Statistics on correct columns? (min/max on filtered columns)
2. Queries use statistics columns? (WHERE sale_date = ...)
3. Data distribution suitable? (Not all values in all files)

**Solution**: Verify statistics configuration, adjust queries

---

## Additional Resources

- **Archive Documentation**: `docs/archive/VISUAL_PRESENTATION.md` (detailed chart templates)
- **Configuration Guide**: `docs/CONFIGURATION_GUIDE.md` (tuning advice)
- **Technical Details**: `docs/TECHNICAL_ARCHITECTURE.md` (understand internals)

---

**Ready to create compelling PAX performance reports!**
