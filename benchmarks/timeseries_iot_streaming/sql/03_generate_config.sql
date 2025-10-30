--
-- Phase 3: Generate Safe PAX Configuration
-- Auto-generates configuration from cardinality analysis
-- Prevents manual configuration errors
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 3: Generate PAX Config'
\echo '===================================================='
\echo ''

-- =====================================================
-- Create Sample Table for Config Generation
-- =====================================================

\echo 'Creating temporary sample for config generation...'

CREATE TEMP TABLE cdr_config_sample AS
SELECT
    'call-000000000001-abc123' AS call_id,
    timestamp '2025-10-01 00:00:00' AS call_timestamp,
    '+1-0000000001' AS caller_number,
    '+1-0000000001' AS callee_number,
    120 AS duration_seconds,
    1 AS cell_tower_id,
    'voice' AS call_type,
    '5G' AS network_type,
    NULL::BIGINT AS bytes_transferred,
    1 AS termination_code,
    12.00 AS billing_amount,
    1 AS rate_plan_id,
    FALSE AS is_roaming
FROM generate_series(1, 100000) gs
LIMIT 100000;

ANALYZE cdr_config_sample;

\echo '  ✓ Sample created'
\echo ''

-- =====================================================
-- Generate Configuration
-- =====================================================

\echo 'Generating safe PAX configuration...'
\echo ''
\echo '===================================================='

SELECT cdr_validation.generate_pax_config(
    'cdr',                               -- Schema name
    'cdr_config_sample',                 -- Sample table (from temp)
    50000000,                            -- Target: 50M rows for streaming test
    'call_timestamp,cell_tower_id'       -- Cluster on time + location
);

\echo '===================================================='
\echo ''

-- =====================================================
-- Cleanup
-- =====================================================

DROP TABLE IF EXISTS cdr_config_sample;

\echo 'Configuration generation complete!'
\echo ''
\echo 'Copy the configuration above to 04_create_variants.sql'
\echo ''
\echo 'Next: Phase 4 - Create table variants (AO/AOCO/PAX/PAX-no-cluster)'
