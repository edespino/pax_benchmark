--
-- Phase 5: Generate Time-Series Data
-- Populates all 4 variants with identical 10M rows
-- Realistic IoT sensor readings with time-series characteristics
--

\timing on

\echo '===================================================='
\echo 'IoT Benchmark - Phase 5: Generate Time-Series Data'
\echo '===================================================='
\echo ''
\echo 'Generating 10,000,000 sensor readings...'
\echo '  (This will take 2-3 minutes)'
\echo ''

-- =====================================================
-- Insert Data into All 4 Variants
-- Using INSERT INTO ... SELECT for efficiency
-- =====================================================

\echo 'Step 1/4: Populating AO variant...'

INSERT INTO iot.readings_ao
SELECT
    -- Time dimension (30 days of data, 15-second intervals)
    timestamp '2025-10-01 00:00:00' + (gs * interval '15 seconds') AS reading_time,
    (timestamp '2025-10-01 00:00:00' + (gs * interval '15 seconds'))::DATE AS reading_date,

    -- Device ID (100K devices, realistic distribution - Zipf-like)
    'device-' || lpad((1 + (CASE
        WHEN random() < 0.2 THEN (random() * 10000)::INT        -- 20% hot devices (0-10K)
        WHEN random() < 0.6 THEN 10000 + (random() * 30000)::INT  -- 40% warm (10K-40K)
        ELSE 40000 + (random() * 59999)::INT                    -- 40% cold (40K-100K)
    END))::TEXT, 6, '0') AS device_id,

    -- Sensor type (100 types, skewed - 80/20 rule)
    CASE
        WHEN random() < 0.8 THEN 1 + (random() * 19)::INT  -- 80% from top 20 types
        ELSE 20 + (random() * 79)::INT                     -- 20% from remaining 80
    END AS sensor_type_id,

    -- Temperature (normal distribution around 22°C, ±10°C)
    (22.0 + (random() - 0.5) * 20)::NUMERIC(5,2) AS temperature,

    -- Humidity (45-75%, slightly anti-correlated with temperature)
    (60.0 - ((22.0 + (random() - 0.5) * 20) - 22.0) * 0.3 + (random() - 0.5) * 20)::NUMERIC(5,2) AS humidity,

    -- Pressure (standard atmospheric)
    (1013.25 + (random() - 0.5) * 50)::NUMERIC(7,2) AS pressure,

    -- Battery level (decays over time, 100% to 70% over dataset)
    (100.0 - (gs / 10000000.0) * 30 + (random() - 0.5) * 5)::NUMERIC(5,2) AS battery_level,

    -- Status (realistic distribution: 95% ok, 4% warning, 1% error)
    CASE
        WHEN random() < 0.95 THEN 'ok'
        WHEN random() < 0.99 THEN 'warning'
        ELSE 'error'
    END AS status,

    -- Alerts (5% of readings trigger alerts)
    (random() < 0.05) AS alert_triggered,

    -- Location (1000 locations, Zipf distribution)
    'building-' || chr(65 + (CASE
        WHEN random() < 0.3 THEN (random() * 3)::INT   -- 30% in buildings A-D
        ELSE 3 + (random() * 22)::INT                  -- 70% in E-Z
    END)) ||
    '-floor-' || (1 + (random() * 10)::INT) ||
    '-room-' || lpad((1 + (random() * 100)::INT)::TEXT, 3, '0') AS location,

    -- Firmware version (10 versions, skewed to recent)
    CASE
        WHEN random() < 0.7 THEN 'v' || (8 + (random() * 2)::INT) || '.0'  -- 70% on v8-v10
        ELSE 'v' || (1 + (random() * 7)::INT) || '.0'                      -- 30% on v1-v7
    END AS firmware_version,

    -- Sequence number (incremental)
    gs AS sequence_number,

    -- Checksum (simulated - unique per row)
    md5(gs::TEXT || random()::TEXT) AS checksum

FROM generate_series(1, 10000000) gs;

\echo '  ✓ AO populated (10M rows)'
\echo ''

-- =====================================================

\echo 'Step 2/4: Populating AOCO variant...'

INSERT INTO iot.readings_aoco
SELECT * FROM iot.readings_ao;

\echo '  ✓ AOCO populated (10M rows)'
\echo ''

-- =====================================================

\echo 'Step 3/4: Populating PAX (clustered) variant...'

INSERT INTO iot.readings_pax
SELECT * FROM iot.readings_ao;

\echo '  ✓ PAX clustered populated (10M rows)'
\echo ''

-- =====================================================

\echo 'Step 4/4: Populating PAX (no-cluster) variant...'

INSERT INTO iot.readings_pax_nocluster
SELECT * FROM iot.readings_ao;

\echo '  ✓ PAX no-cluster populated (10M rows)'
\echo ''

-- =====================================================
-- ANALYZE All Tables
-- =====================================================

\echo 'Running ANALYZE on all variants...'

ANALYZE iot.readings_ao;
ANALYZE iot.readings_aoco;
ANALYZE iot.readings_pax;
ANALYZE iot.readings_pax_nocluster;

\echo '  ✓ ANALYZE complete'
\echo ''

-- =====================================================
-- Summary
-- =====================================================

\echo 'Data generation summary:'
\echo ''

SELECT
    tablename,
    CASE
        WHEN tablename = 'readings_ao' THEN 'AO'
        WHEN tablename = 'readings_aoco' THEN 'AOCO'
        WHEN tablename = 'readings_pax' THEN 'PAX (clustered)'
        WHEN tablename = 'readings_pax_nocluster' THEN 'PAX (no-cluster)'
    END AS variant,
    (SELECT COUNT(*) FROM iot.readings_ao) AS row_count,
    pg_size_pretty(pg_total_relation_size('iot.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size('iot.' || tablename)) AS table_size,
    ROUND((pg_total_relation_size('iot.' || tablename)::NUMERIC /
           (SELECT COUNT(*) FROM iot.readings_ao)::NUMERIC), 2) AS bytes_per_row
FROM pg_tables
WHERE schemaname = 'iot'
  AND tablename LIKE 'readings_%'
ORDER BY tablename;

\echo ''
\echo '===================================================='
\echo 'Data generation complete!'
\echo '===================================================='
\echo ''
\echo 'All 4 variants populated with 10M identical rows'
\echo ''
\echo 'Next: Phase 6 - Validate configuration (bloat check)'
