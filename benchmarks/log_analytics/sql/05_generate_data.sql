--
-- Phase 5: Generate Log Data
-- Populates all 4 variants with identical 10M rows
-- Realistic log entries with sparse fields and realistic distributions
--

\timing on

\echo '===================================================='
\echo 'Log Analytics - Phase 5: Generate Log Data'
\echo '===================================================='
\echo ''
\echo 'Generating 10,000,000 log entries...'
\echo '  (This will take 2-4 minutes)'
\echo ''
\echo 'Key characteristics:'
\echo '  - 80% INFO, 15% WARN, 4% ERROR, 1% FATAL (realistic distribution)'
\echo '  - Sparse fields: stack_trace (95% NULL), error_code (95% NULL), user_id (30% NULL)'
\echo '  - High-cardinality: trace_id, request_id (~10M unique)'
\echo '  - Low-cardinality: log_level (6 values), application_id (200 values)'
\echo ''

-- =====================================================
-- Insert Data into All 4 Variants
-- Using INSERT INTO ... SELECT for efficiency
-- =====================================================

\echo 'Step 1/4: Populating AO variant...'

INSERT INTO logs.log_entries_ao
SELECT
    -- Time dimension (28 hours of logs, ~10 logs per second)
    timestamp '2025-10-01 00:00:00' + (gs * interval '0.1 seconds') AS log_timestamp,
    (timestamp '2025-10-01 00:00:00' + (gs * interval '0.1 seconds'))::DATE AS log_date,

    -- Application ID (200 microservices, realistic distribution - some busier than others)
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
    END || lpad((CASE
        WHEN random() < 0.3 THEN (random() * 5)::INT        -- 30% on first 5 instances
        WHEN random() < 0.7 THEN 5 + (random() * 10)::INT   -- 40% on middle instances
        ELSE 15 + (random() * 5)::INT                       -- 30% on last instances
    END)::TEXT, 2, '0') AS application_id,

    -- Log level (realistic distribution: 80% INFO, 15% WARN, 4% ERROR, 1% FATAL)
    CASE
        WHEN random() < 0.01 THEN 'TRACE'
        WHEN random() < 0.10 THEN 'DEBUG'
        WHEN random() < 0.80 THEN 'INFO'
        WHEN random() < 0.95 THEN 'WARN'
        WHEN random() < 0.99 THEN 'ERROR'
        ELSE 'FATAL'
    END AS log_level,

    -- Request ID (HIGH CARDINALITY - unique per request)
    'req-' || md5(gs::TEXT || random()::TEXT) AS request_id,

    -- Trace ID (HIGH CARDINALITY - unique per request, for distributed tracing)
    'trace-' || md5(gs::TEXT) AS trace_id,

    -- User ID (SPARSE - 30% NULL, HIGH CARDINALITY when present)
    CASE
        WHEN random() < 0.3 THEN NULL  -- 30% anonymous/system logs
        ELSE 'user-' || lpad((1 + (CASE
            WHEN random() < 0.2 THEN (random() * 100000)::INT      -- 20% hot users
            WHEN random() < 0.6 THEN 100000 + (random() * 400000)::INT  -- 40% warm
            ELSE 500000 + (random() * 4500000)::INT                -- 40% cold (up to 5M users)
        END))::TEXT, 10, '0')
    END AS user_id,

    -- Session ID (SPARSE - 30% NULL, HIGH CARDINALITY)
    CASE
        WHEN random() < 0.3 THEN NULL  -- 30% no session
        ELSE 'sess-' || md5((gs / 1000)::TEXT || random()::TEXT)
    END AS session_id,

    -- Error code (HIGHLY SPARSE - 95% NULL, only for ERROR/FATAL)
    CASE
        WHEN random() > 0.05 THEN NULL
        ELSE 'ERR-' || lpad((1 + (random() * 49)::INT)::TEXT, 4, '0')
    END AS error_code,

    -- Stack trace (HIGHLY SPARSE - 95% NULL, only for ERROR/FATAL)
    CASE
        WHEN random() > 0.05 THEN NULL
        ELSE
            E'Exception in thread "main" java.lang.' ||
            CASE (random() * 5)::INT
                WHEN 0 THEN 'NullPointerException'
                WHEN 1 THEN 'IllegalArgumentException'
                WHEN 2 THEN 'RuntimeException'
                WHEN 3 THEN 'SQLException'
                ELSE 'TimeoutException'
            END || E'\n' ||
            E'  at com.example.' ||
            CASE (random() * 5)::INT
                WHEN 0 THEN 'auth.AuthService'
                WHEN 1 THEN 'db.DatabaseConnection'
                WHEN 2 THEN 'payment.PaymentProcessor'
                WHEN 3 THEN 'cache.CacheManager'
                ELSE 'queue.MessageQueue'
            END ||
            '.process(Unknown Source:' || (100 + (random() * 900)::INT) || E')\n' ||
            E'  at com.example.core.Handler.handle(Handler.java:' || (50 + (random() * 200)::INT) || E')\n' ||
            E'  at com.example.core.Dispatcher.dispatch(Dispatcher.java:' || (20 + (random() * 80)::INT) || ')'
    END AS stack_trace,

    -- HTTP method (MODERATELY SPARSE - 40% NULL for non-web services)
    CASE
        WHEN random() < 0.4 THEN NULL
        ELSE
            CASE (random() * 10)::INT
                WHEN 0 THEN 'GET'
                WHEN 1 THEN 'GET'
                WHEN 2 THEN 'GET'
                WHEN 3 THEN 'GET'
                WHEN 4 THEN 'GET'    -- 50% GET
                WHEN 5 THEN 'POST'
                WHEN 6 THEN 'POST'   -- 20% POST
                WHEN 7 THEN 'PUT'    -- 10% PUT
                WHEN 8 THEN 'DELETE' -- 10% DELETE
                ELSE 'PATCH'         -- 10% PATCH
            END
    END AS http_method,

    -- HTTP path (MODERATELY SPARSE - 40% NULL)
    CASE
        WHEN random() < 0.4 THEN NULL
        ELSE
            '/api/v' || (1 + (random() * 2)::INT) || '/' ||
            CASE (random() * 10)::INT
                WHEN 0 THEN 'users'
                WHEN 1 THEN 'products'
                WHEN 2 THEN 'orders'
                WHEN 3 THEN 'payments'
                WHEN 4 THEN 'search'
                WHEN 5 THEN 'inventory'
                WHEN 6 THEN 'auth'
                WHEN 7 THEN 'recommendations'
                WHEN 8 THEN 'notifications'
                ELSE 'analytics'
            END ||
            CASE
                WHEN random() < 0.6 THEN ''  -- List endpoint
                ELSE '/' || (1 + (random() * 999999)::INT)::TEXT  -- Detail endpoint
            END
    END AS http_path,

    -- HTTP status code (MODERATELY SPARSE - 40% NULL)
    CASE
        WHEN random() < 0.4 THEN NULL
        ELSE
            CASE
                WHEN random() < 0.85 THEN  -- 85% success (2xx)
                    CASE (random() * 4)::INT
                        WHEN 0 THEN 200
                        WHEN 1 THEN 201
                        WHEN 2 THEN 202
                        ELSE 204
                    END
                WHEN random() < 0.92 THEN  -- 7% client errors (4xx)
                    CASE (random() * 5)::INT
                        WHEN 0 THEN 400
                        WHEN 1 THEN 401
                        WHEN 2 THEN 403
                        WHEN 3 THEN 404
                        ELSE 422
                    END
                ELSE  -- 8% server errors (5xx)
                    CASE (random() * 3)::INT
                        WHEN 0 THEN 500
                        WHEN 1 THEN 502
                        ELSE 503
                    END
            END
    END AS http_status_code,

    -- Response time (MODERATELY SPARSE - 40% NULL)
    -- Log-normal distribution (most fast, some slow, rare very slow)
    CASE
        WHEN random() < 0.4 THEN NULL
        ELSE
            CASE
                WHEN random() < 0.70 THEN (10 + random() * 90)::INTEGER     -- 70% fast (10-100ms)
                WHEN random() < 0.90 THEN (100 + random() * 400)::INTEGER   -- 20% medium (100-500ms)
                WHEN random() < 0.98 THEN (500 + random() * 1500)::INTEGER  -- 8% slow (500-2000ms)
                ELSE (2000 + random() * 8000)::INTEGER                      -- 2% very slow (2-10s)
            END
    END AS response_time_ms,

    -- Message (always present)
    CASE
        WHEN random() < 0.80 THEN
            CASE (random() * 10)::INT
                WHEN 0 THEN 'Request processed successfully'
                WHEN 1 THEN 'User authentication completed'
                WHEN 2 THEN 'Database query executed'
                WHEN 3 THEN 'Cache hit for key'
                WHEN 4 THEN 'Message published to queue'
                WHEN 5 THEN 'API request received'
                WHEN 6 THEN 'Transaction committed'
                WHEN 7 THEN 'Data validation passed'
                WHEN 8 THEN 'Resource created successfully'
                ELSE 'Operation completed'
            END
        WHEN random() < 0.95 THEN
            CASE (random() * 5)::INT
                WHEN 0 THEN 'Resource not found'
                WHEN 1 THEN 'Access denied for user'
                WHEN 2 THEN 'Invalid request parameters'
                WHEN 3 THEN 'Rate limit exceeded'
                ELSE 'Timeout waiting for response'
            END
        ELSE
            CASE (random() * 5)::INT
                WHEN 0 THEN 'Internal server error occurred'
                WHEN 1 THEN 'Database connection failed'
                WHEN 2 THEN 'External service unavailable'
                WHEN 3 THEN 'Memory allocation error'
                ELSE 'Unexpected exception during processing'
            END
    END AS message,

    -- Environment (realistic: 60% production, 30% staging, 10% dev)
    CASE
        WHEN random() < 0.60 THEN 'production'
        WHEN random() < 0.90 THEN 'staging'
        ELSE 'development'
    END AS environment,

    -- Region (6 regions, realistic distribution)
    CASE
        WHEN (random() * 100)::INT <= 40 THEN 'us-east-1'       -- 40% US East
        WHEN (random() * 100)::INT <= 60 THEN 'us-west-2'       -- 20% US West
        WHEN (random() * 100)::INT <= 75 THEN 'eu-west-1'       -- 15% EU West
        WHEN (random() * 100)::INT <= 85 THEN 'eu-central-1'    -- 10% EU Central
        WHEN (random() * 100)::INT <= 92 THEN 'ap-southeast-1'  -- 7% Asia Southeast
        ELSE 'ap-northeast-1'                                    -- 8% Asia Northeast
    END AS region,

    -- Hostname (500 hosts, realistic distribution)
    'host-' || lpad((1 + (CASE
        WHEN random() < 0.3 THEN (random() * 50)::INT       -- 30% on first 50 hosts (hot)
        WHEN random() < 0.7 THEN 50 + (random() * 150)::INT -- 40% on middle hosts
        ELSE 200 + (random() * 300)::INT                    -- 30% on remaining hosts
    END))::TEXT, 4, '0') AS hostname,

    -- Sequence number (incremental)
    gs AS sequence_number

FROM generate_series(1, 10000000) gs;

\echo '  ✓ AO populated (10M rows)'
\echo ''

-- =====================================================

\echo 'Step 2/4: Populating AOCO variant...'

INSERT INTO logs.log_entries_aoco
SELECT * FROM logs.log_entries_ao;

\echo '  ✓ AOCO populated (10M rows)'
\echo ''

-- =====================================================

\echo 'Step 3/4: Populating PAX (clustered) variant...'

INSERT INTO logs.log_entries_pax
SELECT * FROM logs.log_entries_ao;

\echo '  ✓ PAX clustered populated (10M rows)'
\echo ''

-- =====================================================

\echo 'Step 4/4: Populating PAX (no-cluster) variant...'

INSERT INTO logs.log_entries_pax_nocluster
SELECT * FROM logs.log_entries_ao;

\echo '  ✓ PAX no-cluster populated (10M rows)'
\echo ''

-- =====================================================
-- ANALYZE All Tables
-- =====================================================

\echo 'Running ANALYZE on all variants...'

ANALYZE logs.log_entries_ao;
ANALYZE logs.log_entries_aoco;
ANALYZE logs.log_entries_pax;
ANALYZE logs.log_entries_pax_nocluster;

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
        WHEN tablename = 'log_entries_ao' THEN 'AO'
        WHEN tablename = 'log_entries_aoco' THEN 'AOCO'
        WHEN tablename = 'log_entries_pax' THEN 'PAX (clustered)'
        WHEN tablename = 'log_entries_pax_nocluster' THEN 'PAX (no-cluster)'
    END AS variant,
    (SELECT COUNT(*) FROM logs.log_entries_ao) AS row_count,
    pg_size_pretty(pg_total_relation_size('logs.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size('logs.' || tablename)) AS table_size,
    pg_size_pretty(pg_indexes_size('logs.' || tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'logs'
  AND tablename LIKE 'log_entries_%'
ORDER BY tablename;

\echo ''
\echo '===================================================='
\echo 'Data generation complete!'
\echo '===================================================='
\echo ''
\echo 'Sparse field analysis (expected NULL percentages):'
\echo '  - stack_trace: ~95% NULL (only ERROR/FATAL)'
\echo '  - error_code: ~95% NULL (only ERROR/FATAL)'
\echo '  - user_id: ~30% NULL (anonymous/system logs)'
\echo '  - session_id: ~30% NULL'
\echo '  - http_*: ~40% NULL (non-web services)'
\echo ''
\echo 'This demonstrates PAX sparse filtering advantage!'
\echo ''
\echo 'Next: Phase 6 - Optimize PAX with Z-order clustering'
\echo 'Run: psql -f sql/06_optimize_pax.sql'
\echo ''
