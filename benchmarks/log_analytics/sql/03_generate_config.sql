--
-- Phase 3: Generate Safe PAX Configuration
-- Auto-generates configuration from cardinality analysis
-- Prevents manual configuration errors
--

\timing on

\echo '===================================================='
\echo 'Log Analytics - Phase 3: Generate Safe Configuration'
\echo '===================================================='
\echo ''

-- Note: This requires cardinality analysis to have been run first
-- (sql/02_analyze_cardinality.sql)

\echo 'Generating auto-validated PAX configuration...'
\echo ''

-- Re-create sample table for config generation
-- (In real usage, this would be your actual source data)
CREATE TEMP TABLE log_entries_sample AS
SELECT
    timestamp '2025-10-01 00:00:00' + (gs * interval '0.1 seconds') AS log_timestamp,
    (timestamp '2025-10-01 00:00:00' + (gs * interval '0.1 seconds'))::DATE AS log_date,

    CASE (gs % 10)
        WHEN 0 THEN 'auth-service-'
        WHEN 1 THEN 'payment-api-'
        WHEN 2 THEN 'user-service-'
        WHEN 3 THEN 'product-catalog-'
        WHEN 4 THEN 'order-service-'
        WHEN 5 THEN 'inventory-api-'
        WHEN 6 THEN 'notification-worker-'
        WHEN 7 THEN 'analytics-processor-'
        WHEN 8 THEN 'search-service-'
        ELSE 'cache-manager-'
    END || lpad((gs % 20)::TEXT, 2, '0') AS application_id,

    CASE
        WHEN random() < 0.01 THEN 'TRACE'
        WHEN random() < 0.10 THEN 'DEBUG'
        WHEN random() < 0.80 THEN 'INFO'
        WHEN random() < 0.95 THEN 'WARN'
        WHEN random() < 0.99 THEN 'ERROR'
        ELSE 'FATAL'
    END AS log_level,

    'req-' || md5(gs::TEXT || random()::TEXT) AS request_id,
    'trace-' || md5(gs::TEXT) AS trace_id,

    CASE WHEN random() < 0.3 THEN NULL ELSE 'user-' || lpad((1 + (random() * 5000000)::INT)::TEXT, 10, '0') END AS user_id,
    CASE WHEN random() < 0.3 THEN NULL ELSE 'sess-' || md5((gs / 1000)::TEXT || random()::TEXT) END AS session_id,
    CASE WHEN random() > 0.05 THEN NULL ELSE 'ERR-' || lpad((1 + (random() * 49)::INT)::TEXT, 4, '0') END AS error_code,

    CASE
        WHEN random() > 0.05 THEN NULL
        ELSE E'Exception at line ' || (100 + (random() * 900)::INT) || E'\n  at com.example.Service.process()'
    END AS stack_trace,

    CASE WHEN random() < 0.6 THEN CASE (random() * 5)::INT WHEN 0 THEN 'GET' WHEN 1 THEN 'POST' ELSE 'PUT' END ELSE NULL END AS http_method,
    CASE WHEN random() < 0.6 THEN '/api/v1/resource' ELSE NULL END AS http_path,
    CASE WHEN random() < 0.6 THEN 200 + (random() * 299)::INT ELSE NULL END AS http_status_code,
    CASE WHEN random() < 0.6 THEN (10 + random() * 5000)::INTEGER ELSE NULL END AS response_time_ms,

    'Log message ' || gs AS message,

    CASE (gs % 3) WHEN 0 THEN 'production' WHEN 1 THEN 'staging' ELSE 'development' END AS environment,
    CASE (gs % 6) WHEN 0 THEN 'us-east-1' WHEN 1 THEN 'us-west-2' ELSE 'eu-west-1' END AS region,
    'host-' || lpad((1 + (gs % 500))::TEXT, 4, '0') AS hostname,

    gs AS sequence_number
FROM generate_series(1, 100000) gs;

ANALYZE log_entries_sample;

\echo '  ✓ Sample data created for configuration generation'
\echo ''

-- =====================================================
-- Generate Configuration
-- =====================================================

\echo '===================================================='
\echo 'AUTO-GENERATED PAX CONFIGURATION'
\echo '===================================================='
\echo ''
\echo 'Configuration based on analyzed cardinality:'
\echo ''

SELECT * FROM logs_validation.generate_pax_config(
    'pg_temp',              -- Schema containing sample table
    'log_entries_sample'    -- Sample table name
);

\echo ''

-- Memory recommendation
\echo 'Memory recommendation for 10M rows:'
\echo ''

SELECT * FROM logs_validation.calculate_cluster_memory(10000000);

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
\echo 'RECOMMENDED MANUAL ADDITIONS:'
\echo '  cluster_columns=''log_date,application_id'''
\echo '  cluster_type=''zorder'''
\echo '  storage_format=''porc'''
\echo '  compresstype=''zstd'''
\echo '  compresslevel=5'
\echo ''
\echo 'Copy the configuration above to create your PAX tables safely.'
\echo ''
\echo 'Next: Phase 4 - Create storage variants with validated configuration'
\echo 'Run: psql -f sql/04_create_variants.sql'
\echo ''

-- Cleanup
DROP TABLE IF EXISTS log_entries_sample;
