--
-- Phase 6: Post-Creation Validation
-- SAFETY GATE #3: Detects storage bloat after table creation
-- Must pass BEFORE Z-order clustering
--

\timing on

\echo '===================================================='
\echo 'Financial Trading - Phase 6: Configuration Validation'
\echo '===================================================='
\echo ''
\echo 'SAFETY GATE #3: Post-creation bloat detection'
\echo ''

-- =====================================================
-- Compare PAX vs AOCO (Baseline)
-- =====================================================

\echo 'Comparing PAX (no-cluster) vs AOCO baseline...'
\echo ''

SELECT * FROM trading_validation.detect_storage_bloat(
    'trading',
    'tick_data_aoco',           -- Baseline
    'tick_data_pax_nocluster'   -- Test
);

\echo ''

-- =====================================================
-- Detailed Size Breakdown
-- =====================================================

\echo 'Storage breakdown by variant:'
\echo ''

SELECT
    CASE tablename
        WHEN 'tick_data_ao' THEN '1. AO'
        WHEN 'tick_data_aoco' THEN '2. AOCO'
        WHEN 'tick_data_pax_nocluster' THEN '3. PAX (no-cluster)'
        WHEN 'tick_data_pax' THEN '4. PAX (clustered)'
    END AS variant,
    pg_size_pretty(pg_relation_size('trading.' || tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size('trading.' || tablename) - pg_relation_size('trading.' || tablename)) AS indexes_toast,
    pg_size_pretty(pg_total_relation_size('trading.' || tablename)) AS total_size,
    ROUND(pg_total_relation_size('trading.' || tablename)::NUMERIC / 1024 / 1024, 2) AS size_mb
FROM pg_tables
WHERE schemaname = 'trading'
  AND tablename LIKE 'tick_data_%'
ORDER BY pg_total_relation_size('trading.' || tablename);

\echo ''

-- =====================================================
-- Validation Check
-- =====================================================

DO $$
DECLARE
    v_aoco_size BIGINT;
    v_pax_size BIGINT;
    v_bloat_ratio NUMERIC;
BEGIN
    SELECT pg_total_relation_size('trading.tick_data_aoco') INTO v_aoco_size;
    SELECT pg_total_relation_size('trading.tick_data_pax_nocluster') INTO v_pax_size;

    v_bloat_ratio := v_pax_size::NUMERIC / v_aoco_size::NUMERIC;

    RAISE NOTICE '';
    RAISE NOTICE 'Validation Results:';
    RAISE NOTICE '  AOCO size:  % MB', ROUND(v_aoco_size::NUMERIC / 1024 / 1024, 2);
    RAISE NOTICE '  PAX size:   % MB', ROUND(v_pax_size::NUMERIC / 1024 / 1024, 2);
    RAISE NOTICE '  Bloat ratio: %.2fx', v_bloat_ratio;
    RAISE NOTICE '';

    IF v_bloat_ratio < 1.1 THEN
        RAISE NOTICE '✅ EXCELLENT: PAX overhead < 10%% (%.1f%%)', (v_bloat_ratio - 1) * 100;
        RAISE NOTICE '   Configuration is optimal.';
    ELSIF v_bloat_ratio < 1.3 THEN
        RAISE NOTICE '✅ HEALTHY: PAX overhead < 30%% (%.1f%%)', (v_bloat_ratio - 1) * 100;
        RAISE NOTICE '   Configuration is acceptable.';
    ELSIF v_bloat_ratio < 1.5 THEN
        RAISE NOTICE '🟠 ACCEPTABLE: PAX overhead %.1f%%', (v_bloat_ratio - 1) * 100;
        RAISE NOTICE '   Review bloom filter configuration.';
    ELSE
        RAISE EXCEPTION '❌ CRITICAL BLOAT DETECTED (%.1f%% overhead)!', (v_bloat_ratio - 1) * 100;
    END IF;
END $$;

\echo ''
\echo '===================================================='
\echo 'Phase 6 complete!'
\echo '===================================================='
\echo ''
\echo 'Configuration validation passed!'
\echo 'Next: Phase 7 - Z-order clustering optimization'
