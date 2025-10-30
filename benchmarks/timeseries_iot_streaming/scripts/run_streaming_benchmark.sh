#!/bin/bash
#
# Streaming INSERT Benchmark - Master Script
# Tests INSERT throughput for continuous batch loading scenarios
# Simulates realistic telecom/IoT traffic patterns
#
# Phases:
#   Phase 1 (No indexes): Pure INSERT speed
#   Phase 2 (With indexes): Realistic production scenario
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
RESULTS_DIR="results/run_$(date +%Y%m%d_%H%M%S)"
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
echo "  Streaming INSERT Benchmark - PAX vs AO/AOCO"
echo "==========================================================="
echo ""
echo "Test Scenario:"
echo "  📊 Dataset: 50M rows (500 batches)"
echo "  🔄 Traffic: Realistic 24-hour telecom pattern"
echo "  📈 Batch sizes: 10K (small), 100K (medium), 500K (large bursts)"
echo "  ⏱️  Runtime: ~40-55 minutes (Phase 1 + Phase 2)"
echo ""
echo "Key Features:"
echo "  ✅ Two-phase testing (with/without indexes)"
echo "  ✅ Validation-first design (prevents misconfiguration)"
echo "  ✅ Per-batch metrics (500 measurements per variant)"
echo "  ✅ Storage growth tracking"
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
# PHASE 1: STREAMING INSERTS (NO INDEXES)
# =====================================================

echo ""
echo "==========================================================="
echo "  PHASE 1: Streaming INSERTs WITHOUT Indexes"
echo "==========================================================="
echo ""
info "This tests pure INSERT throughput without index maintenance"
info "Expected runtime: 15-20 minutes"
echo ""

run_phase "6a" "Streaming INSERTs - Phase 1 (NO INDEXES)" \
    "sql/06_streaming_inserts_noindex.sql" \
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

# =====================================================
# Ask user if they want to continue with Phase 2
# =====================================================

info "Phase 1 (no indexes) complete!"
info "Phase 2 will test INSERT performance WITH indexes (realistic production)"
info "Phase 2 runtime: ~25-35 minutes"
echo ""
read -p "Continue with Phase 2 (with indexes)? [Y/n] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
    warn "Skipping Phase 2"
    warn "To run Phase 2 later, use: ./scripts/run_phase2_withindex.sh"
    echo ""

    # Final summary (Phase 1 only)
    BENCHMARK_END=$(date +%s)
    TOTAL_DURATION=$((BENCHMARK_END - BENCHMARK_START))

    echo ""
    echo "==========================================================="
    echo "  BENCHMARK COMPLETE (Phase 1 only)"
    echo "==========================================================="
    echo ""
    echo "Total runtime: $((TOTAL_DURATION / 60))m $((TOTAL_DURATION % 60))s"
    echo ""
    echo "Results saved to: ${RESULTS_DIR}"
    echo ""
    echo "Key files:"
    echo "  • ${RESULTS_DIR}/10_metrics_phase1.txt - Performance metrics"
    echo "  • ${RESULTS_DIR}/11_validation_phase1.txt - Validation results"
    echo "  • ${TIMING_FILE} - Phase timings"
    echo ""
    exit 0
fi

# =====================================================
# PHASE 2: STREAMING INSERTS (WITH INDEXES)
# =====================================================

echo ""
echo "==========================================================="
echo "  PHASE 2: Streaming INSERTs WITH Indexes"
echo "==========================================================="
echo ""
info "This tests INSERT throughput with index maintenance overhead"
info "Expected runtime: 25-35 minutes (slower than Phase 1)"
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

# Run streaming INSERTs with indexes
run_phase "6b" "Streaming INSERTs - Phase 2 (WITH INDEXES)" \
    "sql/07_streaming_inserts_withindex.sql" \
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
echo "  BENCHMARK COMPLETE (Both Phases)"
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
echo "  • ${TIMING_FILE} - Phase timings"
echo ""
echo "SUCCESS! Benchmark completed without errors."
echo ""
