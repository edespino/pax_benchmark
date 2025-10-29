--
-- Phase 2: Analyze Cardinality (CRITICAL VALIDATION STEP)
-- Run BEFORE creating PAX tables to validate bloom filter candidates
-- This step prevents the 81% storage bloat discovered in October 2025
--

\timing on

\echo '===================================================='
\echo 'IoT Benchmark - Phase 2: Cardinality Analysis'
\echo '===================================================='
\echo ''
\echo '⚠️  CRITICAL: This validates bloom filter candidates'
\echo '⚠️  BEFORE table creation to prevent storage bloat'
\echo ''

-- =====================================================
-- Create Sample Table for Analysis
-- Use 1M row sample to get accurate statistics
-- =====================================================

\echo 'Step 1: Creating sample table for analysis...'
\echo '  (This will be dropped after analysis)'
\echo ''

DROP TABLE IF EXISTS iot.readings_sample CASCADE;

CREATE TEMP TABLE readings_sample AS
SELECT
    -- Time dimension
    timestamp '2025-10-01 00:00:00' + (gs * interval '15 seconds') AS reading_time,
    (timestamp '2025-10-01 00:00:00' + (gs * interval '15 seconds'))::DATE AS reading_date,

    -- Device/sensor identifiers (HIGH CARDINALITY)
    'device-' || lpad((1 + (random() * 99999)::INT)::TEXT, 6, '0') AS device_id,

    -- Sensor type (LOW CARDINALITY - 100 values)
    CASE
        WHEN random() < 0.8 THEN 1 + (random() * 19)::INT  -- 80% from top 20
        ELSE 20 + (random() * 79)::INT
    END AS sensor_type_id,

    -- Measurements
    (22.0 + (random() - 0.5) * 10)::NUMERIC(5,2) AS temperature,
    (60.0 + (random() - 0.5) * 40)::NUMERIC(5,2) AS humidity,
    (1013.25 + (random() - 0.5) * 50)::NUMERIC(7,2) AS pressure,
    (100.0 - (gs / 1000000.0) * 30 + (random() - 0.5) * 5)::NUMERIC(5,2) AS battery_level,

    -- Status (VERY LOW CARDINALITY - 3 values)
    CASE
        WHEN random() < 0.95 THEN 'ok'
        WHEN random() < 0.98 THEN 'warning'
        ELSE 'error'
    END AS status,

    -- Alerts (BINARY)
    (random() < 0.05) AS alert_triggered,

    -- Location (MEDIUM CARDINALITY - ~1000 values)
    'building-' || chr(65 + (random() * 25)::INT) ||
    '-floor-' || (1 + (random() * 10)::INT) ||
    '-room-' || lpad((1 + (random() * 100)::INT)::TEXT, 3, '0') AS location,

    -- Firmware (VERY LOW CARDINALITY - 10 values)
    'v' || (1 + (random() * 9)::INT) || '.0' AS firmware_version,

    -- Metadata
    gs AS sequence_number,
    md5(gs::TEXT || random()::TEXT) AS checksum
FROM generate_series(1, 1000000) gs;

\echo '  ✓ Sample table created (1M rows)'
\echo ''

-- =====================================================
-- Step 2: ANALYZE to Collect Statistics
-- =====================================================

\echo 'Step 2: Running ANALYZE to collect statistics...'

ANALYZE readings_sample;

\echo '  ✓ Statistics collected'
\echo ''

-- =====================================================
-- Step 3: Validate ALL Proposed Bloom Filter Columns
-- =====================================================

\echo '===================================================='
\echo 'BLOOM FILTER CANDIDATE VALIDATION'
\echo '===================================================='
\echo ''
\echo 'Proposed bloom filter columns for validation:'
\echo '  - device_id (expected: HIGH cardinality - ~100K unique)'
\echo '  - location (expected: MEDIUM cardinality - ~1K unique)'
\echo '  - sensor_type_id (expected: LOW cardinality - ~100 unique)'
\echo '  - status (expected: VERY LOW cardinality - 3 unique)'
\echo ''
\echo 'Validation results:'
\echo ''

SELECT * FROM iot_validation.validate_bloom_candidates(
    'pg_temp',
    'readings_sample',
    ARRAY['device_id', 'location', 'sensor_type_id', 'status', 'firmware_version', 'checksum']
);

\echo ''
\echo '===================================================='
\echo ''

-- =====================================================
-- Step 4: Cardinality Summary for All Columns
-- =====================================================

\echo 'Cardinality summary for ALL columns:'
\echo ''

SELECT
    attname AS column_name,
    n_distinct,
    CASE
        WHEN n_distinct >= 0 THEN n_distinct::BIGINT
        ELSE (1000000 * ABS(n_distinct))::BIGINT
    END AS estimated_unique_values,
    CASE
        WHEN ABS(n_distinct) >= 1000 THEN '✅ Bloom filter recommended'
        WHEN ABS(n_distinct) >= 100 THEN '🟠 Borderline for bloom'
        WHEN ABS(n_distinct) >= 10 THEN '📊 MinMax only'
        ELSE '❌ Skip (too low)'
    END AS recommendation,
    null_frac AS null_fraction,
    avg_width AS avg_bytes
FROM pg_stats
WHERE schemaname = 'pg_temp'
  AND tablename = 'readings_sample'
ORDER BY ABS(n_distinct) DESC;

\echo ''

-- =====================================================
-- Step 5: Memory Requirements Calculation
-- =====================================================

\echo '===================================================='
\echo 'MEMORY REQUIREMENTS FOR CLUSTERING'
\echo '===================================================='
\echo ''
\echo 'Target table size: 10,000,000 rows'
\echo ''

SELECT * FROM iot_validation.calculate_cluster_memory(10000000);

\echo ''

-- =====================================================
-- Step 6: Expected Configuration Summary
-- =====================================================

\echo '===================================================='
\echo 'EXPECTED CONFIGURATION SUMMARY'
\echo '===================================================='
\echo ''
\echo 'Based on cardinality analysis:'
\echo ''
\echo 'SAFE for bloom filters (cardinality >= 1000):'
\echo '  ✅ device_id (~100,000 unique)'
\echo '  ✅ checksum (~1,000,000 unique)'
\echo ''
\echo 'BORDERLINE (cardinality 100-1000):'
\echo '  🟠 location (~1,000 unique) - Consider testing'
\echo ''
\echo 'UNSAFE for bloom filters (cardinality < 100):'
\echo '  ❌ sensor_type_id (~100 unique) - Use minmax only'
\echo '  ❌ firmware_version (~10 unique) - Skip'
\echo '  ❌ status (~3 unique) - Skip'
\echo ''
\echo 'RECOMMENDED PAX CONFIGURATION:'
\echo '  bloomfilter_columns=''device_id,checksum'''
\echo '  minmax_columns=''reading_date,device_id,sensor_type_id,temperature,pressure,location'''
\echo '  maintenance_work_mem: See calculation above'
\echo ''

-- =====================================================
-- Cleanup
-- =====================================================

DROP TABLE IF EXISTS readings_sample;

\echo '===================================================='
\echo 'Cardinality analysis complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 3 - Generate safe PAX configuration'
