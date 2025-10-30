#!/bin/bash
#
# Log Analytics Benchmark with Validation Framework
# Master script with validation gates to prevent PAX misconfiguration
#
# Key Innovation: Validates configuration BEFORE table creation
# Tests PAX sparse filtering advantage on log data (95% NULL columns)
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Timing helper
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
echo "  Log Analytics Benchmark with Validation Framework"
echo "==========================================================="
echo ""
echo "Key Features:"
echo "  ✅ Validation-first design (prevents misconfiguration)"
echo "  ✅ Auto-generated PAX configuration"
echo "  ✅ Sparse column testing (95% NULL - PAX advantage)"
echo "  ✅ High-cardinality bloom filters (trace_id, request_id)"
echo "  ✅ Fast iteration (3-6 minutes runtime)"
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

run_phase 1 "Log Schema Setup (200 microservices)" \
    "sql/01_setup_schema.sql" \
    "${RESULTS_DIR}/01_setup_schema.log" || exit 1

# =====================================================
# Phase 2: CRITICAL - Cardinality Analysis
# VALIDATION GATE: Validate bloom filter candidates
# =====================================================

log "Phase 2: 🔍 CRITICAL - Cardinality Analysis (1M sample)..."
run_phase 2 "Cardinality Analysis" \
    "sql/02_analyze_cardinality.sql" \
    "${RESULTS_DIR}/02_cardinality_analysis.txt" || exit 1

# Check for DANGEROUS bloom filter candidates
DANGEROUS_COUNT=$(grep -c "❌ DANGEROUS" "${RESULTS_DIR}/02_cardinality_analysis.txt" || true)
if [ "$DANGEROUS_COUNT" -gt 0 ]; then
    warn "Found ${DANGEROUS_COUNT} columns marked DANGEROUS for bloom filters"
    warn "These columns will be EXCLUDED from bloom filter configuration"
else
    success "All proposed bloom filter columns passed validation"
fi

# Check sparse columns
SPARSE_COUNT=$(grep -c "✨" "${RESULTS_DIR}/02_cardinality_analysis.txt" || true)
log "Detected ${SPARSE_COUNT} highly sparse columns (PAX advantage)"

# =====================================================
# Phase 3: Generate Safe Configuration
# VALIDATION GATE: Auto-generate config from analysis
# =====================================================

run_phase 3 "Auto-Generate Safe Configuration" \
    "sql/03_generate_config.sql" \
    "${RESULTS_DIR}/03_generated_config.sql" || exit 1

# =====================================================
# Phases 4-9: Remaining benchmark phases
# =====================================================

run_phase 4 "Create Storage Variants (AO/AOCO/PAX)" \
    "sql/04_create_variants.sql" \
    "${RESULTS_DIR}/04_create_variants.log" || exit 1

run_phase 5 "Generate Log Data (10M entries)" \
    "sql/05_generate_data.sql" \
    "${RESULTS_DIR}/05_data_generation.log" || exit 1

run_phase 6 "PAX Z-order Clustering" \
    "sql/06_optimize_pax.sql" \
    "${RESULTS_DIR}/06_optimize.log"

# Check clustering status
CLUSTERING_STATUS=$?
if [ $CLUSTERING_STATUS -ne 0 ]; then
    error "Clustering failed or exceeded bloat threshold"
    exit 1
fi

# Check for clustering bloat
BLOAT_COUNT=$(grep -c "❌ CRITICAL" "${RESULTS_DIR}/06_optimize.log" || true)
if [ "$BLOAT_COUNT" -gt 0 ]; then
    error "CRITICAL CLUSTERING BLOAT DETECTED!"
    error "Review: ${RESULTS_DIR}/06_optimize.log"
    exit 1
fi

run_phase 7 "Run Query Suite (12 queries × 4 variants)" \
    "sql/07_run_queries.sql" \
    "${RESULTS_DIR}/07_query_results.txt" || exit 1

run_phase 8 "Collect Final Metrics" \
    "sql/08_collect_metrics.sql" \
    "${RESULTS_DIR}/08_metrics.txt" || exit 1

run_phase 9 "Validate Results" \
    "sql/09_validate_results.sql" \
    "${RESULTS_DIR}/09_validation.txt"

# Check validation status
VALIDATION_STATUS=$?
if [ $VALIDATION_STATUS -ne 0 ]; then
    error "Results validation failed"
    exit 1
fi

# Check for validation failures
VALIDATION_FAILURES=$(grep -c "❌ FAILED" "${RESULTS_DIR}/09_validation.txt" || true)
if [ "$VALIDATION_FAILURES" -gt 0 ]; then
    error "Found ${VALIDATION_FAILURES} validation failures"
    error "Review: ${RESULTS_DIR}/09_validation.txt"
    exit 1
fi

# =====================================================
# Summary
# =====================================================

BENCHMARK_END=$(date +%s)
TOTAL_TIME=$((BENCHMARK_END - BENCHMARK_START))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

echo ""
echo "==========================================================="
echo "  ✅ Benchmark Complete!"
echo "==========================================================="
echo ""
echo "Total runtime: ${MINUTES}m ${SECONDS}s"
echo "Results saved to: ${RESULTS_DIR}/"
echo ""
echo "Timing breakdown:"
cat "${TIMING_FILE}" 2>/dev/null || echo "  (Timing file not found)"
echo ""
echo "Key files to review:"
echo "  📊 Cardinality analysis:      02_cardinality_analysis.txt"
echo "  ⚙️  Generated configuration:   03_generated_config.sql"
echo "  🔧 PAX optimization:          06_optimize.log"
echo "  📈 Query performance:         07_query_results.txt"
echo "  💾 Final metrics:             08_metrics.txt"
echo "  ✅ Validation results:        09_validation.txt"
echo "  ⏱️  Timing breakdown:          timing.txt"
echo ""
echo "Validation gates passed:"
echo "  ✅ Cardinality validation (bloom filter check)"
echo "  ✅ Auto-generated configuration"
echo "  ✅ Clustering bloat check"
echo "  ✅ Post-benchmark validation"
echo ""
echo "Key findings to review:"
echo "  1. Sparse column efficiency (stack_trace, error_code ~95% NULL)"
echo "  2. Bloom filter effectiveness (trace_id, request_id)"
echo "  3. Z-order clustering benefit (log_date + application_id)"
echo "  4. Storage comparison (AO vs AOCO vs PAX)"
echo ""
echo "Next steps:"
echo "  1. Review cardinality analysis results"
echo "  2. Compare query performance across variants"
echo "  3. Analyze sparse column storage savings"
echo "  4. Use validated configuration for production log storage"
echo ""
echo "==========================================================="
echo ""
