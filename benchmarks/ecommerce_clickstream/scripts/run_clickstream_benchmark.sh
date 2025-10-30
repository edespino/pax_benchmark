#!/bin/bash
#
# E-commerce Clickstream Benchmark - Master Automation Script
# Runs all 9 phases with validation gates
#

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BENCHMARK_DIR="$(dirname "$SCRIPT_DIR")"
SQL_DIR="$BENCHMARK_DIR/sql"
RESULTS_DIR="$BENCHMARK_DIR/results/run_$(date +%Y%m%d_%H%M%S)"

# Create results directory
mkdir -p "$RESULTS_DIR"

echo "===================================================="
echo "E-commerce Clickstream Benchmark Suite"
echo "===================================================="
echo ""
echo "Results will be saved to: $RESULTS_DIR"
echo ""

# Start timing
START_TIME=$(date +%s)

# Phase 0: Validation Framework
echo "Phase 0: Validation Framework Setup..."
psql -f "$SQL_DIR/00_validation_framework.sql" 2>&1 | tee "$RESULTS_DIR/00_validation.txt"
echo ""

# Phase 1: Schema Setup
echo "Phase 1: Schema Setup..."
psql -f "$SQL_DIR/01_setup_schema.sql" 2>&1 | tee "$RESULTS_DIR/01_schema.txt"
echo ""

# Phase 2: Cardinality Analysis
echo "Phase 2: Cardinality Analysis (1M sample)..."
psql -f "$SQL_DIR/02_analyze_cardinality.sql" 2>&1 | tee "$RESULTS_DIR/02_cardinality.txt"
echo ""

# Phase 3: Generate Configuration
echo "Phase 3: Generate Safe PAX Configuration..."
psql -f "$SQL_DIR/03_generate_config.sql" 2>&1 | tee "$RESULTS_DIR/03_config.txt"
echo ""

# Phase 4: Create Variants
echo "Phase 4: Create Storage Variants..."
psql -f "$SQL_DIR/04_create_variants.sql" 2>&1 | tee "$RESULTS_DIR/04_variants.txt"
echo ""

# Phase 5: Generate Data (10M events)
echo "Phase 5: Generate 10M Clickstream Events..."
echo "  (This will take 3-5 minutes)"
psql -f "$SQL_DIR/05_generate_data.sql" 2>&1 | tee "$RESULTS_DIR/05_data.txt"
echo ""

# Phase 6: Optimize PAX
echo "Phase 6: Optimize PAX with Z-order Clustering..."
echo "  (This will take 3-5 minutes)"
psql -f "$SQL_DIR/06_optimize_pax.sql" 2>&1 | tee "$RESULTS_DIR/06_optimize.txt"
echo ""

# Phase 7: Run Queries
echo "Phase 7: Running Benchmark Queries..."
echo "  Testing: AO, AOCO, PAX (clustered), PAX (no-cluster)"
echo ""

# Run queries on all 4 variants
for variant in clickstream_ao clickstream_aoco clickstream_pax clickstream_pax_nocluster; do
    echo "  Running queries on $variant..."
    sed "s/TABLE_VARIANT/$variant/g" "$SQL_DIR/07_run_queries.sql" | psql 2>&1 | tee "$RESULTS_DIR/07_queries_$variant.txt"
done
echo ""

# Phase 8: Collect Metrics
echo "Phase 8: Collecting Metrics..."
psql -f "$SQL_DIR/08_collect_metrics.sql" 2>&1 | tee "$RESULTS_DIR/08_metrics.txt"
echo ""

# Phase 9: Validate Results
echo "Phase 9: Validating Results..."
psql -f "$SQL_DIR/09_validate_results.sql" 2>&1 | tee "$RESULTS_DIR/09_validation.txt"
echo ""

# End timing
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo "===================================================="
echo "E-commerce Clickstream Benchmark Complete!"
echo "===================================================="
echo ""
echo "Total runtime: ${MINUTES}m ${SECONDS}s"
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "Key files:"
echo "  - 09_validation.txt: Final validation summary"
echo "  - 08_metrics.txt: Storage comparison"
echo "  - 07_queries_*.txt: Query results per variant"
echo ""
echo "Next steps:"
echo "  1. Review validation results: cat $RESULTS_DIR/09_validation.txt"
echo "  2. Compare storage sizes: grep 'PAX' $RESULTS_DIR/08_metrics.txt"
echo "  3. Analyze query performance: Compare timing across variant files"
echo ""
