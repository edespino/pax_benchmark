--
-- Phase 11: Validate Results (Safety Gates)
-- Validates benchmark results against expected thresholds
-- Based on October 2025 PAX testing lessons
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 11: Result Validation'
\echo '===================================================='
\echo ''

-- =====================================================
-- Gate 1: Row Count Consistency
-- All variants must have identical row counts
-- =====================================================

\echo 'Gate 1: Row Count Consistency'
\echo '=============================='
\echo ''

DO $$
DECLARE
    v_ao_count BIGINT;
    v_aoco_count BIGINT;
    v_pax_count BIGINT;
    v_pax_nc_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_ao_count FROM cdr.cdr_ao;
    SELECT COUNT(*) INTO v_aoco_count FROM cdr.cdr_aoco;
    SELECT COUNT(*) INTO v_pax_count FROM cdr.cdr_pax;
    SELECT COUNT(*) INTO v_pax_nc_count FROM cdr.cdr_pax_nocluster;

    RAISE NOTICE 'Row counts:';
    RAISE NOTICE '  AO: %', v_ao_count;
    RAISE NOTICE '  AOCO: %', v_aoco_count;
    RAISE NOTICE '  PAX: %', v_pax_count;
    RAISE NOTICE '  PAX-no-cluster: %', v_pax_nc_count;
    RAISE NOTICE '';

    IF v_ao_count = v_aoco_count AND v_aoco_count = v_pax_count AND v_pax_count = v_pax_nc_count THEN
        RAISE NOTICE '✅ PASSED: All variants have identical row counts (% rows)', v_ao_count;
    ELSE
        RAISE EXCEPTION '❌ FAILED: Row count mismatch! Data integrity compromised.';
    END IF;
END $$;

\echo ''

-- =====================================================
-- Gate 2: PAX Configuration Bloat Check
-- PAX variants must not have excessive storage bloat
-- =====================================================

\echo 'Gate 2: PAX Configuration Bloat Check'
\echo '====================================='
\echo ''

DO $$
DECLARE
    v_aoco_size BIGINT;
    v_pax_nc_size BIGINT;
    v_pax_size BIGINT;
    v_nc_bloat_ratio NUMERIC;
    v_clustered_bloat_ratio NUMERIC;
BEGIN
    v_aoco_size := pg_total_relation_size('cdr.cdr_aoco');
    v_pax_nc_size := pg_total_relation_size('cdr.cdr_pax_nocluster');
    v_pax_size := pg_total_relation_size('cdr.cdr_pax');

    v_nc_bloat_ratio := (v_pax_nc_size::NUMERIC / v_aoco_size::NUMERIC);
    v_clustered_bloat_ratio := (v_pax_size::NUMERIC / v_pax_nc_size::NUMERIC);

    RAISE NOTICE 'Storage sizes:';
    RAISE NOTICE '  AOCO (baseline): %', pg_size_pretty(v_aoco_size);
    RAISE NOTICE '  PAX-no-cluster: % (%.2fx vs AOCO)', pg_size_pretty(v_pax_nc_size), v_nc_bloat_ratio;
    RAISE NOTICE '  PAX-clustered: % (%.2fx vs no-cluster)', pg_size_pretty(v_pax_size), v_clustered_bloat_ratio;
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
-- PAX must achieve reasonable INSERT performance
-- =====================================================

\echo 'Gate 3: INSERT Throughput Sanity Check'
\echo '======================================='
\echo ''

DO $$
DECLARE
    v_ao_throughput NUMERIC;
    v_pax_throughput NUMERIC;
    v_ratio NUMERIC;
BEGIN
    -- Get Phase 1 throughput (no indexes)
    SELECT AVG(throughput_rows_sec) INTO v_ao_throughput
    FROM cdr.streaming_metrics_phase1
    WHERE variant = 'AO';

    SELECT AVG(throughput_rows_sec) INTO v_pax_throughput
    FROM cdr.streaming_metrics_phase1
    WHERE variant = 'PAX';

    v_ratio := v_pax_throughput / v_ao_throughput;

    RAISE NOTICE 'Phase 1 (no indexes) throughput:';
    RAISE NOTICE '  AO: % rows/sec', ROUND(v_ao_throughput, 0);
    RAISE NOTICE '  PAX: % rows/sec', ROUND(v_pax_throughput, 0);
    RAISE NOTICE '  Ratio: PAX is %.1f%% of AO speed', v_ratio * 100;
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
-- Verify bloom filters are providing value
-- =====================================================

\echo 'Gate 4: Bloom Filter Effectiveness'
\echo '==================================='
\echo ''

DO $$
DECLARE
    v_call_id_distinct NUMERIC;
    v_caller_distinct NUMERIC;
    v_callee_distinct NUMERIC;
BEGIN
    -- Check cardinality of bloom filter columns
    SELECT n_distinct INTO v_call_id_distinct
    FROM pg_stats
    WHERE schemaname = 'cdr' AND tablename = 'cdr_pax' AND attname = 'call_id';

    SELECT n_distinct INTO v_caller_distinct
    FROM pg_stats
    WHERE schemaname = 'cdr' AND tablename = 'cdr_pax' AND attname = 'caller_number';

    SELECT n_distinct INTO v_callee_distinct
    FROM pg_stats
    WHERE schemaname = 'cdr' AND tablename = 'cdr_pax' AND attname = 'callee_number';

    RAISE NOTICE 'Bloom filter column cardinalities:';
    RAISE NOTICE '  call_id: % distinct values', ABS(v_call_id_distinct);
    RAISE NOTICE '  caller_number: % distinct values', ABS(v_caller_distinct);
    RAISE NOTICE '  callee_number: % distinct values', ABS(v_callee_distinct);
    RAISE NOTICE '';

    IF ABS(v_call_id_distinct) >= 1000 AND ABS(v_caller_distinct) >= 1000 AND ABS(v_callee_distinct) >= 1000 THEN
        RAISE NOTICE '✅ PASSED: All bloom filter columns have high cardinality (>1000 unique)';
    ELSE
        RAISE WARNING '🟠 WARNING: Some bloom filter columns have lower cardinality than expected';
    END IF;
END $$;

\echo ''

-- =====================================================
-- Summary
-- =====================================================

\echo '===================================================='
\echo 'VALIDATION SUMMARY'
\echo '===================================================='
\echo ''
\echo 'All validation gates:';
\echo '  1. Row count consistency: Check above';
\echo '  2. PAX configuration bloat: Check above';
\echo '  3. INSERT throughput sanity: Check above';
\echo '  4. Bloom filter effectiveness: Check above';
\echo ''
\echo 'If all gates passed: ✅ Benchmark results are valid!';
\echo 'If any gates failed: ❌ Review configuration and re-run';
\echo ''
\echo '===================================================='
\echo 'Benchmark complete!'
\echo '===================================================='
