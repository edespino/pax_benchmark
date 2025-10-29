--
-- Phase 0: Validation Framework (Core Innovation)
-- Prevents PAX misconfiguration through automated validation
-- Based on lessons learned from October 2025 bloom filter disaster
--

\timing on

\echo '===================================================='
\echo 'IoT Benchmark - Phase 0: Validation Framework Setup'
\echo '===================================================='
\echo ''

-- =====================================================
-- Create Validation Schema
-- =====================================================

\echo 'Creating validation schema...'

DROP SCHEMA IF EXISTS iot_validation CASCADE;
CREATE SCHEMA iot_validation;

\echo '  ✓ Validation schema created'
\echo ''

-- =====================================================
-- Validation Rules Table
-- Based on October 2025 testing results
-- =====================================================

\echo 'Creating validation rules table...'

CREATE TABLE iot_validation.cardinality_rules (
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
INSERT INTO iot_validation.cardinality_rules (notes) VALUES (
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

CREATE OR REPLACE FUNCTION iot_validation.validate_bloom_candidates(
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
    FROM iot_validation.cardinality_rules
    ORDER BY rule_id DESC
    LIMIT 1;

    RETURN QUERY
    SELECT
        s.attname::TEXT,
        s.n_distinct,
        CASE
            WHEN s.n_distinct >= 0 THEN s.n_distinct::BIGINT
            ELSE (s.reltuples * ABS(s.n_distinct))::BIGINT
        END AS cardinality_estimate,
        CASE
            WHEN ABS(s.n_distinct::NUMERIC) >= v_min_bloom THEN '✅ SAFE'::TEXT
            WHEN ABS(s.n_distinct::NUMERIC) >= v_warn_bloom THEN '🟠 WARNING'::TEXT
            ELSE '❌ UNSAFE'::TEXT
        END AS verdict,
        CASE
            WHEN ABS(s.n_distinct::NUMERIC) >= v_min_bloom THEN
                'High cardinality (' || ABS(s.n_distinct)::TEXT || ' unique values) - bloom filter will provide significant file-level pruning'
            WHEN ABS(s.n_distinct::NUMERIC) >= v_warn_bloom THEN
                'Borderline cardinality (' || ABS(s.n_distinct)::TEXT || ' unique) - consider cost/benefit. May waste storage for minimal gain.'
            ELSE
                '🔴 CRITICAL: TOO LOW (' || ABS(s.n_distinct)::TEXT || ' unique) - bloom filter will cause MASSIVE storage bloat! Remove from bloomfilter_columns!'
        END::TEXT AS reason,
        CASE
            WHEN ABS(s.n_distinct::NUMERIC) >= v_min_bloom THEN
                'Add to bloomfilter_columns AND minmax_columns'::TEXT
            WHEN ABS(s.n_distinct::NUMERIC) >= v_warn_bloom THEN
                'Test with and without bloom filter, measure impact. Consider minmax_columns only.'::TEXT
            ELSE
                '❌ REMOVE from bloomfilter_columns. Use minmax_columns instead (if cardinality > 10).'::TEXT
        END AS recommendation
    FROM pg_stats s
    CROSS JOIN (
        SELECT c.reltuples
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = p_schema_name
          AND c.relname = p_table_name
    ) r
    WHERE s.schemaname = p_schema_name
      AND s.tablename = p_table_name
      AND s.attname = ANY(p_proposed_bloom_columns)
    ORDER BY ABS(s.n_distinct) DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION iot_validation.validate_bloom_candidates IS
'Validates proposed bloom filter columns against cardinality thresholds. Returns SAFE/WARNING/UNSAFE verdict for each column. CRITICAL: Run this BEFORE creating PAX tables to prevent 80%+ storage bloat.';

\echo '  ✓ Bloom filter validation function created'
\echo ''

-- =====================================================
-- Function: Calculate Required Clustering Memory
-- Formula from October 2025 testing
-- =====================================================

\echo 'Creating memory calculation function...'

CREATE OR REPLACE FUNCTION iot_validation.calculate_cluster_memory(
    p_table_rows BIGINT
) RETURNS TABLE(
    rows BIGINT,
    base_memory_mb BIGINT,
    recommended_memory_mb BIGINT,
    recommended_memory_setting TEXT,
    rationale TEXT
) AS $$
DECLARE
    v_memory_per_million INTEGER;
    v_safety_margin NUMERIC;
    v_base_mb BIGINT;
    v_recommended_mb BIGINT;
BEGIN
    -- Get current rules
    SELECT memory_per_million_rows, memory_safety_margin
    INTO v_memory_per_million, v_safety_margin
    FROM iot_validation.cardinality_rules
    ORDER BY rule_id DESC
    LIMIT 1;

    -- Calculate base memory requirement
    v_base_mb := CEIL((p_table_rows::NUMERIC / 1000000.0) * v_memory_per_million);

    -- Add safety margin
    v_recommended_mb := CEIL(v_base_mb * v_safety_margin);

    -- Ensure minimum of 64MB
    IF v_recommended_mb < 64 THEN
        v_recommended_mb := 64;
    END IF;

    RETURN QUERY
    SELECT
        p_table_rows,
        v_base_mb,
        v_recommended_mb,
        v_recommended_mb || 'MB'::TEXT AS recommended_memory_setting,
        'Formula: (' || p_table_rows || ' rows / 1M) * ' || v_memory_per_million || 'MB * ' ||
        v_safety_margin || ' safety margin = ' || v_recommended_mb || 'MB. ' ||
        'Set maintenance_work_mem to this value BEFORE running CLUSTER to prevent storage bloat.'::TEXT
    ;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION iot_validation.calculate_cluster_memory IS
'Calculates required maintenance_work_mem for Z-order clustering. Based on testing: ~200MB per 1M rows + 20% safety margin. Low memory during clustering causes storage bloat.';

\echo '  ✓ Memory calculation function created'
\echo ''

-- =====================================================
-- Function: Detect Storage Bloat (Post-Creation Check)
-- =====================================================

\echo 'Creating bloat detection function...'

CREATE OR REPLACE FUNCTION iot_validation.detect_storage_bloat(
    p_schema_name TEXT,
    p_baseline_table TEXT,   -- e.g., 'readings_aoco' (no clustering)
    p_test_table TEXT         -- e.g., 'readings_pax' (with clustering)
) RETURNS TABLE(
    baseline_table TEXT,
    baseline_size_mb NUMERIC,
    test_table TEXT,
    test_size_mb NUMERIC,
    bloat_mb NUMERIC,
    bloat_ratio NUMERIC,
    verdict TEXT,
    analysis TEXT
) AS $$
DECLARE
    v_max_acceptable NUMERIC;
    v_critical NUMERIC;
BEGIN
    -- Get bloat thresholds
    SELECT max_acceptable_bloat_ratio, critical_bloat_ratio
    INTO v_max_acceptable, v_critical
    FROM iot_validation.cardinality_rules
    ORDER BY rule_id DESC
    LIMIT 1;

    RETURN QUERY
    SELECT
        p_baseline_table::TEXT,
        ROUND((pg_total_relation_size(p_schema_name || '.' || p_baseline_table) / 1024.0 / 1024.0)::NUMERIC, 2) AS baseline_size_mb,
        p_test_table::TEXT,
        ROUND((pg_total_relation_size(p_schema_name || '.' || p_test_table) / 1024.0 / 1024.0)::NUMERIC, 2) AS test_size_mb,
        ROUND(((pg_total_relation_size(p_schema_name || '.' || p_test_table) -
                pg_total_relation_size(p_schema_name || '.' || p_baseline_table)) / 1024.0 / 1024.0)::NUMERIC, 2) AS bloat_mb,
        ROUND((pg_total_relation_size(p_schema_name || '.' || p_test_table)::NUMERIC /
               pg_total_relation_size(p_schema_name || '.' || p_baseline_table)::NUMERIC), 2) AS bloat_ratio,
        CASE
            WHEN (pg_total_relation_size(p_schema_name || '.' || p_test_table)::NUMERIC /
                  pg_total_relation_size(p_schema_name || '.' || p_baseline_table)::NUMERIC) < v_max_acceptable
                THEN '✅ HEALTHY'::TEXT
            WHEN (pg_total_relation_size(p_schema_name || '.' || p_test_table)::NUMERIC /
                  pg_total_relation_size(p_schema_name || '.' || p_baseline_table)::NUMERIC) < v_critical
                THEN '🟠 WARNING'::TEXT
            ELSE '❌ CRITICAL'::TEXT
        END AS verdict,
        CASE
            WHEN (pg_total_relation_size(p_schema_name || '.' || p_test_table)::NUMERIC /
                  pg_total_relation_size(p_schema_name || '.' || p_baseline_table)::NUMERIC) < v_max_acceptable
                THEN 'Storage overhead is acceptable. PAX configuration is healthy.'
            WHEN (pg_total_relation_size(p_schema_name || '.' || p_test_table)::NUMERIC /
                  pg_total_relation_size(p_schema_name || '.' || p_baseline_table)::NUMERIC) < v_critical
                THEN 'Storage bloat detected. Review bloom filter configuration and maintenance_work_mem setting.'
            ELSE '🔴 CRITICAL BLOAT DETECTED! Likely causes: (1) Bloom filters on low-cardinality columns, (2) Insufficient maintenance_work_mem during clustering. Run sql/02_analyze_cardinality.sql to diagnose.'
        END::TEXT AS analysis;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION iot_validation.detect_storage_bloat IS
'Compares storage size of PAX table vs baseline (AOCO). Detects misconfiguration by identifying excessive bloat (>30% = warning, >50% = critical). Run after CLUSTER to validate configuration effectiveness.';

\echo '  ✓ Bloat detection function created'
\echo ''

-- =====================================================
-- Function: Generate Safe PAX Configuration
-- Auto-generates configuration from cardinality analysis
-- =====================================================

\echo 'Creating auto-configuration generator...'

CREATE OR REPLACE FUNCTION iot_validation.generate_pax_config(
    p_schema_name TEXT,
    p_sample_table TEXT,
    p_target_rows BIGINT,
    p_cluster_columns TEXT DEFAULT NULL  -- e.g., 'reading_time,device_id'
) RETURNS TEXT AS $$
DECLARE
    v_bloom_cols TEXT;
    v_minmax_cols TEXT;
    v_cluster_mem TEXT;
    v_config TEXT;
    v_min_bloom INTEGER;
    v_min_minmax INTEGER;
    v_max_bloom INTEGER;
BEGIN
    -- Get current rules
    SELECT min_distinct_bloom, min_distinct_minmax, max_bloom_columns
    INTO v_min_bloom, v_min_minmax, v_max_bloom
    FROM iot_validation.cardinality_rules
    ORDER BY rule_id DESC
    LIMIT 1;

    -- Auto-select bloom filter columns (cardinality >= threshold, max 3 columns)
    SELECT string_agg(attname, ',')
    INTO v_bloom_cols
    FROM (
        SELECT attname
        FROM pg_stats
        WHERE schemaname = p_schema_name
          AND tablename = p_sample_table
          AND ABS(n_distinct::NUMERIC) >= v_min_bloom
        ORDER BY ABS(n_distinct) DESC
        LIMIT v_max_bloom
    ) high_card;

    -- Auto-select minmax columns (cardinality >= 10, exclude very low cardinality)
    SELECT string_agg(attname, ',')
    INTO v_minmax_cols
    FROM (
        SELECT attname
        FROM pg_stats
        WHERE schemaname = p_schema_name
          AND tablename = p_sample_table
          AND ABS(n_distinct::NUMERIC) >= v_min_minmax
        ORDER BY ABS(n_distinct) DESC
        LIMIT 15  -- Reasonable limit for minmax (low overhead)
    ) medium_card;

    -- Calculate required memory
    SELECT recommended_memory_setting
    INTO v_cluster_mem
    FROM iot_validation.calculate_cluster_memory(p_target_rows);

    -- Generate configuration
    v_config := format(E'--\n-- Auto-Generated PAX Configuration\n-- Generated: %s\n-- Target rows: %s\n-- Bloom filter columns: %s\n-- MinMax columns: %s\n-- Required memory: %s\n--\n\n',
        NOW()::TEXT,
        p_target_rows,
        COALESCE(v_bloom_cols, 'NONE (no high-cardinality columns found)'),
        COALESCE(v_minmax_cols, 'NONE'),
        v_cluster_mem
    );

    v_config := v_config || format(E'CREATE TABLE %s.your_table_name (...) USING pax WITH (\n', p_schema_name);
    v_config := v_config || E'    -- Core compression\n';
    v_config := v_config || E'    compresstype=''zstd'',\n';
    v_config := v_config || E'    compresslevel=5,\n';
    v_config := v_config || E'    \n';

    IF v_bloom_cols IS NOT NULL THEN
        v_config := v_config || E'    -- Bloom filters (AUTO-VALIDATED: cardinality >= ' || v_min_bloom || E')\n';
        v_config := v_config || E'    bloomfilter_columns=''' || v_bloom_cols || E''',\n';
        v_config := v_config || E'    \n';
    ELSE
        v_config := v_config || E'    -- Bloom filters: NONE (no columns met cardinality threshold)\n';
        v_config := v_config || E'    -- bloomfilter_columns='''',  -- Intentionally empty\n';
        v_config := v_config || E'    \n';
    END IF;

    IF v_minmax_cols IS NOT NULL THEN
        v_config := v_config || E'    -- MinMax statistics (AUTO-VALIDATED: cardinality >= ' || v_min_minmax || E')\n';
        v_config := v_config || E'    minmax_columns=''' || v_minmax_cols || E''',\n';
        v_config := v_config || E'    \n';
    END IF;

    IF p_cluster_columns IS NOT NULL THEN
        v_config := v_config || E'    -- Z-order clustering\n';
        v_config := v_config || E'    cluster_type=''zorder'',\n';
        v_config := v_config || E'    cluster_columns=''' || p_cluster_columns || E''',\n';
        v_config := v_config || E'    \n';
    END IF;

    v_config := v_config || E'    -- Storage format\n';
    v_config := v_config || E'    storage_format=''porc''\n';
    v_config := v_config || E');\n\n';

    v_config := v_config || E'-- CRITICAL: Set maintenance_work_mem BEFORE clustering\n';
    v_config := v_config || E'SET maintenance_work_mem = ''' || v_cluster_mem || E''';\n';
    v_config := v_config || E'CLUSTER your_table_name USING your_zorder_index;\n';

    RETURN v_config;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION iot_validation.generate_pax_config IS
'Auto-generates safe PAX configuration from cardinality analysis. Automatically selects bloom filter columns (cardinality >= 1000), minmax columns (cardinality >= 10), and calculates required memory. Prevents manual configuration errors.';

\echo '  ✓ Auto-configuration generator created'
\echo ''

-- =====================================================
-- Verification Query
-- =====================================================

\echo 'Validation framework summary:'
\echo ''

SELECT
    'Bloom filter minimum cardinality' AS setting,
    min_distinct_bloom::TEXT AS value,
    'Columns below this threshold will cause storage bloat' AS description
FROM iot_validation.cardinality_rules
WHERE rule_id = 1

UNION ALL

SELECT
    'MinMax minimum cardinality',
    min_distinct_minmax::TEXT,
    'Columns below this threshold provide no filtering benefit'
FROM iot_validation.cardinality_rules
WHERE rule_id = 1

UNION ALL

SELECT
    'Maximum bloom filter columns',
    max_bloom_columns::TEXT,
    'Safety limit to prevent excessive overhead'
FROM iot_validation.cardinality_rules
WHERE rule_id = 1

UNION ALL

SELECT
    'Memory per 1M rows',
    memory_per_million_rows::TEXT || ' MB',
    'Base memory requirement for Z-order clustering'
FROM iot_validation.cardinality_rules
WHERE rule_id = 1

UNION ALL

SELECT
    'Memory safety margin',
    (memory_safety_margin * 100)::TEXT || '%',
    'Additional buffer to prevent clustering memory issues'
FROM iot_validation.cardinality_rules
WHERE rule_id = 1;

\echo ''
\echo '===================================================='
\echo 'Validation framework ready!'
\echo '===================================================='
\echo ''
\echo 'Available functions:'
\echo '  • iot_validation.validate_bloom_candidates(...)'
\echo '  • iot_validation.calculate_cluster_memory(...)'
\echo '  • iot_validation.detect_storage_bloat(...)'
\echo '  • iot_validation.generate_pax_config(...)'
\echo ''
\echo 'Next: Phase 1 - Setup IoT schema'
