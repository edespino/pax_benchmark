--
-- Phase 4: Create Storage Variants
-- Creates 4 table variants: AO, AOCO, PAX (clustered), PAX (no-cluster)
-- Based on validated configuration from Phase 3
--

\timing on

\echo '===================================================='
\echo 'Log Analytics - Phase 4: Create Storage Variants'
\echo '===================================================='
\echo ''

-- =====================================================
-- Creating 4 storage variants for comparison
-- =====================================================

\echo 'Creating 4 storage variants for comparison...'
\echo ''

-- =====================================================
-- Variant 1: AO (Append-Only Row-Oriented)
-- Baseline for comparison
-- =====================================================

\echo 'Variant 1: AO (Append-Only Row-Oriented)...'

CREATE TABLE logs.log_entries_ao (
    -- Time dimension
    log_timestamp TIMESTAMP NOT NULL,
    log_date DATE NOT NULL,

    -- Application/service identifiers
    application_id VARCHAR(64) NOT NULL,
    log_level VARCHAR(10) NOT NULL,

    -- Request tracing (high cardinality)
    request_id VARCHAR(64),
    trace_id VARCHAR(64),

    -- User/session (sparse - 30% NULL, high cardinality)
    user_id VARCHAR(64),
    session_id VARCHAR(64),

    -- Error information (sparse - 95% NULL for non-errors)
    error_code VARCHAR(50),
    stack_trace TEXT,

    -- HTTP metadata (sparse - 60% present)
    http_method VARCHAR(10),
    http_path TEXT,
    http_status_code INTEGER,
    response_time_ms INTEGER,

    -- Message (always present)
    message TEXT NOT NULL,

    -- Environment/location
    environment VARCHAR(20) NOT NULL,
    region VARCHAR(20) NOT NULL,
    hostname VARCHAR(64) NOT NULL,

    -- Metadata
    sequence_number BIGINT
) WITH (
    appendonly=true,
    orientation=row,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (application_id);

\echo '  ✓ log_entries_ao created (AO baseline)'
\echo ''

-- =====================================================
-- Variant 2: AOCO (Append-Only Column-Oriented)
-- Current best practice in Cloudberry
-- =====================================================

\echo 'Variant 2: AOCO (Append-Only Column-Oriented)...'

CREATE TABLE logs.log_entries_aoco (
    log_timestamp TIMESTAMP NOT NULL,
    log_date DATE NOT NULL,
    application_id VARCHAR(64) NOT NULL,
    log_level VARCHAR(10) NOT NULL,
    request_id VARCHAR(64),
    trace_id VARCHAR(64),
    user_id VARCHAR(64),
    session_id VARCHAR(64),
    error_code VARCHAR(50),
    stack_trace TEXT,
    http_method VARCHAR(10),
    http_path TEXT,
    http_status_code INTEGER,
    response_time_ms INTEGER,
    message TEXT NOT NULL,
    environment VARCHAR(20) NOT NULL,
    region VARCHAR(20) NOT NULL,
    hostname VARCHAR(64) NOT NULL,
    sequence_number BIGINT
) WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (application_id);

\echo '  ✓ log_entries_aoco created (AOCO best practice)'
\echo ''

-- =====================================================
-- Variant 3: PAX (With Z-order Clustering)
-- VALIDATED configuration from Phase 3
-- =====================================================

\echo 'Variant 3: PAX (With Z-order Clustering)...'
\echo '  Using validated configuration from Phase 3:'
\echo '    - bloomfilter_columns: trace_id,request_id (HIGH cardinality only)'
\echo '    - minmax_columns: All filterable columns'
\echo '    - cluster_columns: log_date,application_id'
\echo '    - SPARSE columns: stack_trace, error_code, user_id'

CREATE TABLE logs.log_entries_pax (
    log_timestamp TIMESTAMP NOT NULL,
    log_date DATE NOT NULL,
    application_id VARCHAR(64) NOT NULL,
    log_level VARCHAR(10) NOT NULL,
    request_id VARCHAR(64),
    trace_id VARCHAR(64),
    user_id VARCHAR(64),
    session_id VARCHAR(64),
    error_code VARCHAR(50),
    stack_trace TEXT,
    http_method VARCHAR(10),
    http_path TEXT,
    http_status_code INTEGER,
    response_time_ms INTEGER,
    message TEXT NOT NULL,
    environment VARCHAR(20) NOT NULL,
    region VARCHAR(20) NOT NULL,
    hostname VARCHAR(64) NOT NULL,
    sequence_number BIGINT
) USING pax WITH (
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- MinMax statistics (low overhead, all filterable columns)
    -- Includes low-cardinality columns (log_level, environment, region)
    minmax_columns='log_date,log_timestamp,application_id,log_level,http_status_code,response_time_ms,environment,region',

    -- Bloom filters: VALIDATED - ONLY high-cardinality columns
    -- ⚠️  CRITICAL: trace_id and request_id have ~1M unique values
    -- ⚠️  DO NOT add application_id (200 values), log_level (6 values), etc.
    bloomfilter_columns='trace_id,request_id',

    -- Z-order clustering for time-series + application queries
    -- Multi-dimensional clustering for log analysis patterns
    cluster_type='zorder',
    cluster_columns='log_date,application_id',

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (application_id);

\echo '  ✓ log_entries_pax created (will be clustered in Phase 6)'
\echo ''

-- =====================================================
-- Variant 4: PAX No-Clustering (Control Group)
-- Same as PAX but WITHOUT Z-order clustering
-- =====================================================

\echo 'Variant 4: PAX No-Clustering (Control)...'
\echo '  Same configuration as PAX clustered, but NO clustering'
\echo '  This isolates the clustering overhead from storage benefits'

CREATE TABLE logs.log_entries_pax_nocluster (
    log_timestamp TIMESTAMP NOT NULL,
    log_date DATE NOT NULL,
    application_id VARCHAR(64) NOT NULL,
    log_level VARCHAR(10) NOT NULL,
    request_id VARCHAR(64),
    trace_id VARCHAR(64),
    user_id VARCHAR(64),
    session_id VARCHAR(64),
    error_code VARCHAR(50),
    stack_trace TEXT,
    http_method VARCHAR(10),
    http_path TEXT,
    http_status_code INTEGER,
    response_time_ms INTEGER,
    message TEXT NOT NULL,
    environment VARCHAR(20) NOT NULL,
    region VARCHAR(20) NOT NULL,
    hostname VARCHAR(64) NOT NULL,
    sequence_number BIGINT
) USING pax WITH (
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- Same statistics as clustered PAX
    minmax_columns='log_date,log_timestamp,application_id,log_level,http_status_code,response_time_ms,environment,region',
    bloomfilter_columns='trace_id,request_id',

    -- NO clustering (this is the key difference)
    -- cluster_type and cluster_columns intentionally omitted

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (application_id);

\echo '  ✓ log_entries_pax_nocluster created (no clustering)'
\echo ''

-- =====================================================
-- Verify Table Creation
-- =====================================================

\echo 'Verification - All 4 variants created:'
\echo ''

SELECT
    tablename,
    CASE
        WHEN tablename = 'log_entries_ao' THEN 'AO (row-oriented baseline)'
        WHEN tablename = 'log_entries_aoco' THEN 'AOCO (column-oriented best practice)'
        WHEN tablename = 'log_entries_pax' THEN 'PAX (with Z-order clustering)'
        WHEN tablename = 'log_entries_pax_nocluster' THEN 'PAX (no clustering - control)'
    END AS description,
    pg_size_pretty(pg_total_relation_size('logs.' || tablename)) AS current_size
FROM pg_tables
WHERE schemaname = 'logs'
  AND tablename LIKE 'log_entries_%'
ORDER BY tablename;

\echo ''
\echo '===================================================='
\echo 'All 4 storage variants created successfully!'
\echo '===================================================='
\echo ''
\echo 'CONFIGURATION SUMMARY:'
\echo '  ✅ Bloom filters: ONLY on high-cardinality (trace_id, request_id)'
\echo '  ✅ MinMax: On all filterable columns (includes low-cardinality)'
\echo '  ✅ Sparse columns: stack_trace, error_code, user_id (PAX advantage)'
\echo '  ✅ Z-order clustering: log_date + application_id (for PAX variant)'
\echo ''
\echo 'Next: Phase 5 - Generate 10M log entries'
\echo 'Run: psql -f sql/05_generate_data.sql'
\echo ''
