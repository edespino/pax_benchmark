#!/bin/bash
#
# PAX Benchmark Automation Script
# Runs complete benchmark suite and generates comparison report
#

set -e  # Exit on error

# Configuration
BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_DIR="$BENCHMARK_DIR/sql"
RESULTS_DIR="$BENCHMARK_DIR/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="$RESULTS_DIR/run_$TIMESTAMP"

# Database connection (set these or use environment variables)
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-postgres}"
PGUSER="${PGUSER:-gpadmin}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check psql
    if ! command -v psql &> /dev/null; then
        log_error "psql not found. Please install PostgreSQL client."
        exit 1
    fi

    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_warning "python3 not found. Result parsing will be skipped."
    fi

    # Check PAX extension
    if ! psql -h "$PGHOST" -p "$PGPORT" -d "$PGDATABASE" -U "$PGUSER" -tAc \
        "SELECT 1 FROM pg_am WHERE amname = 'pax'" | grep -q 1; then
        log_error "PAX extension not found. Build Cloudberry with --enable-pax"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

run_sql_phase() {
    local phase_name=$1
    local sql_file=$2
    local log_file="$RUN_DIR/${phase_name}_$(date +%H%M%S).log"

    log_info "Running Phase: $phase_name"
    log_info "SQL file: $sql_file"
    log_info "Log file: $log_file"

    if psql -h "$PGHOST" -p "$PGPORT" -d "$PGDATABASE" -U "$PGUSER" \
        -f "$sql_file" > "$log_file" 2>&1; then
        log_success "Phase $phase_name completed"
        return 0
    else
        log_error "Phase $phase_name failed. Check log: $log_file"
        return 1
    fi
}

run_queries_on_variant() {
    local variant=$1
    local queries_file="$SQL_DIR/05_queries_ALL.sql"
    local output_dir="$RUN_DIR/queries"
    mkdir -p "$output_dir"

    log_info "Running queries on variant: $variant"

    # Create temporary SQL file with TABLE_VARIANT substituted
    local temp_sql="$output_dir/queries_${variant}_temp.sql"
    sed "s/TABLE_VARIANT/${variant}/g" "$queries_file" > "$temp_sql"

    # Run queries 3 times for each variant
    for run in 1 2 3; do
        local log_file="$output_dir/${variant}_run${run}.log"
        log_info "  Run $run/3..."

        # Clear caches between runs
        psql -h "$PGHOST" -p "$PGPORT" -d "$PGDATABASE" -U "$PGUSER" \
            -c "CHECKPOINT;" > /dev/null 2>&1
        sleep 2

        # Run queries
        psql -h "$PGHOST" -p "$PGPORT" -d "$PGDATABASE" -U "$PGUSER" \
            -f "$temp_sql" > "$log_file" 2>&1

        log_success "    Run $run completed: $log_file"
    done

    rm -f "$temp_sql"
    log_success "Queries completed for $variant"
}

# Main execution
main() {
    echo "================================================"
    echo "  PAX Storage Performance Benchmark"
    echo "  Run ID: $TIMESTAMP"
    echo "================================================"
    echo ""

    # Create results directory
    mkdir -p "$RUN_DIR"
    log_info "Results directory: $RUN_DIR"
    echo ""

    # Check prerequisites
    check_prerequisites
    echo ""

    # Ask for confirmation
    echo "This benchmark will:"
    echo "  1. Create benchmark schema and dimension tables (~5GB)"
    echo "  2. Create three table variants (AO, AOCO, PAX)"
    echo "  3. Generate 200M rows of data (~70GB per variant, ~210GB total)"
    echo "  4. Run Z-order clustering on PAX table"
    echo "  5. Execute 20 queries on each variant (3 runs each)"
    echo ""
    echo "Estimated time: 2-4 hours"
    echo "Estimated disk space: ~300GB"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Benchmark cancelled by user"
        exit 0
    fi
    echo ""

    # Phase 1: Schema setup
    if ! run_sql_phase "Phase1_Schema" "$SQL_DIR/01_setup_schema.sql"; then
        log_error "Schema setup failed. Exiting."
        exit 1
    fi
    echo ""

    # Phase 2: Create variants
    if ! run_sql_phase "Phase2_Variants" "$SQL_DIR/02_create_variants.sql"; then
        log_error "Variant creation failed. Exiting."
        exit 1
    fi
    echo ""

    # Phase 3: Data generation (longest phase)
    log_warning "Phase 3 will take 30-60 minutes. Please be patient..."
    if ! run_sql_phase "Phase3_Data" "$SQL_DIR/03_generate_data.sql"; then
        log_error "Data generation failed. Exiting."
        exit 1
    fi
    echo ""

    # Phase 4: Optimization & clustering
    log_warning "Phase 4 clustering will take 10-20 minutes..."
    if ! run_sql_phase "Phase4_Optimize" "$SQL_DIR/04_optimize_pax.sql"; then
        log_error "Optimization failed. Exiting."
        exit 1
    fi
    echo ""

    # Phase 5: Run queries on all variants
    log_info "Phase 5: Running benchmark queries (this will take 1-2 hours)..."
    run_queries_on_variant "sales_fact_ao"
    run_queries_on_variant "sales_fact_aoco"
    run_queries_on_variant "sales_fact_pax"
    echo ""

    # Phase 6: Collect metrics
    if ! run_sql_phase "Phase6_Metrics" "$SQL_DIR/06_collect_metrics.sql"; then
        log_warning "Metrics collection failed (non-fatal)"
    fi
    echo ""

    # Generate report
    log_info "Generating summary report..."
    if command -v python3 &> /dev/null; then
        if [ -f "$BENCHMARK_DIR/scripts/generate_report.py" ]; then
            python3 "$BENCHMARK_DIR/scripts/generate_report.py" "$RUN_DIR" \
                > "$RUN_DIR/BENCHMARK_REPORT.md"
            log_success "Report generated: $RUN_DIR/BENCHMARK_REPORT.md"
        else
            log_warning "generate_report.py not found. Skipping report generation."
        fi
    fi
    echo ""

    # Summary
    echo "================================================"
    echo "  BENCHMARK COMPLETE!"
    echo "================================================"
    echo ""
    echo "Results location: $RUN_DIR"
    echo ""
    echo "Next steps:"
    echo "  1. Review: $RUN_DIR/BENCHMARK_REPORT.md"
    echo "  2. Analyze query logs in: $RUN_DIR/queries/"
    echo "  3. Compare execution times across variants"
    echo ""
    log_success "All phases completed successfully"
}

# Run main
main "$@"
