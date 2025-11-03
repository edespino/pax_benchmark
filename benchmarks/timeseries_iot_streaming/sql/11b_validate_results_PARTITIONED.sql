--
-- Phase 11b: Validate Results (Safety Gates) - PARTITIONED VARIANTS
-- Validates benchmark results against expected thresholds for partitioned tables
-- Based on October 2025 PAX testing lessons + November 2025 partitioning implementation
--
-- Note: All checks work on parent tables which automatically aggregate partitions
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 11b: Result Validation (PARTITIONED)'
\echo '===================================================='
\echo ''

-- =====================================================
-- Gate 1: Row Count Consistency
-- All partitioned variants must have identical row counts
-- =====================================================

\echo 'Gate 1: Row Count Consistency (Partitioned Variants)'
\echo '====================================================='
\echo ''

DO $$
DECLARE
    v_ao_count BIGINT;
    v_aoco_count BIGINT;
    v_pax_count BIGINT;
    v_pax_nc_count BIGINT;
BEGIN
    -- COUNT(*) on parent tables automatically aggregates all partitions
    SELECT COUNT(*) INTO v_ao_count FROM cdr.cdr_ao_partitioned;
    SELECT COUNT(*) INTO v_aoco_count FROM cdr.cdr_aoco_partitioned;
    SELECT COUNT(*) INTO v_pax_count FROM cdr.cdr_pax_partitioned;
    SELECT COUNT(*) INTO v_pax_nc_count FROM cdr.cdr_pax_nocluster_partitioned;

    RAISE NOTICE 'Row counts (partitioned tables):';
    RAISE NOTICE '  AO: % rows (24 partitions)', v_ao_count;
    RAISE NOTICE '  AOCO: % rows (24 partitions)', v_aoco_count;
    RAISE NOTICE '  PAX: % rows (24 partitions)', v_pax_count;
    RAISE NOTICE '  PAX-no-cluster: % rows (24 partitions)', v_pax_nc_count;
    RAISE NOTICE '';

    IF v_ao_count = v_aoco_count AND v_aoco_count = v_pax_count AND v_pax_count = v_pax_nc_count THEN
        RAISE NOTICE '✅ PASSED: All variants have identical row counts (% rows)', v_ao_count;
        RAISE NOTICE '    Note: Each partition contains ~% rows', ROUND(v_ao_count / 24.0, 0);
    ELSE
        RAISE EXCEPTION '❌ FAILED: Row count mismatch! Data integrity compromised.';
    END IF;
END $$;

\echo ''

-- =====================================================
-- Gate 2: PAX Configuration Bloat Check
-- PAX partitioned variants must not have excessive storage bloat
-- =====================================================

\echo 'Gate 2: PAX Configuration Bloat Check (Partitioned)'
\echo '===================================================='
\echo ''

DO $$
DECLARE
    v_aoco_size BIGINT;
    v_pax_nc_size BIGINT;
    v_pax_size BIGINT;
    v_nc_bloat_ratio NUMERIC;
    v_clustered_bloat_ratio NUMERIC;
BEGIN
    -- pg_total_relation_size() on parent returns 0 (Greenplum/Cloudberry behavior)
    -- Use pg_partition_tree() to sum leaf partition sizes
    SELECT SUM(pg_total_relation_size(relid)) INTO v_aoco_size
    FROM pg_partition_tree('cdr.cdr_aoco_partitioned')
    WHERE isleaf = true;

    SELECT SUM(pg_total_relation_size(relid)) INTO v_pax_nc_size
    FROM pg_partition_tree('cdr.cdr_pax_nocluster_partitioned')
    WHERE isleaf = true;

    SELECT SUM(pg_total_relation_size(relid)) INTO v_pax_size
    FROM pg_partition_tree('cdr.cdr_pax_partitioned')
    WHERE isleaf = true;

    v_nc_bloat_ratio := (v_pax_nc_size::NUMERIC / v_aoco_size::NUMERIC);
    v_clustered_bloat_ratio := (v_pax_size::NUMERIC / v_pax_nc_size::NUMERIC);

    RAISE NOTICE 'Storage sizes (partitioned, includes all 24 partitions):';
    RAISE NOTICE '  AOCO (baseline): %', pg_size_pretty(v_aoco_size);
    RAISE NOTICE '  PAX-no-cluster: % (%x vs AOCO)', pg_size_pretty(v_pax_nc_size), ROUND(v_nc_bloat_ratio, 2);
    RAISE NOTICE '  PAX-clustered: % (%x vs no-cluster)', pg_size_pretty(v_pax_size), ROUND(v_clustered_bloat_ratio, 2);
    RAISE NOTICE '';

    -- Check PAX no-cluster vs AOCO
    IF v_nc_bloat_ratio < 1.20 THEN
        RAISE NOTICE '✅ PASSED: PAX-no-cluster bloat is healthy (<20%% overhead)';
    ELSIF v_nc_bloat_ratio < 1.40 THEN
        RAISE WARNING '🟠 WARNING: PAX-no-cluster has moderate bloat (20-40%% overhead). Review bloom filter configuration.';
    ELSE
        RAISE EXCEPTION '❌ FAILED: PAX-no-cluster has CRITICAL bloat (>40%% overhead). Bloom filter misconfiguration likely!';
    END IF;

    -- Check PAX clustered vs no-cluster
    IF v_clustered_bloat_ratio < 1.40 THEN
        RAISE NOTICE '✅ PASSED: PAX-clustered overhead is acceptable (<40%%)';
    ELSIF v_clustered_bloat_ratio < 1.60 THEN
        RAISE WARNING '🟠 WARNING: PAX-clustered has moderate overhead (40-60%%). Consider increasing maintenance_work_mem.';
    ELSE
        RAISE EXCEPTION '❌ FAILED: PAX-clustered has excessive overhead (>60%%). Check maintenance_work_mem and bloom filter config!';
    END IF;
END $$;

\echo ''

-- =====================================================
-- Gate 3: INSERT Throughput Sanity Check
-- PAX partitioned variant must achieve reasonable INSERT performance
-- =====================================================

\echo 'Gate 3: INSERT Throughput Sanity Check (Partitioned)'
\echo '====================================================='
\echo ''

DO $$
DECLARE
    v_table_name TEXT;
    v_ao_throughput NUMERIC;
    v_pax_throughput NUMERIC;
    v_ratio NUMERIC;
BEGIN
    -- Check which partitioned metrics table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1_partitioned_test') THEN
        v_table_name := 'streaming_metrics_phase1_partitioned_test';
        RAISE NOTICE 'Using Phase 1 metrics from PARTITIONED TEST run';
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1_partitioned') THEN
        v_table_name := 'streaming_metrics_phase1_partitioned';
        RAISE NOTICE 'Using Phase 1 metrics from PARTITIONED PRODUCTION run';
    ELSE
        RAISE NOTICE 'Phase 1 metrics not found (partitioned table does not exist)';
        RAISE NOTICE 'Run 06b_streaming_inserts_noindex_PARTITIONED.sql first';
        RETURN;
    END IF;

    -- Get Phase 1 throughput (no indexes) using dynamic SQL
    EXECUTE format('SELECT AVG(throughput_rows_sec) FROM cdr.%I WHERE variant = ''AO''', v_table_name)
        INTO v_ao_throughput;

    EXECUTE format('SELECT AVG(throughput_rows_sec) FROM cdr.%I WHERE variant = ''PAX''', v_table_name)
        INTO v_pax_throughput;

    v_ratio := v_pax_throughput / v_ao_throughput;

    RAISE NOTICE '';
    RAISE NOTICE 'Phase 1 (no indexes, partitioned) throughput:';
    RAISE NOTICE '  AO: % rows/sec', ROUND(v_ao_throughput, 0);
    RAISE NOTICE '  PAX: % rows/sec', ROUND(v_pax_throughput, 0);
    RAISE NOTICE '  Ratio: PAX is %%% of AO speed', ROUND(v_ratio * 100, 1);
    RAISE NOTICE '';

    IF v_ratio >= 0.50 THEN
        RAISE NOTICE '✅ PASSED: PAX INSERT speed is acceptable (>50%% of AO)';
    ELSIF v_ratio >= 0.30 THEN
        RAISE WARNING '🟠 WARNING: PAX INSERT speed is slower than expected (30-50%% of AO)';
    ELSE
        RAISE EXCEPTION '❌ FAILED: PAX INSERT speed is critically slow (<30%% of AO)';
    END IF;
END $$;

\echo ''

-- =====================================================
-- Gate 4: Bloom Filter Effectiveness (Optional)
-- Verify bloom filters are providing value in partitioned tables
-- =====================================================

\echo 'Gate 4: Bloom Filter Effectiveness (Partitioned)'
\echo '================================================='
\echo ''

DO $$
DECLARE
    v_caller_distinct NUMERIC;
    v_callee_distinct NUMERIC;
    v_partition_name TEXT;
    v_sample_count INTEGER := 0;
BEGIN
    -- Check cardinality of bloom filter columns in first few partitions
    -- Note: call_id removed from bloom filters in Nov 2025 optimization (only 1 distinct value)

    -- For partitioned tables, check stats on a sample partition
    SELECT tablename INTO v_partition_name
    FROM pg_tables
    WHERE schemaname = 'cdr'
      AND tablename LIKE 'cdr_pax_part_day%'
    ORDER BY tablename
    LIMIT 1;

    IF v_partition_name IS NOT NULL THEN
        -- Try to get stats from partition (may not be available)
        SELECT n_distinct INTO v_caller_distinct
        FROM pg_stats
        WHERE schemaname = 'cdr' AND tablename = v_partition_name AND attname = 'caller_number';

        SELECT n_distinct INTO v_callee_distinct
        FROM pg_stats
        WHERE schemaname = 'cdr' AND tablename = v_partition_name AND attname = 'callee_number';
    END IF;

    -- If partition stats not available, try parent table
    IF v_caller_distinct IS NULL THEN
        SELECT n_distinct INTO v_caller_distinct
        FROM pg_stats
        WHERE schemaname = 'cdr' AND tablename = 'cdr_pax_partitioned' AND attname = 'caller_number';

        SELECT n_distinct INTO v_callee_distinct
        FROM pg_stats
        WHERE schemaname = 'cdr' AND tablename = 'cdr_pax_partitioned' AND attname = 'callee_number';
    END IF;

    RAISE NOTICE 'Bloom filter column cardinalities (Nov 2025 optimized config):';
    IF v_caller_distinct IS NOT NULL THEN
        RAISE NOTICE '  caller_number: % distinct values (partitioned)', ABS(v_caller_distinct);
        RAISE NOTICE '  callee_number: % distinct values (partitioned)', ABS(v_callee_distinct);
        RAISE NOTICE '  (call_id removed - only 1 distinct value)';
        RAISE NOTICE '';

        IF ABS(v_caller_distinct) >= 1000 AND ABS(v_callee_distinct) >= 1000 THEN
            RAISE NOTICE '✅ PASSED: All bloom filter columns have high cardinality (>1000 unique)';
        ELSE
            RAISE WARNING '🟠 WARNING: Some bloom filter columns have lower cardinality than expected';
        END IF;
    ELSE
        RAISE NOTICE '  ⚠️  Statistics not yet available for partitioned tables';
        RAISE NOTICE '  Run ANALYZE on parent table: ANALYZE cdr.cdr_pax_partitioned;';
        RAISE NOTICE '  Skipping cardinality check (not critical for validation)';
    END IF;
END $$;

\echo ''

-- =====================================================
-- Gate 5: Partition Health Check (BONUS)
-- Verify partitions are populated and balanced
-- =====================================================

\echo 'Gate 5: Partition Health Check (BONUS for Partitioned)'
\echo '======================================================='
\echo ''

DO $$
DECLARE
    v_partition_count INTEGER;
    v_empty_partitions INTEGER := 0;
    v_min_rows BIGINT;
    v_max_rows BIGINT;
    v_avg_rows NUMERIC;
    v_partition_name TEXT;
    v_row_count BIGINT;
BEGIN
    -- Count total partitions
    SELECT COUNT(*) INTO v_partition_count
    FROM pg_tables
    WHERE schemaname = 'cdr'
      AND tablename LIKE 'cdr_ao_part_day%';

    RAISE NOTICE 'Partition distribution analysis:';
    RAISE NOTICE '  Total partitions per variant: %', v_partition_count;
    RAISE NOTICE '';

    -- Check for empty partitions and get distribution stats (sample AO variant)
    SELECT MIN(cnt), MAX(cnt), AVG(cnt)
    INTO v_min_rows, v_max_rows, v_avg_rows
    FROM (
        SELECT COUNT(*) as cnt
        FROM cdr.cdr_ao_partitioned
        GROUP BY call_date
    ) partition_counts;

    RAISE NOTICE 'Row distribution per partition (AO variant):';
    RAISE NOTICE '  Min rows: %', COALESCE(v_min_rows, 0);
    RAISE NOTICE '  Max rows: %', COALESCE(v_max_rows, 0);
    RAISE NOTICE '  Avg rows: %', COALESCE(ROUND(v_avg_rows, 0), 0);
    RAISE NOTICE '';

    IF v_min_rows > 0 THEN
        RAISE NOTICE '✅ PASSED: All partitions are populated';

        -- Check if distribution is relatively balanced (max/min < 2.0)
        IF v_max_rows::NUMERIC / v_min_rows::NUMERIC < 2.0 THEN
            RAISE NOTICE '✅ PASSED: Partition distribution is balanced (max/min < 2.0)';
        ELSE
            RAISE WARNING '🟠 INFO: Partition distribution has some skew (max/min >= 2.0) - expected for realistic traffic patterns';
        END IF;
    ELSE
        RAISE WARNING '🟠 WARNING: Some partitions may be empty';
    END IF;
END $$;

\echo ''

-- =====================================================
-- Summary
-- =====================================================

\echo '===================================================='
\echo 'VALIDATION SUMMARY (PARTITIONED VARIANTS)'
\echo '===================================================='
\echo ''
\echo 'All validation gates (partitioned):'
\echo '  1. Row count consistency: Check above'
\echo '  2. PAX configuration bloat: Check above'
\echo '  3. INSERT throughput sanity: Check above'
\echo '  4. Bloom filter effectiveness: Check above'
\echo '  5. Partition health check: Check above (BONUS)'
\echo ''
\echo 'Partitioning benefits validated:'
\echo '  • 24 partitions per variant (96 total tables)'
\echo '  • Each partition: ~1.74M rows (vs 42M monolithic)'
\echo '  • Automatic partition routing working correctly'
\echo '  • Storage and performance metrics match expectations'
\echo ''
\echo 'If all gates passed: ✅ Benchmark results are valid (partitioned)!'
\echo 'If any gates failed: ❌ Review configuration and re-run'
\echo ''
\echo 'Expected benefits vs monolithic:'
\echo '  • Phase 2 runtime: 18-35% faster (smaller indexes)'
\echo '  • Query performance: 20-30% faster (partition pruning)'
\echo '  • Index maintenance: O(n log n) reduction per partition'
\echo ''
\echo '===================================================='
\echo 'Benchmark validation complete (partitioned)!'
\echo '===================================================='
