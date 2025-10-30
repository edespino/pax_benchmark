--
-- Phase 0: Validation Framework (Core Innovation)
-- Prevents PAX misconfiguration through automated validation
-- Based on lessons learned from October 2025 bloom filter disaster
--

\timing on

\echo '===================================================='
\echo 'Log Analytics - Phase 0: Validation Framework Setup'
\echo '===================================================='
\echo ''

-- =====================================================
-- Create Validation Schema
-- =====================================================

\echo 'Creating validation schema...'

DROP SCHEMA IF EXISTS logs_validation CASCADE;
CREATE SCHEMA logs_validation;

\echo '  ✓ Validation schema created'
\echo ''

-- =====================================================
-- Validation Rules Table
-- Based on October 2025 testing results
-- =====================================================

\echo 'Creating validation rules table...'

CREATE TABLE logs_validation.cardinality_rules (
    rule_id SERIAL PRIMARY KEY,

    -- Bloom filter thresholds (from Oct 2025 lessons)
    min_distinct_bloom INTEGER DEFAULT 1000,        -- Below this: NO bloom filter (causes bloat)
    warn_distinct_bloom INTEGER DEFAULT 100,        -- Warning zone: borderline
    max_bloom_columns INTEGER DEFAULT 3,            -- Safety: never exceed 3 columns

    -- MinMax thresholds
    min_distinct_minmax INTEGER DEFAULT 10,         -- Below this: NO minmax (useless)

    -- Memory calculation (MB per 1M rows, from testing)
    memory_per_million_rows INTEGER DEFAULT 200,    -- 200MB per 1M rows
    memory_safety_margin NUMERIC(3,2) DEFAULT 1.2,  -- 20% safety margin

    -- Storage bloat thresholds
    max_acceptable_bloat_ratio NUMERIC(3,2) DEFAULT 1.3,  -- 30% bloat is max acceptable
    critical_bloat_ratio NUMERIC(3,2) DEFAULT 1.5,        -- 50% bloat is critical failure

    -- Metadata
    created_at TIMESTAMP DEFAULT NOW(),
    notes TEXT
);

-- Insert default rules (validated through Oct 2025 testing)
INSERT INTO logs_validation.cardinality_rules (notes) VALUES (
    'Default rules based on October 2025 PAX benchmark testing. ' ||
    'Bloom filter misconfiguration caused 81% storage bloat and 54x memory overhead. ' ||
    'These thresholds prevent such disasters.'
);

\echo '  ✓ Validation rules configured'
\echo ''

-- =====================================================
-- Function: Validate Bloom Filter Candidates
-- CRITICAL: Run BEFORE creating PAX tables
-- =====================================================

\echo 'Creating bloom filter validation function...'

CREATE OR REPLACE FUNCTION logs_validation.validate_bloom_candidates(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_proposed_bloom_columns TEXT[]
) RETURNS TABLE(
    column_name TEXT,
    n_distinct NUMERIC,
    cardinality_estimate BIGINT,
    verdict TEXT,
    reason TEXT,
    recommendation TEXT
) AS $$
DECLARE
    v_min_bloom INTEGER;
    v_warn_bloom INTEGER;
BEGIN
    -- Get current rules
    SELECT min_distinct_bloom, warn_distinct_bloom
    INTO v_min_bloom, v_warn_bloom
    FROM logs_validation.cardinality_rules
    ORDER BY rule_id DESC
    LIMIT 1;

    RETURN QUERY
    SELECT
        s.attname::TEXT,
        s.n_distinct,
        CASE
            WHEN s.n_distinct >= 0 THEN s.n_distinct::BIGINT
            ELSE (10000000 * ABS(s.n_distinct))::BIGINT  -- Estimate for 10M rows
        END AS cardinality_estimate,
        CASE
            WHEN s.attname = ANY(p_proposed_bloom_columns) THEN
                CASE
                    WHEN ABS(s.n_distinct) >= v_min_bloom THEN '✅ SAFE'
                    WHEN ABS(s.n_distinct) >= v_warn_bloom THEN '🟠 WARNING'
                    ELSE '❌ DANGEROUS'
                END
            ELSE '⚪ Not proposed'
        END AS verdict,
        CASE
            WHEN s.attname = ANY(p_proposed_bloom_columns) THEN
                CASE
                    WHEN ABS(s.n_distinct) >= v_min_bloom THEN
                        'Cardinality sufficient for bloom filter'
                    WHEN ABS(s.n_distinct) >= v_warn_bloom THEN
                        'Cardinality borderline - may cause moderate bloat'
                    ELSE
                        'Cardinality too low - WILL cause 80%+ storage bloat and 50x+ memory overhead'
                END
            ELSE
                'Column not in proposed bloom filter list'
        END AS reason,
        CASE
            WHEN s.attname = ANY(p_proposed_bloom_columns) THEN
                CASE
                    WHEN ABS(s.n_distinct) >= v_min_bloom THEN
                        'Add to bloomfilter_columns'
                    WHEN ABS(s.n_distinct) >= v_warn_bloom THEN
                        'Test with and without bloom filter'
                    ELSE
                        'REMOVE from bloomfilter_columns - use minmax_columns only'
                END
            ELSE
                CASE
                    WHEN ABS(s.n_distinct) >= v_min_bloom THEN
                        'Consider adding to bloomfilter_columns'
                    WHEN ABS(s.n_distinct) >= 10 THEN
                        'Add to minmax_columns only'
                    ELSE
                        'Skip - too low cardinality'
                END
        END AS recommendation
    FROM pg_stats s
    WHERE s.schemaname = p_schema_name
      AND s.tablename = p_table_name
      AND s.attname = ANY(p_proposed_bloom_columns)
    ORDER BY ABS(s.n_distinct) DESC;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ Bloom filter validation function created'
\echo ''

-- =====================================================
-- Function: Calculate Clustering Memory Requirements
-- =====================================================

\echo 'Creating memory calculation function...'

CREATE OR REPLACE FUNCTION logs_validation.calculate_cluster_memory(
    p_target_rows BIGINT
) RETURNS TABLE(
    target_rows BIGINT,
    estimated_memory_mb INTEGER,
    recommended_maintenance_work_mem TEXT,
    safety_margin_included BOOLEAN,
    notes TEXT
) AS $$
DECLARE
    v_memory_per_million INTEGER;
    v_safety_margin NUMERIC;
    v_base_memory INTEGER;
    v_safe_memory INTEGER;
BEGIN
    -- Get rules
    SELECT memory_per_million_rows, memory_safety_margin
    INTO v_memory_per_million, v_safety_margin
    FROM logs_validation.cardinality_rules
    ORDER BY rule_id DESC
    LIMIT 1;

    -- Calculate memory (MB per 1M rows * number of millions)
    v_base_memory := (p_target_rows / 1000000.0 * v_memory_per_million)::INTEGER;
    v_safe_memory := (v_base_memory * v_safety_margin)::INTEGER;

    RETURN QUERY
    SELECT
        p_target_rows,
        v_safe_memory,
        CASE
            WHEN v_safe_memory < 1024 THEN v_safe_memory || 'MB'
            ELSE (v_safe_memory / 1024.0)::NUMERIC(10,1) || 'GB'
        END::TEXT,
        TRUE,
        'Set maintenance_work_mem BEFORE running CLUSTER to prevent 2-3x storage bloat'::TEXT;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ Memory calculation function created'
\echo ''

-- =====================================================
-- Function: Detect Storage Bloat
-- Runs AFTER table creation to validate configuration
-- =====================================================

\echo 'Creating bloat detection function...'

CREATE OR REPLACE FUNCTION logs_validation.detect_storage_bloat(
    p_baseline_table TEXT,
    p_pax_table TEXT,
    p_schema_name TEXT DEFAULT 'logs'
) RETURNS TABLE(
    baseline_table TEXT,
    baseline_size_mb NUMERIC,
    pax_table TEXT,
    pax_size_mb NUMERIC,
    bloat_ratio NUMERIC,
    verdict TEXT,
    recommendation TEXT
) AS $$
DECLARE
    v_baseline_size BIGINT;
    v_pax_size BIGINT;
    v_bloat_ratio NUMERIC;
    v_max_acceptable NUMERIC;
    v_critical NUMERIC;
BEGIN
    -- Get bloat thresholds
    SELECT max_acceptable_bloat_ratio, critical_bloat_ratio
    INTO v_max_acceptable, v_critical
    FROM logs_validation.cardinality_rules
    ORDER BY rule_id DESC
    LIMIT 1;

    -- Get table sizes
    EXECUTE format('SELECT pg_total_relation_size(%L)', p_schema_name || '.' || p_baseline_table)
    INTO v_baseline_size;

    EXECUTE format('SELECT pg_total_relation_size(%L)', p_schema_name || '.' || p_pax_table)
    INTO v_pax_size;

    v_bloat_ratio := v_pax_size::NUMERIC / NULLIF(v_baseline_size, 0);

    RETURN QUERY
    SELECT
        p_baseline_table::TEXT,
        (v_baseline_size / 1024.0 / 1024.0)::NUMERIC(10,2),
        p_pax_table::TEXT,
        (v_pax_size / 1024.0 / 1024.0)::NUMERIC(10,2),
        v_bloat_ratio::NUMERIC(4,2),
        CASE
            WHEN v_bloat_ratio <= v_max_acceptable THEN '✅ ACCEPTABLE'
            WHEN v_bloat_ratio <= v_critical THEN '🟠 WARNING'
            ELSE '❌ CRITICAL BLOAT'
        END::TEXT,
        CASE
            WHEN v_bloat_ratio <= v_max_acceptable THEN
                'PAX configuration is optimal'
            WHEN v_bloat_ratio <= v_critical THEN
                'Review bloom filter configuration - moderate bloat detected'
            ELSE
                'CRITICAL: Bloom filters on low-cardinality columns - recreate table without them'
        END::TEXT;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ Bloat detection function created'
\echo ''

-- =====================================================
-- Function: Generate Safe PAX Configuration
-- Based on cardinality analysis
-- =====================================================

\echo 'Creating configuration generator function...'

CREATE OR REPLACE FUNCTION logs_validation.generate_pax_config(
    p_schema_name TEXT,
    p_table_name TEXT
) RETURNS TABLE(
    config_section TEXT,
    config_value TEXT
) AS $$
DECLARE
    v_bloom_columns TEXT;
    v_minmax_columns TEXT;
    v_min_bloom INTEGER;
BEGIN
    -- Get threshold
    SELECT min_distinct_bloom
    INTO v_min_bloom
    FROM logs_validation.cardinality_rules
    ORDER BY rule_id DESC
    LIMIT 1;

    -- Build bloom filter columns (only high-cardinality)
    SELECT string_agg(attname, ',')
    INTO v_bloom_columns
    FROM pg_stats
    WHERE schemaname = p_schema_name
      AND tablename = p_table_name
      AND ABS(n_distinct) >= v_min_bloom;

    -- Build minmax columns (all filterable columns)
    SELECT string_agg(attname, ',')
    INTO v_minmax_columns
    FROM pg_stats
    WHERE schemaname = p_schema_name
      AND tablename = p_table_name
      AND ABS(n_distinct) >= 10
      AND atttypid IN (
          'integer'::regtype, 'bigint'::regtype, 'numeric'::regtype,
          'date'::regtype, 'timestamp'::regtype, 'timestamptz'::regtype,
          'text'::regtype, 'varchar'::regtype
      );

    RETURN QUERY
    SELECT 'bloomfilter_columns'::TEXT, COALESCE(v_bloom_columns, 'none')::TEXT
    UNION ALL
    SELECT 'minmax_columns'::TEXT, COALESCE(v_minmax_columns, 'none')::TEXT;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ Configuration generator function created'
\echo ''

\echo '===================================================='
\echo 'Validation framework ready!'
\echo '===================================================='
\echo ''
\echo 'Available validation functions:'
\echo '  1. logs_validation.validate_bloom_candidates() - Pre-creation validation'
\echo '  2. logs_validation.calculate_cluster_memory()  - Memory planning'
\echo '  3. logs_validation.detect_storage_bloat()      - Post-creation validation'
\echo '  4. logs_validation.generate_pax_config()       - Auto-config generation'
\echo ''
\echo 'Next: Phase 1 - Setup schema'
\echo ''
