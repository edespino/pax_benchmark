#!/bin/bash
#
# Quick Test Script - Phase 2 Only (With Indexes)
# Tests INSERT throughput with index maintenance overhead
# NOTE: This is standalone - doesn't require Phase 1 to be run first
#
# Runtime: ~30-35 minutes
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PSQL_CMD="psql postgres"
RESULTS_DIR="results/phase2_$(date +%Y%m%d_%H%M%S)"
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
    ${PSQL_CMD} -f "${sql_file}" > "${log_file}" 2>&1
    local exit_code=$?
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
echo "  Streaming INSERT Benchmark - PHASE 2 ONLY (With Indexes)"
echo "==========================================================="
echo ""
echo "Test Scenario:"
echo "  📊 Dataset: 50M rows (500 batches)"
echo "  🔄 Traffic: Realistic 24-hour telecom pattern"
echo "  📈 Batch sizes: 10K (small), 100K (medium), 500K (large bursts)"
echo "  📇 Indexes: 5 per variant (20 total)"
echo "  ⏱️  Runtime: ~30-35 minutes"
echo ""
echo "What this tests:"
echo "  ✅ INSERT throughput WITH index maintenance overhead"
echo "  ✅ Production-realistic scenario"
echo "  ✅ Index impact on INSERT performance"
echo ""
echo "Results will be saved to: ${RESULTS_DIR}"
echo ""

# =====================================================
# Phases 0-4: Setup
# =====================================================

run_phase 0 "Validation Framework Setup" \
    "sql/00_validation_framework.sql" \
    "${RESULTS_DIR}/00_validation_framework.log" || exit 1

run_phase 1 "CDR Schema Setup" \
    "sql/01_setup_schema.sql" \
    "${RESULTS_DIR}/01_setup_schema.log" || exit 1

run_phase 2 "Cardinality Analysis" \
    "sql/02_analyze_cardinality.sql" \
    "${RESULTS_DIR}/02_cardinality_analysis.txt" || exit 1

UNSAFE_COUNT=$(grep -c "❌ UNSAFE" "${RESULTS_DIR}/02_cardinality_analysis.txt" || true)
if [ "$UNSAFE_COUNT" -gt 0 ]; then
    warn "Found ${UNSAFE_COUNT} columns marked UNSAFE for bloom filters"
else
    success "All proposed bloom filter columns passed validation"
fi

run_phase 3 "Auto-Generate Safe Configuration" \
    "sql/03_generate_config.sql" \
    "${RESULTS_DIR}/03_generated_config.sql" || exit 1

run_phase 4 "Create Storage Variants" \
    "sql/04_create_variants.sql" \
    "${RESULTS_DIR}/04_create_variants.log" || exit 1

# =====================================================
# Phase 5: Create Indexes
# =====================================================

info "Creating indexes on all 4 variants (5 indexes each)..."
run_phase 5 "Create Indexes (20 total)" \
    "sql/05_create_indexes.sql" \
    "${RESULTS_DIR}/05_create_indexes.log" || exit 1

echo ""

# =====================================================
# Phase 7: STREAMING INSERTS (WITH INDEXES) - MAIN TEST
# =====================================================

echo "==========================================================="
echo "  MAIN TEST: Streaming INSERTs WITH Indexes"
echo "==========================================================="
echo ""
info "This will INSERT 50M rows in 500 batches (per variant)"
info "WITH index maintenance on every INSERT"
info "Expected runtime: 20-30 minutes (slower than Phase 1)"
info "Progress will be shown every 10 batches"
echo ""

run_phase 7 "Streaming INSERTs - Phase 2 (WITH INDEXES)" \
    "sql/07_streaming_inserts_withindex.sql" \
    "${RESULTS_DIR}/07_streaming_phase2.log" || exit 1

# =====================================================
# Phase 8: Optimize PAX
# =====================================================

run_phase 8 "PAX Z-order Clustering" \
    "sql/08_optimize_pax.sql" \
    "${RESULTS_DIR}/08_optimize_pax.log" || exit 1

BLOAT_DETECTED=$(grep -c "❌ CRITICAL" "${RESULTS_DIR}/08_optimize_pax.log" || true)
if [ "$BLOAT_DETECTED" -gt 0 ]; then
    error "CRITICAL STORAGE BLOAT DETECTED after clustering!"
    error "Review: ${RESULTS_DIR}/08_optimize_pax.log"
    exit 1
fi

# =====================================================
# Phase 9: Query Performance Tests
# =====================================================

run_phase 9 "Query Performance Tests" \
    "sql/09_run_queries.sql" \
    "${RESULTS_DIR}/09_queries.log" || exit 1

# =====================================================
# Phase 10: Collect Metrics
# =====================================================

run_phase 10 "Collect Metrics (Phase 2)" \
    "sql/10_collect_metrics.sql" \
    "${RESULTS_DIR}/10_metrics.txt" || exit 1

# =====================================================
# Phase 11: Validate Results
# =====================================================

run_phase 11 "Validate Results" \
    "sql/11_validate_results.sql" \
    "${RESULTS_DIR}/11_validation.txt" || exit 1

VALIDATION_FAILED=$(grep -c "❌ FAILED" "${RESULTS_DIR}/11_validation.txt" || true)
if [ "$VALIDATION_FAILED" -gt 0 ]; then
    error "Validation failed! Review: ${RESULTS_DIR}/11_validation.txt"
    exit 1
else
    success "All validation gates passed"
fi

# =====================================================
# Final Summary
# =====================================================

BENCHMARK_END=$(date +%s)
TOTAL_DURATION=$((BENCHMARK_END - BENCHMARK_START))

echo ""
echo "==========================================================="
echo "  PHASE 2 COMPLETE!"
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
echo "  • ${RESULTS_DIR}/10_metrics.txt - INSERT throughput with index overhead"
echo "  • ${RESULTS_DIR}/11_validation.txt - Validation results"
echo "  • ${RESULTS_DIR}/07_streaming_phase2.log - Full INSERT log"
echo ""
echo "Next steps:"
echo "  1. Review metrics: cat ${RESULTS_DIR}/10_metrics.txt"
echo "  2. Compare with Phase 1 (if available)"
echo "  3. Run full benchmark: ./scripts/run_streaming_benchmark.sh"
echo ""
echo "SUCCESS! Phase 2 completed without errors."
echo ""
