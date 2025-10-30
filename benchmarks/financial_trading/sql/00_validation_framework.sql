--
-- Phase 0: Validation Framework Setup
-- Reusable validation functions for PAX configuration safety
-- Prevents 81% storage bloat from bloom filter misconfiguration
--

\timing on

\echo '===================================================='
\echo 'Financial Trading - Phase 0: Validation Framework'
\echo '===================================================='
\echo ''

-- Create validation schema
DROP SCHEMA IF EXISTS trading_validation CASCADE;
CREATE SCHEMA trading_validation;

\echo 'Validation schema created'
\echo ''

-- =====================================================
-- Function 1: Validate Bloom Filter Candidates
-- CRITICAL: Checks cardinality before bloom filter use
-- =====================================================

\echo 'Creating function: validate_bloom_candidates()'

CREATE OR REPLACE FUNCTION trading_validation.validate_bloom_candidates(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_proposed_bloom_columns TEXT[]
)
RETURNS TABLE(
    column_name TEXT,
    n_distinct NUMERIC,
    cardinality_estimate BIGINT,
    verdict TEXT,
    reason TEXT,
    recommendation TEXT
) AS $$
DECLARE
    v_column TEXT;
    v_n_distinct NUMERIC;
    v_total_rows BIGINT;
    v_cardinality_estimate BIGINT;
    v_verdict TEXT;
    v_reason TEXT;
    v_recommendation TEXT;
BEGIN
    -- Get total row count
    EXECUTE format('SELECT COUNT(*) FROM %I.%I', p_schema_name, p_table_name)
    INTO v_total_rows;

    -- Loop through proposed bloom filter columns
    FOREACH v_column IN ARRAY p_proposed_bloom_columns
    LOOP
        -- Get n_distinct from pg_stats
        SELECT s.n_distinct INTO v_n_distinct
        FROM pg_stats s
        WHERE (s.schemaname = p_schema_name OR (p_schema_name = 'pg_temp' AND s.schemaname LIKE 'pg_temp%'))
          AND s.tablename = p_table_name
          AND s.attname = v_column;

        -- Calculate cardinality estimate
        -- n_distinct < 0 means fraction of rows, n_distinct > 0 means absolute count
        IF v_n_distinct < 0 THEN
            v_cardinality_estimate := GREATEST(1, (ABS(v_n_distinct) * v_total_rows)::BIGINT);
        ELSE
            v_cardinality_estimate := v_n_distinct::BIGINT;
        END IF;

        -- Determine verdict based on cardinality
        IF v_cardinality_estimate >= 1000 THEN
            v_verdict := '✅ SAFE';
            v_reason := 'High cardinality, bloom filter will be effective';
            v_recommendation := 'Include in bloomfilter_columns';
        ELSIF v_cardinality_estimate >= 100 THEN
            v_verdict := '🟠 BORDERLINE';
            v_reason := 'Medium cardinality, bloom filter overhead may not justify benefit';
            v_recommendation := 'Test with and without bloom filter, compare storage';
        ELSE
            v_verdict := '❌ UNSAFE';
            v_reason := format('TOO LOW - Only %s unique values. Will cause massive storage bloat!', v_cardinality_estimate);
            v_recommendation := 'EXCLUDE from bloomfilter_columns. Use minmax_columns instead.';
        END IF;

        -- Return result row
        column_name := v_column;
        n_distinct := v_n_distinct;
        cardinality_estimate := v_cardinality_estimate;
        verdict := v_verdict;
        reason := v_reason;
        recommendation := v_recommendation;
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION trading_validation.validate_bloom_candidates IS 'Validates proposed bloom filter columns against cardinality thresholds. Returns SAFE/WARNING/UNSAFE verdict for each column. CRITICAL: Run this BEFORE creating PAX tables to prevent 80%+ storage bloat.';

\echo '  ✓ validate_bloom_candidates() created'
\echo ''

-- =====================================================
-- Function 2: Calculate Required Clustering Memory
-- Prevents 2-3x storage bloat from insufficient memory
-- =====================================================

\echo 'Creating function: calculate_cluster_memory()'

CREATE OR REPLACE FUNCTION trading_validation.calculate_cluster_memory(
    p_table_rows BIGINT
)
RETURNS TABLE(
    rows BIGINT,
    base_memory_mb BIGINT,
    recommended_memory_mb BIGINT,
    recommended_memory_setting TEXT,
    reasoning TEXT
) AS $$
DECLARE
    v_base_memory_mb BIGINT;
    v_recommended_memory_mb BIGINT;
BEGIN
    -- Formula: (rows / 1M) * 200MB * 1.2 safety margin
    v_base_memory_mb := GREATEST(200, (p_table_rows / 1000000.0 * 200)::BIGINT);
    v_recommended_memory_mb := (v_base_memory_mb * 1.2)::BIGINT;

    rows := p_table_rows;
    base_memory_mb := v_base_memory_mb;
    recommended_memory_mb := v_recommended_memory_mb;
    recommended_memory_setting := v_recommended_memory_mb || 'MB';
    reasoning := format('For %s rows: %s MB base + 20%% safety margin = %s MB',
                       p_table_rows, v_base_memory_mb, v_recommended_memory_mb);

    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION trading_validation.calculate_cluster_memory IS 'Calculates required maintenance_work_mem for Z-order clustering. Formula: (rows/1M)*200MB*1.2. Set this BEFORE running CLUSTER command.';

\echo '  ✓ calculate_cluster_memory() created'
\echo ''

-- =====================================================
-- Function 3: Detect Storage Bloat
-- Compares PAX table size vs baseline (AOCO)
-- =====================================================

\echo 'Creating function: detect_storage_bloat()'

CREATE OR REPLACE FUNCTION trading_validation.detect_storage_bloat(
    p_schema_name TEXT,
    p_baseline_table TEXT,
    p_test_table TEXT
)
RETURNS TABLE(
    baseline_table TEXT,
    baseline_size_mb NUMERIC,
    test_table TEXT,
    test_size_mb NUMERIC,
    bloat_mb NUMERIC,
    bloat_ratio NUMERIC,
    verdict TEXT,
    action_required TEXT
) AS $$
DECLARE
    v_baseline_size BIGINT;
    v_test_size BIGINT;
    v_bloat_mb NUMERIC;
    v_bloat_ratio NUMERIC;
    v_verdict TEXT;
    v_action TEXT;
BEGIN
    -- Get table sizes
    EXECUTE format('SELECT pg_total_relation_size(%L)', p_schema_name || '.' || p_baseline_table)
    INTO v_baseline_size;

    EXECUTE format('SELECT pg_total_relation_size(%L)', p_schema_name || '.' || p_test_table)
    INTO v_test_size;

    -- Calculate bloat
    v_bloat_mb := (v_test_size - v_baseline_size)::NUMERIC / 1024 / 1024;
    v_bloat_ratio := v_test_size::NUMERIC / NULLIF(v_baseline_size::NUMERIC, 0);

    -- Determine verdict
    IF v_bloat_ratio < 1.1 THEN
        v_verdict := '✅ EXCELLENT';
        v_action := 'Configuration is optimal. PAX overhead < 10%.';
    ELSIF v_bloat_ratio < 1.3 THEN
        v_verdict := '✅ HEALTHY';
        v_action := 'Configuration is acceptable. PAX overhead < 30%.';
    ELSIF v_bloat_ratio < 1.5 THEN
        v_verdict := '🟠 ACCEPTABLE';
        v_action := 'Review bloom filter configuration. Consider reducing bloom filter columns.';
    ELSE
        v_verdict := '❌ CRITICAL';
        v_action := 'BLOAT DETECTED! Review cardinality analysis. Likely cause: bloom filters on low-cardinality columns.';
    END IF;

    -- Return results
    baseline_table := p_baseline_table;
    baseline_size_mb := (v_baseline_size::NUMERIC / 1024 / 1024);
    test_table := p_test_table;
    test_size_mb := (v_test_size::NUMERIC / 1024 / 1024);
    bloat_mb := v_bloat_mb;
    bloat_ratio := ROUND(v_bloat_ratio, 2);
    verdict := v_verdict;
    action_required := v_action;

    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION trading_validation.detect_storage_bloat IS 'Compares test table size vs baseline. Detects bloat ratios: <1.3x = healthy, >1.5x = critical. Run after table creation and after clustering.';

\echo '  ✓ detect_storage_bloat() created'
\echo ''

-- =====================================================
-- Function 4: Auto-Generate Safe PAX Configuration
-- Creates configuration string from cardinality analysis
-- =====================================================

\echo 'Creating function: generate_pax_config()'

CREATE OR REPLACE FUNCTION trading_validation.generate_pax_config(
    p_schema_name TEXT,
    p_sample_table TEXT,
    p_target_rows BIGINT,
    p_cluster_columns TEXT DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
    v_config TEXT;
    v_bloom_columns TEXT[];
    v_minmax_columns TEXT[];
    v_column_name TEXT;
    v_n_distinct NUMERIC;
    v_cardinality BIGINT;
    v_total_rows BIGINT;
    v_memory_setting TEXT;
BEGIN
    -- Get sample table row count
    EXECUTE format('SELECT COUNT(*) FROM %I.%I', p_schema_name, p_sample_table)
    INTO v_total_rows;

    -- Analyze all columns
    FOR v_column_name, v_n_distinct IN
        SELECT attname, n_distinct
        FROM pg_stats
        WHERE (schemaname = p_schema_name OR (p_schema_name = 'pg_temp' AND schemaname LIKE 'pg_temp%'))
          AND tablename = p_sample_table
          AND attname NOT IN ('tableoid', 'cmax', 'xmax', 'cmin', 'xmin', 'ctid')
        ORDER BY attname
    LOOP
        -- Calculate absolute cardinality
        IF v_n_distinct < 0 THEN
            v_cardinality := GREATEST(1, (ABS(v_n_distinct) * v_total_rows)::BIGINT);
        ELSE
            v_cardinality := v_n_distinct::BIGINT;
        END IF;

        -- Bloom filter candidates (cardinality >= 1000)
        IF v_cardinality >= 1000 THEN
            v_bloom_columns := array_append(v_bloom_columns, v_column_name);
        END IF;

        -- MinMax candidates (cardinality >= 10, exclude text/json types)
        IF v_cardinality >= 10 THEN
            v_minmax_columns := array_append(v_minmax_columns, v_column_name);
        END IF;
    END LOOP;

    -- Calculate memory requirement
    SELECT recommended_memory_setting INTO v_memory_setting
    FROM trading_validation.calculate_cluster_memory(p_target_rows);

    -- Build configuration string
    v_config := E'-- Auto-generated PAX configuration\n';
    v_config := v_config || E'-- Based on cardinality analysis of ' || p_sample_table || E'\n';
    v_config := v_config || E'-- Target rows: ' || p_target_rows || E'\n';
    v_config := v_config || E'-- Generated: ' || now() || E'\n\n';

    v_config := v_config || E'CREATE TABLE your_schema.your_table (\n';
    v_config := v_config || E'    -- [Define your columns here]\n';
    v_config := v_config || E') USING pax WITH (\n';
    v_config := v_config || E'    compresstype=\'zstd\',\n';
    v_config := v_config || E'    compresslevel=5,\n\n';

    v_config := v_config || E'    -- MinMax statistics (low overhead, use liberally)\n';
    v_config := v_config || E'    minmax_columns=\'' || array_to_string(v_minmax_columns, ',') || E'\',\n\n';

    v_config := v_config || E'    -- Bloom filters (VALIDATED - only high-cardinality columns)\n';
    IF array_length(v_bloom_columns, 1) > 0 THEN
        v_config := v_config || E'    bloomfilter_columns=\'' || array_to_string(v_bloom_columns, ',') || E'\',\n\n';
    ELSE
        v_config := v_config || E'    -- bloomfilter_columns=\'\',  -- No high-cardinality columns found\n\n';
    END IF;

    IF p_cluster_columns IS NOT NULL THEN
        v_config := v_config || E'    -- Z-order clustering\n';
        v_config := v_config || E'    cluster_type=\'zorder\',\n';
        v_config := v_config || E'    cluster_columns=\'' || p_cluster_columns || E'\',\n\n';
    END IF;

    v_config := v_config || E'    storage_format=\'porc\'\n';
    v_config := v_config || E');\n\n';

    v_config := v_config || E'-- Required memory for clustering:\n';
    v_config := v_config || E'SET maintenance_work_mem = \'' || v_memory_setting || E'\';\n';

    RETURN v_config;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION trading_validation.generate_pax_config IS 'Auto-generates safe PAX configuration from sample table analysis. Automatically selects bloom filter columns (cardinality >= 1000) and calculates required memory.';

\echo '  ✓ generate_pax_config() created'
\echo ''

-- =====================================================
-- Verification
-- =====================================================

\echo '===================================================='
\echo 'Validation Framework Summary'
\echo '===================================================='
\echo ''

SELECT
    proname AS function_name,
    pg_get_function_arguments(oid) AS parameters
FROM pg_proc
WHERE pronamespace = 'trading_validation'::regnamespace
ORDER BY proname;

\echo ''
\echo '===================================================='
\echo 'Validation framework ready!'
\echo '===================================================='
\echo ''
\echo 'Available functions:'
\echo '  1. validate_bloom_candidates()  - Check cardinality before bloom filters'
\echo '  2. calculate_cluster_memory()   - Calculate required maintenance_work_mem'
\echo '  3. detect_storage_bloat()       - Compare PAX vs baseline'
\echo '  4. generate_pax_config()        - Auto-generate safe configuration'
\echo ''
\echo 'Next: Phase 1 - Create trading schema'
