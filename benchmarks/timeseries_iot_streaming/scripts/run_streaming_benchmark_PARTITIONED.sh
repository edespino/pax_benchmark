#!/bin/bash
#
# Streaming INSERT Benchmark - PARTITIONED VARIANTS
# Tests INSERT throughput with table partitioning (24 partitions per variant)
#
# Track B Optimization: Table partitioning for smaller index maintenance
# Expected benefit: 18-35% Phase 2 speedup vs monolithic tables
#
# Phases:
#   Phase 1 (No indexes): Pure INSERT speed with partition routing
#   Phase 2 (With indexes): Realistic production scenario (expected 18-35% faster)
#

set -e  # Exit on error

# Detect and change to correct directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BENCHMARK_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PSQL_CMD="psql postgres"
RESULTS_DIR="results/run_partitioned_$(date +%Y%m%d_%H%M%S)"
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
echo "  Streaming INSERT Benchmark - PARTITIONED VARIANTS"
echo "==========================================================="
echo ""
echo "Test Scenario:"
echo "  📊 Dataset: ~42M rows (500 batches)"
echo "  🔄 Traffic: Realistic 24-hour telecom pattern"
echo "  📈 Batch sizes: 10K (small), 100K (medium)"
echo "  🗂️  Partitioning: 24 daily partitions per variant (96 total)"
echo "  ⏱️  Runtime: ~35-50 min (Phase 1: 15-20 min, Phase 2: 20-30 min)"
echo ""
echo "Key Features:"
echo "  ✅ Two-phase testing (with/without indexes)"
echo "  ✅ Partition routing (Hour 0→day00, Hour 23→day23)"
echo "  ✅ Per-batch metrics (500 measurements per variant)"
echo "  ✅ 18-35% Phase 2 speedup expected vs monolithic"
echo ""
echo "Partitioning Benefits:"
echo "  • Each partition: ~1.74M rows (vs 42M monolithic)"
echo "  • Indexes 24x smaller per partition"
echo "  • O(n log n) reduction per partition"
echo "  • Partition pruning for date-range queries"
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
# Phase 4c: Create PARTITIONED Table Variants
# =====================================================

info "Creating partitioned tables (24 partitions per variant, 96 total)..."
run_phase "4c" "Create Partitioned Variants (AO/AOCO/PAX/PAX-no-cluster)" \
    "sql/04c_create_variants_PARTITIONED.sql" \
    "${RESULTS_DIR}/04c_create_variants_partitioned.log" || exit 1

# Verify partition creation
PARTITION_COUNT=$(${PSQL_CMD} -t -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname='cdr' AND tablename LIKE '%_part_day%';" | xargs)
if [ "$PARTITION_COUNT" -eq 96 ]; then
    success "All 96 partitions created successfully"
else
    error "Expected 96 partitions, found ${PARTITION_COUNT}"
    exit 1
fi

echo ""

# =====================================================
# PHASE 1: STREAMING INSERTS (NO INDEXES) - PARTITIONED
# =====================================================

echo ""
echo "==========================================================="
echo "  PHASE 1: Streaming INSERTs WITHOUT Indexes (PARTITIONED)"
echo "==========================================================="
echo ""
info "This tests pure INSERT throughput with partition routing"
info "Expected runtime: 15-20 minutes (similar to monolithic)"
info "Each hour maps to a partition: Hour 0→2024-01-01 (day00), etc."
echo ""

run_phase "6b" "Streaming INSERTs - Phase 1 (NO INDEXES) - PARTITIONED" \
    "sql/06b_streaming_inserts_noindex_PARTITIONED.sql" \
    "${RESULTS_DIR}/06b_streaming_phase1_partitioned.log" || exit 1

# =====================================================
# Phase 10b: Collect Metrics (Phase 1 - PARTITIONED)
# =====================================================

run_phase "10b-1" "Collect Metrics - Phase 1 (PARTITIONED)" \
    "sql/10b_collect_metrics_PARTITIONED.sql" \
    "${RESULTS_DIR}/10b_metrics_phase1_partitioned.txt" || exit 1

# =====================================================
# Phase 11b: Validate Results (Phase 1 - PARTITIONED)
# =====================================================

run_phase "11b-1" "Validate Results - Phase 1 (PARTITIONED)" \
    "sql/11b_validate_results_PARTITIONED.sql" \
    "${RESULTS_DIR}/11b_validation_phase1_partitioned.txt" || exit 1

# Check for validation failures
VALIDATION_FAILED=$(grep -c "❌ FAILED" "${RESULTS_DIR}/11b_validation_phase1_partitioned.txt" || true)
if [ "$VALIDATION_FAILED" -gt 0 ]; then
    error "Validation failed! Review: ${RESULTS_DIR}/11b_validation_phase1_partitioned.txt"
    exit 1
else
    success "All validation gates passed for Phase 1 (PARTITIONED)"
fi

echo ""
echo "==========================================================="
echo "  PHASE 1 COMPLETE! (PARTITIONED)"
echo "==========================================================="
echo ""

# =====================================================
# Ask user if they want to continue with Phase 2
# =====================================================

info "Phase 1 (no indexes) complete!"
info "Phase 2 will test INSERT performance WITH indexes"
info "Expected speedup: 18-35% vs monolithic (due to smaller partition indexes)"
info "Phase 2 runtime: ~20-30 minutes"
echo ""
read -p "Continue with Phase 2 (with indexes)? [Y/n] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
    warn "Skipping Phase 2"
    warn "To run Phase 2 later, use: psql -f sql/05b_create_indexes_PARTITIONED.sql && psql -f sql/07b_streaming_inserts_withindex_PARTITIONED.sql"
    echo ""

    # Final summary (Phase 1 only)
    BENCHMARK_END=$(date +%s)
    TOTAL_DURATION=$((BENCHMARK_END - BENCHMARK_START))

    echo ""
    echo "==========================================================="
    echo "  BENCHMARK COMPLETE (Phase 1 only - PARTITIONED)"
    echo "==========================================================="
    echo ""
    echo "Total runtime: $((TOTAL_DURATION / 60))m $((TOTAL_DURATION % 60))s"
    echo ""
    echo "Results saved to: ${RESULTS_DIR}"
    echo ""
    echo "Key files:"
    echo "  • ${RESULTS_DIR}/10b_metrics_phase1_partitioned.txt - Performance metrics"
    echo "  • ${RESULTS_DIR}/11b_validation_phase1_partitioned.txt - Validation results"
    echo "  • ${TIMING_FILE} - Phase timings"
    echo ""
    echo "Partition distribution:"
    echo "  • 96 partitions total (4 variants × 24 partitions)"
    echo "  • ~1.74M rows per partition"
    echo ""
    exit 0
fi

# =====================================================
# PHASE 2: STREAMING INSERTS (WITH INDEXES) - PARTITIONED
# =====================================================

echo ""
echo "==========================================================="
echo "  PHASE 2: Streaming INSERTs WITH Indexes (PARTITIONED)"
echo "==========================================================="
echo ""
info "This tests INSERT throughput with smaller partition indexes"
info "Expected runtime: 20-30 minutes (18-35% faster than monolithic)"
echo ""

# Create indexes on partitioned tables
run_phase "5b" "Create Indexes on Partitions (cascades to 480 partition indexes)" \
    "sql/05b_create_indexes_PARTITIONED.sql" \
    "${RESULTS_DIR}/05b_create_indexes_partitioned.log" || exit 1

# Run streaming INSERTs with indexes (partitioned)
run_phase "7b" "Streaming INSERTs - Phase 2 (WITH INDEXES) - PARTITIONED" \
    "sql/07b_streaming_inserts_withindex_PARTITIONED.sql" \
    "${RESULTS_DIR}/07b_streaming_phase2_partitioned.log" || exit 1

# Collect metrics (now includes Phase 1 vs Phase 2 comparison)
run_phase "10b-2" "Collect Metrics - Phase 2 (includes comparison, PARTITIONED)" \
    "sql/10b_collect_metrics_PARTITIONED.sql" \
    "${RESULTS_DIR}/10b_metrics_phase2_partitioned.txt" || exit 1

# Validate Phase 2
run_phase "11b-2" "Validate Results - Phase 2 (PARTITIONED)" \
    "sql/11b_validate_results_PARTITIONED.sql" \
    "${RESULTS_DIR}/11b_validation_phase2_partitioned.txt" || exit 1

# Check for validation failures
VALIDATION_FAILED=$(grep -c "❌ FAILED" "${RESULTS_DIR}/11b_validation_phase2_partitioned.txt" || true)
if [ "$VALIDATION_FAILED" -gt 0 ]; then
    error "Phase 2 validation failed! Review: ${RESULTS_DIR}/11b_validation_phase2_partitioned.txt"
    exit 1
else
    success "All validation gates passed for Phase 2 (PARTITIONED)"
fi

# =====================================================
# Final Summary
# =====================================================

BENCHMARK_END=$(date +%s)
TOTAL_DURATION=$((BENCHMARK_END - BENCHMARK_START))

echo ""
echo "==========================================================="
echo "  BENCHMARK COMPLETE (Both Phases - PARTITIONED)"
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
echo "  • ${RESULTS_DIR}/10b_metrics_phase1_partitioned.txt - Phase 1 (no indexes)"
echo "  • ${RESULTS_DIR}/10b_metrics_phase2_partitioned.txt - Phase 2 (with indexes + comparison)"
echo "  • ${RESULTS_DIR}/11b_validation_phase1_partitioned.txt - Phase 1 validation"
echo "  • ${RESULTS_DIR}/11b_validation_phase2_partitioned.txt - Phase 2 validation"
echo "  • ${TIMING_FILE} - Phase timings"
echo ""
echo "Partitioning Summary:"
echo "  • 96 partitions total (4 variants × 24 partitions)"
echo "  • ~1.74M rows per partition (vs 42M monolithic)"
echo "  • 480 partition indexes (20 parent × 24 partitions)"
echo ""
echo "Compare Phase 2 metrics vs monolithic to validate 18-35% speedup!"
echo ""
echo "SUCCESS! Benchmark completed without errors."
echo ""
