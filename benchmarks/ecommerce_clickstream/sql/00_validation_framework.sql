--
-- Phase 0: E-commerce Clickstream Validation Framework
-- Prevents PAX misconfiguration disasters through automated validation
--

\timing on

\echo '===================================================='
\echo 'E-commerce Clickstream - Phase 0: Validation Framework'
\echo '===================================================='
\echo ''

-- Create schema for validation functions
DROP SCHEMA IF EXISTS ecommerce_validation CASCADE;
CREATE SCHEMA ecommerce_validation;

\echo 'Creating validation functions...'
\echo ''

-- =====================================================
-- FUNCTION 1: Validate Bloom Filter Candidates
-- Checks cardinality of columns to prevent low-cardinality bloom filters
-- =====================================================

CREATE OR REPLACE FUNCTION ecommerce_validation.validate_bloom_candidates(
    schema_name TEXT,
    table_name TEXT,
    candidate_columns TEXT[]
)
RETURNS TABLE (
    column_name TEXT,
    distinct_count BIGINT,
    total_rows BIGINT,
    cardinality_ratio NUMERIC,
    recommendation TEXT,
    is_safe BOOLEAN
) AS $$
DECLARE
    col TEXT;
    query TEXT;
    n_distinct BIGINT;
    n_total BIGINT;
BEGIN
    -- Get total row count
    EXECUTE format('SELECT COUNT(*) FROM %I.%I', schema_name, table_name) INTO n_total;

    FOREACH col IN ARRAY candidate_columns LOOP
        -- Count distinct values for this column
        query := format('SELECT COUNT(DISTINCT %I) FROM %I.%I', col, schema_name, table_name);
        EXECUTE query INTO n_distinct;

        -- Return results with recommendations
        column_name := col;
        distinct_count := n_distinct;
        total_rows := n_total;
        cardinality_ratio := ROUND((n_distinct::NUMERIC / n_total::NUMERIC) * 100, 2);

        -- Recommendation logic
        IF n_distinct >= 10000 THEN
            recommendation := '✅ SAFE for bloom filter (high cardinality)';
            is_safe := TRUE;
        ELSIF n_distinct >= 1000 THEN
            recommendation := '🟠 BORDERLINE - consider minmax only';
            is_safe := FALSE;
        ELSE
            recommendation := '❌ UNSAFE - use minmax instead (low cardinality)';
            is_safe := FALSE;
        END IF;

        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ validate_bloom_candidates() created'

-- =====================================================
-- FUNCTION 2: Calculate Clustering Memory Requirements
-- Estimates maintenance_work_mem needed for Z-order clustering
-- =====================================================

CREATE OR REPLACE FUNCTION ecommerce_validation.calculate_cluster_memory(
    schema_name TEXT,
    table_name TEXT
)
RETURNS TABLE (
    table_rows BIGINT,
    table_size_mb NUMERIC,
    recommended_maintenance_work_mem TEXT,
    minimum_work_mem_mb INTEGER,
    optimal_work_mem_mb INTEGER
) AS $$
DECLARE
    row_count BIGINT;
    size_bytes BIGINT;
    size_mb NUMERIC;
    min_mem INTEGER;
    opt_mem INTEGER;
BEGIN
    -- Get table statistics
    EXECUTE format('SELECT COUNT(*) FROM %I.%I', schema_name, table_name) INTO row_count;
    EXECUTE format('SELECT pg_total_relation_size(%L)', schema_name || '.' || table_name) INTO size_bytes;
    size_mb := ROUND(size_bytes / (1024.0 * 1024.0), 2);

    -- Calculate memory requirements
    -- Rule: minimum 200 bytes per row for sorting, optimal is 2x table size
    min_mem := GREATEST(128, CEIL(row_count * 200 / (1024.0 * 1024.0)));
    opt_mem := GREATEST(min_mem * 2, CEIL(size_mb * 2));

    -- Return recommendation
    table_rows := row_count;
    table_size_mb := size_mb;
    minimum_work_mem_mb := min_mem;
    optimal_work_mem_mb := opt_mem;

    IF opt_mem <= 2048 THEN
        recommended_maintenance_work_mem := opt_mem || 'MB (good for 10M rows)';
    ELSIF opt_mem <= 8192 THEN
        recommended_maintenance_work_mem := opt_mem || 'MB (for larger datasets)';
    ELSE
        recommended_maintenance_work_mem := '8GB (max safe value, consider smaller batches)';
    END IF;

    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ calculate_cluster_memory() created'

-- =====================================================
-- FUNCTION 3: Detect Storage Bloat
-- Compares PAX variants against AOCO baseline
-- =====================================================

CREATE OR REPLACE FUNCTION ecommerce_validation.detect_storage_bloat(
    schema_name TEXT,
    baseline_table TEXT,
    pax_no_cluster_table TEXT,
    pax_clustered_table TEXT
)
RETURNS TABLE (
    variant TEXT,
    size_mb NUMERIC,
    vs_baseline_mb NUMERIC,
    vs_baseline_pct NUMERIC,
    assessment TEXT
) AS $$
DECLARE
    baseline_size BIGINT;
    pax_nocluster_size BIGINT;
    pax_clustered_size BIGINT;
BEGIN
    -- Get sizes
    EXECUTE format('SELECT pg_total_relation_size(%L)', schema_name || '.' || baseline_table)
        INTO baseline_size;
    EXECUTE format('SELECT pg_total_relation_size(%L)', schema_name || '.' || pax_no_cluster_table)
        INTO pax_nocluster_size;
    EXECUTE format('SELECT pg_total_relation_size(%L)', schema_name || '.' || pax_clustered_table)
        INTO pax_clustered_size;

    -- Return baseline
    variant := 'AOCO (baseline)';
    size_mb := ROUND(baseline_size / (1024.0 * 1024.0), 2);
    vs_baseline_mb := 0;
    vs_baseline_pct := 0;
    assessment := 'Baseline for comparison';
    RETURN NEXT;

    -- Return PAX no-cluster
    variant := 'PAX (no-cluster)';
    size_mb := ROUND(pax_nocluster_size / (1024.0 * 1024.0), 2);
    vs_baseline_mb := ROUND((pax_nocluster_size - baseline_size) / (1024.0 * 1024.0), 2);
    vs_baseline_pct := ROUND(((pax_nocluster_size::NUMERIC / baseline_size::NUMERIC) - 1) * 100, 1);

    IF vs_baseline_pct <= 10 THEN
        assessment := '✅ Excellent (<10% overhead)';
    ELSIF vs_baseline_pct <= 20 THEN
        assessment := '✅ Good (10-20% overhead)';
    ELSIF vs_baseline_pct <= 30 THEN
        assessment := '🟠 Acceptable (20-30% overhead)';
    ELSE
        assessment := '❌ HIGH overhead (>30%) - check bloom filter config';
    END IF;
    RETURN NEXT;

    -- Return PAX clustered
    variant := 'PAX (clustered)';
    size_mb := ROUND(pax_clustered_size / (1024.0 * 1024.0), 2);
    vs_baseline_mb := ROUND((pax_clustered_size - baseline_size) / (1024.0 * 1024.0), 2);
    vs_baseline_pct := ROUND(((pax_clustered_size::NUMERIC / baseline_size::NUMERIC) - 1) * 100, 1);

    IF vs_baseline_pct <= 10 THEN
        assessment := '✅ Excellent clustering efficiency';
    ELSIF vs_baseline_pct <= 30 THEN
        assessment := '✅ Acceptable clustering overhead';
    ELSIF vs_baseline_pct <= 50 THEN
        assessment := '🟠 Moderate clustering overhead';
    ELSE
        assessment := '❌ HIGH clustering overhead (>50%) - too many bloom filters?';
    END IF;
    RETURN NEXT;

    -- Calculate clustering overhead
    variant := 'Clustering overhead';
    size_mb := ROUND((pax_clustered_size - pax_nocluster_size) / (1024.0 * 1024.0), 2);
    vs_baseline_mb := NULL;
    vs_baseline_pct := ROUND(((pax_clustered_size::NUMERIC / pax_nocluster_size::NUMERIC) - 1) * 100, 1);

    IF vs_baseline_pct <= 5 THEN
        assessment := '✅ Minimal overhead (<5%)';
    ELSIF vs_baseline_pct <= 30 THEN
        assessment := '✅ Acceptable overhead (5-30%)';
    ELSIF vs_baseline_pct <= 50 THEN
        assessment := '🟠 Moderate overhead (30-50%)';
    ELSE
        assessment := '❌ HIGH overhead (>50%) - investigate bloom filter count';
    END IF;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ detect_storage_bloat() created'

-- =====================================================
-- FUNCTION 4: Generate Safe PAX Configuration
-- Auto-generates PAX configuration from cardinality analysis
-- =====================================================

CREATE OR REPLACE FUNCTION ecommerce_validation.generate_pax_config(
    schema_name TEXT,
    table_name TEXT,
    candidate_bloom_columns TEXT[],
    candidate_minmax_columns TEXT[],
    cluster_columns TEXT[]
)
RETURNS TABLE (
    config_type TEXT,
    column_list TEXT,
    reason TEXT
) AS $$
DECLARE
    safe_bloom TEXT[];
    col TEXT;
    n_distinct BIGINT;
    query TEXT;
BEGIN
    -- Validate bloom filter candidates
    safe_bloom := ARRAY[]::TEXT[];

    FOREACH col IN ARRAY candidate_bloom_columns LOOP
        query := format('SELECT COUNT(DISTINCT %I) FROM %I.%I', col, schema_name, table_name);
        EXECUTE query INTO n_distinct;

        IF n_distinct >= 10000 THEN
            safe_bloom := array_append(safe_bloom, col);
        END IF;
    END LOOP;

    -- Return bloom filter config
    config_type := 'bloomfilter_columns';
    column_list := array_to_string(safe_bloom, ',');
    reason := format('High-cardinality columns (>10K unique) - %s columns validated', array_length(safe_bloom, 1));
    RETURN NEXT;

    -- Return minmax config
    config_type := 'minmax_columns';
    column_list := array_to_string(candidate_minmax_columns, ',');
    reason := format('All filterable columns - %s columns', array_length(candidate_minmax_columns, 1));
    RETURN NEXT;

    -- Return cluster config
    config_type := 'cluster_columns';
    column_list := array_to_string(cluster_columns, ',');
    reason := format('Z-order clustering dimensions - %s columns', array_length(cluster_columns, 1));
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ generate_pax_config() created'
\echo ''

\echo '===================================================='
\echo 'Validation framework ready!'
\echo '===================================================='
\echo ''
\echo 'Available functions:'
\echo '  1. ecommerce_validation.validate_bloom_candidates(schema, table, columns[])'
\echo '  2. ecommerce_validation.calculate_cluster_memory(schema, table)'
\echo '  3. ecommerce_validation.detect_storage_bloat(schema, baseline, pax_nc, pax_c)'
\echo '  4. ecommerce_validation.generate_pax_config(schema, table, bloom[], minmax[], cluster[])'
\echo ''
\echo 'Next: Phase 1 - Setup schema'
\echo ''
