--
-- Phase 4: Create Storage Variants
-- Creates 4 table variants: AO, AOCO, PAX (clustered), PAX (no-cluster)
-- Based on validated configuration from Phase 3
--

\timing on

\echo '===================================================='
\echo 'IoT Benchmark - Phase 4: Create Storage Variants'
\echo '===================================================='
\echo ''

-- =====================================================
-- Base Table Structure (for reference)
-- =====================================================

\echo 'Creating 4 storage variants for comparison...'
\echo ''

-- =====================================================
-- Variant 1: AO (Append-Only Row-Oriented)
-- Baseline for comparison
-- =====================================================

\echo 'Variant 1: AO (Append-Only Row-Oriented)...'

CREATE TABLE iot.readings_ao (
    -- Time dimension
    reading_time TIMESTAMP NOT NULL,
    reading_date DATE NOT NULL,

    -- Device/sensor identifiers
    device_id VARCHAR(64) NOT NULL,
    sensor_type_id INTEGER NOT NULL,

    -- Measurements
    temperature NUMERIC(5,2),
    humidity NUMERIC(5,2),
    pressure NUMERIC(7,2),
    battery_level NUMERIC(5,2),

    -- Status flags
    status VARCHAR(20),
    alert_triggered BOOLEAN,

    -- Location
    location VARCHAR(100),

    -- Metadata
    firmware_version VARCHAR(20),
    sequence_number BIGINT,
    checksum VARCHAR(64)
) WITH (
    appendonly=true,
    orientation=row,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (device_id);

\echo '  ✓ readings_ao created (AO baseline)'
\echo ''

-- =====================================================
-- Variant 2: AOCO (Append-Only Column-Oriented)
-- Current best practice in Cloudberry
-- =====================================================

\echo 'Variant 2: AOCO (Append-Only Column-Oriented)...'

CREATE TABLE iot.readings_aoco (
    reading_time TIMESTAMP NOT NULL,
    reading_date DATE NOT NULL,
    device_id VARCHAR(64) NOT NULL,
    sensor_type_id INTEGER NOT NULL,
    temperature NUMERIC(5,2),
    humidity NUMERIC(5,2),
    pressure NUMERIC(7,2),
    battery_level NUMERIC(5,2),
    status VARCHAR(20),
    alert_triggered BOOLEAN,
    location VARCHAR(100),
    firmware_version VARCHAR(20),
    sequence_number BIGINT,
    checksum VARCHAR(64)
) WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (device_id);

\echo '  ✓ readings_aoco created (AOCO best practice)'
\echo ''

-- =====================================================
-- Variant 3: PAX (With Z-order Clustering)
-- VALIDATED configuration from Phase 3
-- =====================================================

\echo 'Variant 3: PAX (With Z-order Clustering)...'
\echo '  Using validated configuration from Phase 3:'
\echo '    - bloomfilter_columns: ONLY high-cardinality (if any)'
\echo '    - minmax_columns: All filterable columns'
\echo '    - cluster_columns: reading_time,device_id'

CREATE TABLE iot.readings_pax (
    reading_time TIMESTAMP NOT NULL,
    reading_date DATE NOT NULL,
    device_id VARCHAR(64) NOT NULL,
    sensor_type_id INTEGER NOT NULL,
    temperature NUMERIC(5,2),
    humidity NUMERIC(5,2),
    pressure NUMERIC(7,2),
    battery_level NUMERIC(5,2),
    status VARCHAR(20),
    alert_triggered BOOLEAN,
    location VARCHAR(100),
    firmware_version VARCHAR(20),
    sequence_number BIGINT,
    checksum VARCHAR(64)
) USING pax WITH (
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- MinMax statistics (low overhead, all filterable columns)
    minmax_columns='reading_date,reading_time,device_id,sensor_type_id,temperature,pressure,battery_level,location',

    -- Bloom filters: VALIDATED - only if high-cardinality columns exist
    -- Based on Phase 2 analysis, device_id and checksum are high-cardinality
    -- Note: checksum may not pass threshold in small sample, so we list device_id only
    bloomfilter_columns='device_id',

    -- Z-order clustering for time-series + device queries
    -- Note: TIMESTAMP not supported for Z-order, using DATE + device_id
    cluster_type='zorder',
    cluster_columns='reading_date,device_id',

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (device_id);

\echo '  ✓ readings_pax created (will be clustered in Phase 7)'
\echo ''

-- =====================================================
-- Variant 4: PAX No-Clustering (Control Group)
-- Same as PAX but WITHOUT Z-order clustering
-- =====================================================

\echo 'Variant 4: PAX No-Clustering (Control)...'

CREATE TABLE iot.readings_pax_nocluster (
    reading_time TIMESTAMP NOT NULL,
    reading_date DATE NOT NULL,
    device_id VARCHAR(64) NOT NULL,
    sensor_type_id INTEGER NOT NULL,
    temperature NUMERIC(5,2),
    humidity NUMERIC(5,2),
    pressure NUMERIC(7,2),
    battery_level NUMERIC(5,2),
    status VARCHAR(20),
    alert_triggered BOOLEAN,
    location VARCHAR(100),
    firmware_version VARCHAR(20),
    sequence_number BIGINT,
    checksum VARCHAR(64)
) USING pax WITH (
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- Same statistics as clustered PAX
    minmax_columns='reading_date,reading_time,device_id,sensor_type_id,temperature,pressure,battery_level,location',
    bloomfilter_columns='device_id',

    -- NO clustering (this is the key difference)
    -- cluster_type and cluster_columns intentionally omitted

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (device_id);

\echo '  ✓ readings_pax_nocluster created (no clustering)'
\echo ''

-- =====================================================
-- Verify Table Creation
-- =====================================================

\echo 'Verification - All 4 variants created:'
\echo ''

SELECT
    tablename,
    CASE
        WHEN tablename = 'readings_ao' THEN 'AO (row-oriented baseline)'
        WHEN tablename = 'readings_aoco' THEN 'AOCO (column-oriented best practice)'
        WHEN tablename = 'readings_pax' THEN 'PAX (with Z-order clustering)'
        WHEN tablename = 'readings_pax_nocluster' THEN 'PAX (no clustering - control)'
    END AS description,
    pg_size_pretty(pg_total_relation_size('iot.' || tablename)) AS current_size
FROM pg_tables
WHERE schemaname = 'iot'
  AND tablename LIKE 'readings_%'
ORDER BY tablename;

\echo ''
\echo '===================================================='
\echo 'All 4 storage variants created successfully!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 5 - Generate 10M time-series readings'
