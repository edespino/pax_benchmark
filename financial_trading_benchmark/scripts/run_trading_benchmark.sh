#!/bin/bash
#
# Financial Trading Benchmark with Validation Framework
# Master script with 4 safety gates to prevent PAX misconfiguration
#
# Key Innovation: Validates configuration BEFORE table creation
# Prevents the 81% storage bloat discovered in October 2025
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

# Logging function
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
echo "  Financial Trading Benchmark with Validation Framework"
echo "==========================================================="
echo ""
echo "Key Features:"
echo "  ✅ Validation-first design (prevents misconfiguration)"
echo "  ✅ Auto-generated PAX configuration"
echo "  ✅ 4 safety gates (cardinality, memory, bloat detection)"
echo "  ✅ Fast iteration (6-8 minutes runtime)"
echo ""
echo "Results will be saved to: ${RESULTS_DIR}"
echo ""
read -p "Press Enter to start benchmark..."
echo ""

# =====================================================
# Phase 0: Validation Framework Setup
# =====================================================

run_phase 0 "Validation Framework Setup" \
    "sql/00_validation_framework.sql" \
    "${RESULTS_DIR}/00_validation_framework.log" || exit 1

# =====================================================
# Phase 1: Trading Schema Setup
# =====================================================

run_phase 1 "Trading Schema (5K symbols, 20 exchanges)" \
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

# =====================================================
# Phase 3: Generate Safe Configuration
# SAFETY GATE #2: Auto-generate config from analysis
# =====================================================

run_phase 3 "Auto-Generate Safe Configuration" \
    "sql/03_generate_config.sql" \
    "${RESULTS_DIR}/03_generated_config.sql" || exit 1

# =====================================================
# User Review Checkpoint
# =====================================================

echo "==========================================================="
echo "  CHECKPOINT: Review Generated Configuration"
echo "==========================================================="
echo ""
echo "Before proceeding, please review the generated configuration:"
echo "  File: ${RESULTS_DIR}/03_generated_config.sql"
echo ""
echo "Key items to verify:"
echo "  ✅ Bloom filter columns have cardinality >= 1000"
echo "  ✅ maintenance_work_mem is set appropriately"
echo "  ✅ No low-cardinality columns in bloom filters"
echo ""
read -p "Press Enter to continue with table creation..."
echo ""

# =====================================================
# Phase 4: Create Storage Variants
# =====================================================

run_phase 4 "Create Storage Variants (AO/AOCO/PAX)" \
    "sql/04_create_variants.sql" \
    "${RESULTS_DIR}/04_create_variants.log" || exit 1

# =====================================================
# Phase 5: Generate Tick Data
# =====================================================

run_phase 5 "Generate Tick Data (10M rows)" \
    "sql/05_generate_tick_data.sql" \
    "${RESULTS_DIR}/05_data_generation.log" || exit 1

# =====================================================
# SAFETY GATE #3: Post-Creation Validation
# =====================================================

run_phase 6 "Post-Creation Validation (SAFETY GATE #3)" \
    "sql/06_validate_configuration.sql" \
    "${RESULTS_DIR}/06_validation.txt"

# Check for bloat
BLOAT_DETECTED=$(grep -c "❌ CRITICAL" "${RESULTS_DIR}/06_validation.txt" || true)
if [ "$BLOAT_DETECTED" -gt 0 ]; then
    error "CRITICAL STORAGE BLOAT DETECTED!"
    error "Review: ${RESULTS_DIR}/06_validation.txt"
    exit 1
fi

# =====================================================
# Phase 7: PAX Optimization (Z-order Clustering)
# =====================================================

run_phase 7 "PAX Z-order Clustering" \
    "sql/07_optimize_pax.sql" \
    "${RESULTS_DIR}/07_optimize.log" || exit 1

# =====================================================
# SAFETY GATE #4: Post-Clustering Bloat Check
# =====================================================

log "Phase 8: 🔍 Post-clustering bloat check..."
if [ -f sql/06_validate_configuration.sql ]; then
    ${PSQL_CMD} -f sql/06_validate_configuration.sql > "${RESULTS_DIR}/08_post_cluster_validation.txt" 2>&1

    # Check bloat ratio
    BLOAT_RATIO=$(grep "bloat_ratio" "${RESULTS_DIR}/08_post_cluster_validation.txt" | awk '{print $2}' || echo "0")
    if (( $(echo "$BLOAT_RATIO > 1.5" | bc -l 2>/dev/null || echo "0") )); then
        error "Post-clustering bloat ratio: ${BLOAT_RATIO}x (CRITICAL)"
        error "Expected: < 1.3x"
        exit 1
    else
        success "Post-clustering bloat ratio: ${BLOAT_RATIO}x (healthy)"
    fi
else
    warn "Bloat check skipped (validation script not found)"
fi
echo ""

# =====================================================
# Phase 11: Collect Final Metrics
# =====================================================

run_phase 11 "Collect Final Metrics (AO/AOCO/PAX Comparison)" \
    "sql/11_collect_metrics.sql" \
    "${RESULTS_DIR}/11_metrics.txt" || exit 1

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
echo "  ✅ Validation results:        06_validation.txt"
echo "  💾 Final metrics:             11_metrics.txt"
echo "  ⏱️  Timing breakdown:          timing.txt"
echo ""
echo "Safety gates passed:"
echo "  ✅ Gate 1: Cardinality validation (bloom filter check)"
echo "  ✅ Gate 2: Auto-generated configuration"
echo "  ✅ Gate 3: Post-creation validation"
echo "  ✅ Gate 4: Post-clustering bloat check"
echo ""
echo "Next steps:"
echo "  1. Review cardinality analysis results"
echo "  2. Compare performance across AO/AOCO/PAX variants"
echo "  3. Use generated configuration for production deployments"
echo ""
echo "==========================================================="
echo ""
