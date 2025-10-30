--
-- Phase 3: Generate Safe PAX Configuration
-- Auto-generates configuration from cardinality analysis
-- Prevents manual configuration errors
--

\timing on

\echo '===================================================='
\echo 'IoT Benchmark - Phase 3: Generate Safe Configuration'
\echo '===================================================='
\echo ''

-- Note: This requires cardinality analysis to have been run first
-- (sql/02_analyze_cardinality.sql)

\echo 'Generating auto-validated PAX configuration...'
\echo ''

-- Re-create sample table for config generation
-- (In real usage, this would be your actual source data)
CREATE TEMP TABLE readings_sample AS
SELECT
    timestamp '2025-10-01 00:00:00' + (gs * interval '15 seconds') AS reading_time,
    (timestamp '2025-10-01 00:00:00' + (gs * interval '15 seconds'))::DATE AS reading_date,
    'device-' || lpad((1 + (random() * 99999)::INT)::TEXT, 6, '0') AS device_id,
    CASE WHEN random() < 0.8 THEN 1 + (random() * 19)::INT ELSE 20 + (random() * 79)::INT END AS sensor_type_id,
    (22.0 + (random() - 0.5) * 10)::NUMERIC(5,2) AS temperature,
    (60.0 + (random() - 0.5) * 40)::NUMERIC(5,2) AS humidity,
    (1013.25 + (random() - 0.5) * 50)::NUMERIC(7,2) AS pressure,
    (100.0 - (gs / 1000000.0) * 30 + (random() - 0.5) * 5)::NUMERIC(5,2) AS battery_level,
    CASE WHEN random() < 0.95 THEN 'ok' WHEN random() < 0.98 THEN 'warning' ELSE 'error' END AS status,
    (random() < 0.05) AS alert_triggered,
    'building-' || chr(65 + (random() * 25)::INT) || '-floor-' || (1 + (random() * 10)::INT) AS location,
    'v' || (1 + (random() * 9)::INT) || '.0' AS firmware_version,
    gs AS sequence_number,
    md5(gs::TEXT || random()::TEXT) AS checksum
FROM generate_series(1, 100000) gs;

ANALYZE readings_sample;

\echo '  ✓ Sample data created for configuration generation'
\echo ''

-- =====================================================
-- Generate Configuration
-- =====================================================

\echo '===================================================='
\echo 'AUTO-GENERATED PAX CONFIGURATION'
\echo '===================================================='
\echo ''

SELECT iot_validation.generate_pax_config(
    'pg_temp',              -- Schema containing sample table
    'readings_sample',      -- Sample table name
    10000000,               -- Target rows for production table
    'reading_date,device_id'  -- Z-order clustering columns (DATE + VARCHAR supported)
);

\echo ''
\echo '===================================================='
\echo ''

-- =====================================================
-- Validation Summary
-- =====================================================

\echo 'Configuration generation complete!'
\echo ''
\echo 'The auto-generated configuration above:'
\echo '  ✅ Only includes bloom filters on high-cardinality columns (>=1000 unique)'
\echo '  ✅ Includes minmax statistics on filterable columns (>=10 unique)'
\echo '  ✅ Calculates correct maintenance_work_mem for 10M rows'
\echo '  ✅ Prevents the 81% storage bloat from low-cardinality bloom filters'
\echo ''
\echo 'Copy the configuration above to create your PAX tables safely.'
\echo ''
\echo 'Next: Phase 4 - Create storage variants with validated configuration'

-- Cleanup
DROP TABLE IF EXISTS readings_sample;
