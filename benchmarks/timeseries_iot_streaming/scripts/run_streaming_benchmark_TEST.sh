#!/bin/bash
#
# Streaming INSERT Benchmark - QUICK TEST VERSION
# Tests INSERT throughput with 10 batches per phase (instead of 500)
# Runtime: ~5-10 minutes total (vs 3.5-4.5 hours for full benchmark)
#
# This script demonstrates the COMPLETE workflow:
#   - Validation framework
#   - Cardinality analysis
#   - Configuration generation
#   - Table creation
#   - Phase 1: 10 batches, no indexes
#   - PAX optimization
#   - Query performance tests
#   - Metrics collection
#   - Validation
#   - Phase 2: 10 batches, with indexes (5 per variant)
#   - All reporting scripts
#

set -e  # Exit on error

# Detect and change to correct directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(dirname "$SCRIPT_DIR")"

# Change to benchmark directory (scripts run from there)
cd "$BENCHMARK_DIR"

echo "Working directory: $(pwd)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PSQL_CMD="psql postgres"
RESULTS_DIR="results/test_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${RESULTS_DIR}/benchmark.log"
TIMING_FILE="${RESULTS_DIR}/timing.txt"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Timing tracking
BENCHMARK_START=$(date +%s)
declare -A PHASE_TIMES

# Logging functions
log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠️  WARNING:${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +%H:%M:%S)] ❌ ERROR:${NC} $1" | tee -a "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}[$(date +%H:%M:%S)] ✅${NC} $1" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}[$(date +%H:%M:%S)] ℹ️ ${NC} $1" | tee -a "${LOG_FILE}"
}

# Phase execution helper
run_phase() {
    local phase_num=$1
    local phase_name=$2
    local sql_file=$3
    local log_file=$4

    log "Phase ${phase_num}: ${phase_name}..."

    local start=$(date +%s)
    # Use tee to show output on screen AND save to log file
    ${PSQL_CMD} -f "${sql_file}" 2>&1 | tee "${log_file}"
    local exit_code=${PIPESTATUS[0]}
    local end=$(date +%s)
    local duration=$((end - start))

    PHASE_TIMES["phase_${phase_num}"]=$duration

    if [ $exit_code -eq 0 ]; then
        success "${phase_name} completed in ${duration}s"
        echo "Phase ${phase_num} (${phase_name}): ${duration}s" >> "${TIMING_FILE}"
    else
        error "${phase_name} failed"
        return $exit_code
    fi

    echo ""
    return 0
}

# Header
echo ""
echo "==========================================================="
echo "  Streaming INSERT Benchmark - QUICK TEST (10 batches)"
echo "==========================================================="
echo ""
echo "Test Scenario:"
echo "  📊 Dataset: 1M rows per phase (10 batches × ~100K rows)"
echo "  🔄 Traffic: Simplified pattern"
echo "  📈 Batch size: Fixed 100K per batch"
echo "  ⏱️  Runtime: ~5-10 minutes (vs 3.5-4.5 hrs for full)"
echo ""
echo "What this tests:"
echo "  ✅ Complete workflow (validation → inserts → queries → metrics)"
echo "  ✅ Phase 1: Pure INSERT speed (no indexes)"
echo "  ✅ Phase 2: INSERT with index maintenance"
echo "  ✅ All reporting and validation scripts"
echo "  ✅ PROCEDURE with per-batch commits"
echo ""
echo "Results will be saved to: ${RESULTS_DIR}"
echo ""

# =====================================================
# Phase 0: Validation Framework Setup
# =====================================================

run_phase 0 "Validation Framework Setup" \
    "sql/00_validation_framework.sql" \
    "${RESULTS_DIR}/00_validation_framework.log" || exit 1

# =====================================================
# Phase 1: Schema Setup
# =====================================================

run_phase 1 "CDR Schema Setup (10K cell towers)" \
    "sql/01_setup_schema.sql" \
    "${RESULTS_DIR}/01_setup_schema.log" || exit 1

# =====================================================
# Phase 2: CRITICAL - Cardinality Analysis
# SAFETY GATE #1: Validate bloom filter candidates
# =====================================================

log "Phase 2: 🔍 CRITICAL - Cardinality Analysis (1M sample)..."
run_phase 2 "Cardinality Analysis" \
    "sql/02_analyze_cardinality.sql" \
    "${RESULTS_DIR}/02_cardinality_analysis.txt" || exit 1

# Check for UNSAFE bloom filter candidates
UNSAFE_COUNT=$(grep -c "❌ UNSAFE" "${RESULTS_DIR}/02_cardinality_analysis.txt" || true)
if [ "$UNSAFE_COUNT" -gt 0 ]; then
    warn "Found ${UNSAFE_COUNT} columns marked UNSAFE for bloom filters"
    warn "These columns will be EXCLUDED from bloom filter configuration"
else
    success "All proposed bloom filter columns passed validation"
fi

echo ""

# =====================================================
# Phase 3: Generate Safe Configuration
# SAFETY GATE #2: Auto-generate config from analysis
# =====================================================

run_phase 3 "Auto-Generate Safe Configuration" \
    "sql/03_generate_config.sql" \
    "${RESULTS_DIR}/03_generated_config.sql" || exit 1

# =====================================================
# Phase 4: Create Table Variants
# =====================================================

run_phase 4 "Create Storage Variants (AO/AOCO/PAX/PAX-no-cluster)" \
    "sql/04_create_variants.sql" \
    "${RESULTS_DIR}/04_create_variants.log" || exit 1

# =====================================================
# PHASE 1: STREAMING INSERTS (NO INDEXES) - 10 BATCHES
# =====================================================

echo ""
echo "==========================================================="
echo "  PHASE 1: Streaming INSERTs WITHOUT Indexes (10 batches)"
echo "==========================================================="
echo ""
info "This tests pure INSERT throughput without index maintenance"
info "Expected runtime: 2-5 minutes (10 batches × 100K rows)"
echo ""

run_phase "6a" "Streaming INSERTs - Phase 1 TEST (NO INDEXES)" \
    "sql/06c_streaming_inserts_noindex_procedure_TEST.sql" \
    "${RESULTS_DIR}/06_streaming_phase1.log" || exit 1

# =====================================================
# Phase 8: Optimize PAX (Z-order Clustering)
# =====================================================

info "Applying Z-order clustering to PAX tables..."
run_phase 8 "PAX Z-order Clustering" \
    "sql/08_optimize_pax.sql" \
    "${RESULTS_DIR}/08_optimize_pax.log" || exit 1

# Check clustering overhead
BLOAT_DETECTED=$(grep -c "❌ CRITICAL" "${RESULTS_DIR}/08_optimize_pax.log" || true)
if [ "$BLOAT_DETECTED" -gt 0 ]; then
    error "CRITICAL STORAGE BLOAT DETECTED after clustering!"
    error "Review: ${RESULTS_DIR}/08_optimize_pax.log"
    exit 1
else
    success "Clustering overhead is acceptable"
fi

echo ""

# =====================================================
# Phase 9: Query Performance Tests
# =====================================================

run_phase 9 "Query Performance Tests (after Phase 1)" \
    "sql/09_run_queries.sql" \
    "${RESULTS_DIR}/09_queries_phase1.log" || exit 1

# =====================================================
# Phase 10: Collect Metrics (Phase 1)
# =====================================================

run_phase "10a" "Collect Metrics - Phase 1" \
    "sql/10_collect_metrics.sql" \
    "${RESULTS_DIR}/10_metrics_phase1.txt" || exit 1

# =====================================================
# Phase 11: Validate Results (Phase 1)
# =====================================================

run_phase "11a" "Validate Results - Phase 1" \
    "sql/11_validate_results.sql" \
    "${RESULTS_DIR}/11_validation_phase1.txt" || exit 1

# Check for validation failures
VALIDATION_FAILED=$(grep -c "❌ FAILED" "${RESULTS_DIR}/11_validation_phase1.txt" || true)
if [ "$VALIDATION_FAILED" -gt 0 ]; then
    error "Validation failed! Review: ${RESULTS_DIR}/11_validation_phase1.txt"
    exit 1
else
    success "All validation gates passed for Phase 1"
fi

echo ""
echo "==========================================================="
echo "  PHASE 1 COMPLETE!"
echo "==========================================================="
echo ""
success "Phase 1 (10 batches, no indexes) completed successfully"
info "Proceeding with Phase 2 (10 batches, with indexes)..."
echo ""

# =====================================================
# PHASE 2: STREAMING INSERTS (WITH INDEXES) - 10 BATCHES
# =====================================================

echo ""
echo "==========================================================="
echo "  PHASE 2: Streaming INSERTs WITH Indexes (10 batches)"
echo "==========================================================="
echo ""
info "This tests INSERT throughput with index maintenance overhead"
info "Expected runtime: 2-5 minutes (10 batches × 100K rows)"
echo ""

# Drop existing tables and recreate with indexes
warn "Dropping existing tables to recreate with indexes..."
run_phase 4b "Recreate Tables for Phase 2" \
    "sql/04_create_variants.sql" \
    "${RESULTS_DIR}/04b_create_variants_phase2.log" || exit 1

# Create indexes
run_phase 5 "Create Indexes (5 per variant, 20 total)" \
    "sql/05_create_indexes.sql" \
    "${RESULTS_DIR}/05_create_indexes.log" || exit 1

# Run streaming INSERTs with indexes (10 batches)
run_phase "6b" "Streaming INSERTs - Phase 2 TEST (WITH INDEXES)" \
    "sql/07c_streaming_inserts_withindex_procedure_TEST.sql" \
    "${RESULTS_DIR}/07_streaming_phase2.log" || exit 1

# Re-cluster PAX after Phase 2
info "Re-applying Z-order clustering to PAX tables..."
run_phase "8b" "PAX Z-order Clustering (Phase 2)" \
    "sql/08_optimize_pax.sql" \
    "${RESULTS_DIR}/08b_optimize_pax_phase2.log" || exit 1

# Query performance (Phase 2)
run_phase "9b" "Query Performance Tests (after Phase 2)" \
    "sql/09_run_queries.sql" \
    "${RESULTS_DIR}/09b_queries_phase2.log" || exit 1

# Collect metrics (now includes Phase 1 vs Phase 2 comparison)
run_phase "10b" "Collect Metrics - Phase 2 (includes comparison)" \
    "sql/10_collect_metrics.sql" \
    "${RESULTS_DIR}/10_metrics_phase2.txt" || exit 1

# Validate Phase 2
run_phase "11b" "Validate Results - Phase 2" \
    "sql/11_validate_results.sql" \
    "${RESULTS_DIR}/11_validation_phase2.txt" || exit 1

# Check for validation failures
VALIDATION_FAILED=$(grep -c "❌ FAILED" "${RESULTS_DIR}/11_validation_phase2.txt" || true)
if [ "$VALIDATION_FAILED" -gt 0 ]; then
    error "Phase 2 validation failed! Review: ${RESULTS_DIR}/11_validation_phase2.txt"
    exit 1
else
    success "All validation gates passed for Phase 2"
fi

# =====================================================
# Final Summary
# =====================================================

BENCHMARK_END=$(date +%s)
TOTAL_DURATION=$((BENCHMARK_END - BENCHMARK_START))

echo ""
echo "==========================================================="
echo "  QUICK TEST COMPLETE (Both Phases)"
echo "==========================================================="
echo ""
echo "Total runtime: $((TOTAL_DURATION / 60))m $((TOTAL_DURATION % 60))s"
echo ""
echo "Phase breakdown:"
cat "${TIMING_FILE}"
echo ""
echo "Results saved to: ${RESULTS_DIR}"
echo ""
echo "Key files:"
echo "  • ${RESULTS_DIR}/10_metrics_phase1.txt - Phase 1 (no indexes)"
echo "  • ${RESULTS_DIR}/10_metrics_phase2.txt - Phase 2 (with indexes + comparison)"
echo "  • ${RESULTS_DIR}/11_validation_phase1.txt - Phase 1 validation"
echo "  • ${RESULTS_DIR}/11_validation_phase2.txt - Phase 2 validation"
echo "  • ${RESULTS_DIR}/02_cardinality_analysis.txt - Bloom filter analysis"
echo "  • ${RESULTS_DIR}/03_generated_config.sql - PAX configuration"
echo "  • ${TIMING_FILE} - Phase timings"
echo ""
echo "What was tested:"
echo "  ✅ Complete workflow (14 phases)"
echo "  ✅ Validation framework (cardinality analysis, config generation)"
echo "  ✅ Phase 1: 1M rows, no indexes"
echo "  ✅ Phase 2: 1M rows, 20 indexes"
echo "  ✅ PROCEDURE with per-batch commits (resumable)"
echo "  ✅ All reporting and validation scripts"
echo ""
echo "To run full 500-batch benchmark (~3.5-4.5 hours):"
echo "  ./scripts/run_streaming_benchmark.sh"
echo ""
echo "SUCCESS! Quick test completed without errors."
echo ""
