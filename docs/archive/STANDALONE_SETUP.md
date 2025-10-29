# PAX Benchmark - Standalone Repository Setup

## Overview

This is a **standalone repository** containing a comprehensive benchmark suite for demonstrating PAX storage superiority over AO/AOCO in Apache Cloudberry.

**Repository**: `/Users/eespino/workspace/edespino/pax_benchmark`

---

## Prerequisites

### 1. Apache Cloudberry with PAX Extension

This benchmark requires Cloudberry built with PAX support:

```bash
# Clone Cloudberry
git clone https://github.com/apache/cloudberry.git
cd cloudberry

# Configure with PAX
./configure --enable-pax --with-perl --with-python --with-libxml \
    --with-gssapi --prefix=/usr/local/cloudberry

# Initialize submodules (required for PAX)
git submodule update --init --recursive

# Build
make -j8
make -j8 install

# Create demo cluster
make create-demo-cluster
source gpAux/gpdemo/gpdemo-env.sh
```

### 2. Verify PAX Installation

```bash
# Check PAX is available
psql -c "SELECT amname FROM pg_am WHERE amname = 'pax';"

# Should return:
#  amname
# --------
#  pax
# (1 row)
```

### 3. Python Dependencies (Optional - for charts)

```bash
pip3 install matplotlib seaborn
```

---

## Quick Start

### One-Command Execution

```bash
cd /Users/eespino/workspace/edespino/pax_benchmark
./scripts/run_full_benchmark.sh
```

**Runtime**: 2-4 hours
**Disk Required**: ~300GB
**Output**: `results/run_YYYYMMDD_HHMMSS/`

---

## Repository Structure

```
pax_benchmark/                          # This repository
├── README.md                           # Main documentation
├── QUICK_REFERENCE.md                  # One-page cheat sheet
├── COMPLETE_SUMMARY.md                 # Full delivery summary
├── STANDALONE_SETUP.md                 # This file
│
├── docs/
│   ├── TECHNICAL_ARCHITECTURE.md       # PAX internals (2,450+ lines)
│   ├── METHODOLOGY.md                  # Scientific methodology
│   └── CONFIGURATION_GUIDE.md          # Production best practices
│
├── sql/
│   ├── 01_setup_schema.sql            # Create schema + dimensions
│   ├── 02_create_variants.sql         # AO/AOCO/PAX tables
│   ├── 03_generate_data.sql           # 200M rows
│   ├── 04_optimize_pax.sql            # Clustering + GUCs
│   ├── 05_queries_ALL.sql             # 20 benchmark queries
│   └── 06_collect_metrics.sql         # Results collection
│
├── scripts/
│   ├── run_full_benchmark.sh          # Master automation
│   ├── parse_explain_results.py       # Results parser
│   └── generate_charts.py             # Chart generator
│
├── visuals/
│   ├── diagrams/                       # Architecture diagrams (3 PNGs)
│   └── charts/                         # Generated charts (on-demand)
│
└── results/                            # Generated during execution
```

---

## Connection to Cloudberry Source

### Required: Cloudberry Installation

This benchmark **requires** Apache Cloudberry to be installed with PAX:

```bash
# The benchmark connects to a running Cloudberry cluster
# Default connection: localhost:5432

# Environment variables (optional):
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=postgres
export PGUSER=gpadmin
```

### No Source Code Dependency

This repository is **self-contained** for benchmark execution:
- ✅ All SQL scripts included
- ✅ All automation scripts included
- ✅ All documentation included
- ✅ No need to access Cloudberry source tree

### Reference Documentation

For PAX source code and internals:
```bash
# In Cloudberry repository:
cd cloudberry/contrib/pax_storage/

# Documentation:
less README.md
less doc/README.format.md
less doc/README.clustering.md
less doc/README.filter.md
```

---

## Execution Workflow

### Option 1: Automated (Recommended)

```bash
cd /Users/eespino/workspace/edespino/pax_benchmark
./scripts/run_full_benchmark.sh
```

This will:
1. Create schema + dimension tables (5-10 min)
2. Create AO/AOCO/PAX variants (2 min)
3. Generate 200M rows × 3 variants (30-60 min)
4. Optimize PAX with clustering (10-20 min)
5. Run 20 queries × 3 variants × 3 runs (60-120 min)
6. Collect and analyze metrics (5 min)

### Option 2: Manual Phase-by-Phase

```bash
psql -f sql/01_setup_schema.sql
psql -f sql/02_create_variants.sql
psql -f sql/03_generate_data.sql
psql -f sql/04_optimize_pax.sql

# Run queries on each variant
for variant in ao aoco pax; do
  sed "s/TABLE_VARIANT/sales_fact_${variant}/g" sql/05_queries_ALL.sql | psql
done

psql -f sql/06_collect_metrics.sql
```

---

## Results Analysis

### Generated Outputs

```
results/run_YYYYMMDD_HHMMSS/
├── Phase1_Schema_*.log
├── Phase2_Variants_*.log
├── Phase3_Data_*.log
├── Phase4_Optimize_*.log
├── Phase6_Metrics_*.log
├── queries/
│   ├── sales_fact_ao_run1.log
│   ├── sales_fact_aoco_run1.log
│   └── sales_fact_pax_run1.log
├── aggregated_metrics.json
├── comparison_table.md
└── BENCHMARK_REPORT.md
```

### Parse Results

```bash
# Extract metrics from logs
python3 scripts/parse_explain_results.py results/run_YYYYMMDD_HHMMSS/

# Generate charts
python3 scripts/generate_charts.py results/run_YYYYMMDD_HHMMSS/
```

---

## Customization

### Adjust Dataset Size

Edit `sql/03_generate_data.sql`:

```sql
-- Change from 200M to 50M rows
-- Line ~20: FROM generate_series(1, 200000000) gs
-- Change to: FROM generate_series(1, 50000000) gs
```

### Modify PAX Configuration

Edit `sql/02_create_variants.sql`:

```sql
CREATE TABLE benchmark.sales_fact_pax (...) USING pax WITH (
    -- Adjust these parameters:
    compresstype='zstd',
    compresslevel=5,
    minmax_columns='your,columns',
    bloomfilter_columns='your,columns',
    cluster_columns='your,columns'
);
```

### Add Custom Queries

Edit `sql/05_queries_ALL.sql`:

```sql
-- Add your query at the end
-- Q21: Your custom query
\echo 'Q21: Custom query description'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT ... FROM benchmark.TABLE_VARIANT WHERE ...;
```

---

## Sharing Results

### Git Repository

```bash
cd /Users/eespino/workspace/edespino/pax_benchmark

# Initialize (if not already)
git init
git add .
git commit -m "Initial PAX benchmark suite"

# Push to GitHub/GitLab
git remote add origin <your-repo-url>
git push -u origin main
```

### Share Results Only

```bash
# Results are gitignored by default
# To share, create a report:
cd results/run_YYYYMMDD_HHMMSS/
tar -czf pax_benchmark_results_$(date +%Y%m%d).tar.gz \
    comparison_table.md aggregated_metrics.json BENCHMARK_REPORT.md

# Share the tarball
```

---

## Troubleshooting

### "PAX extension not found"

```bash
# Rebuild Cloudberry with --enable-pax
cd /path/to/cloudberry
./configure --enable-pax ...
make clean && make -j8 && make install
```

### "Out of disk space"

```bash
# Check available space (need ~300GB)
df -h

# Or reduce dataset size in sql/03_generate_data.sql
```

### "Connection refused"

```bash
# Ensure Cloudberry cluster is running
source /usr/local/cloudberry/greenplum_path.sh
source gpAux/gpdemo/gpdemo-env.sh

# Check status
psql -c "SELECT version();"
```

### "Charts not generating"

```bash
# Install dependencies
pip3 install matplotlib seaborn

# Or use ASCII charts in VISUAL_PRESENTATION.md
```

---

## Contributing

### Report Issues

Found a bug or have a suggestion?

1. Open an issue in this repository
2. Include:
   - Cloudberry version
   - Benchmark phase where issue occurred
   - Error messages or logs
   - Expected vs actual behavior

### Improve Documentation

```bash
# Edit documentation
vim docs/CONFIGURATION_GUIDE.md

# Commit changes
git add docs/CONFIGURATION_GUIDE.md
git commit -m "docs: improve PAX configuration examples"
```

### Add Features

```bash
# Create feature branch
git checkout -b feature/new-query-category

# Make changes
vim sql/05_queries_ALL.sql

# Test
./scripts/run_full_benchmark.sh

# Submit pull request
```

---

## References

### This Repository
- **GitHub**: `<your-repo-url>`
- **Issues**: `<your-repo-url>/issues`

### Apache Cloudberry
- **Website**: https://cloudberry.apache.org
- **GitHub**: https://github.com/apache/cloudberry
- **PAX Source**: `cloudberry/contrib/pax_storage/`

### Documentation
- **TPC-H Results**: `cloudberry/contrib/pax_storage/doc/performance.md`
- **PAX Format**: `cloudberry/contrib/pax_storage/doc/README.format.md`
- **Clustering**: `cloudberry/contrib/pax_storage/doc/README.clustering.md`

---

## License

Apache License 2.0 (same as Apache Cloudberry)

---

## Acknowledgments

- **Apache Cloudberry Community** - PAX implementation
- **Leonid Borchuk** - PAX architecture and PGConf presentation
- **Yandex Cloud** - Production validation

---

**This standalone repository contains everything needed to benchmark PAX storage performance!**

_Last Updated: October 28, 2025_
