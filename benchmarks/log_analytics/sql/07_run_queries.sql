--
-- Phase 7: Run Query Suite
-- Tests all 4 variants with realistic log analytics queries
-- Categories: Time filtering, bloom filters, sparse columns, Z-order clustering, aggregations
--

\timing on

\echo '===================================================='
\echo 'Log Analytics - Phase 7: Query Suite'
\echo '===================================================='
\echo ''
\echo 'Running 12 queries across all 4 storage variants'
\echo '  (This will take 3-5 minutes)'
\echo ''

-- Warm up (ensure caches are loaded)
\echo 'Warming up caches...'
SELECT COUNT(*) FROM logs.log_entries_ao WHERE log_date >= '2025-10-01' LIMIT 1;
SELECT COUNT(*) FROM logs.log_entries_aoco WHERE log_date >= '2025-10-01' LIMIT 1;
SELECT COUNT(*) FROM logs.log_entries_pax WHERE log_date >= '2025-10-01' LIMIT 1;
SELECT COUNT(*) FROM logs.log_entries_pax_nocluster WHERE log_date >= '2025-10-01' LIMIT 1;
\echo '  ✓ Warm-up complete'
\echo ''

-- =====================================================
-- CATEGORY A: Time Range Filtering (Sparse Filter Test)
-- Tests PAX sparse filtering effectiveness
-- =====================================================

\echo '===================================================='
\echo 'CATEGORY A: Time Range Filtering'
\echo '===================================================='
\echo ''

\echo 'Q1: Recent logs (last 2 hours) - Tests temporal filtering'
\echo ''

\echo '  AO:'
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), log_level FROM logs.log_entries_ao WHERE log_timestamp >= timestamp '2025-10-01 20:00:00' GROUP BY log_level;
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), log_level FROM logs.log_entries_aoco WHERE log_timestamp >= timestamp '2025-10-01 20:00:00' GROUP BY log_level;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), log_level FROM logs.log_entries_pax WHERE log_timestamp >= timestamp '2025-10-01 20:00:00' GROUP BY log_level;
\echo ''

\echo '  PAX (no-cluster):'
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), log_level FROM logs.log_entries_pax_nocluster WHERE log_timestamp >= timestamp '2025-10-01 20:00:00' GROUP BY log_level;
\echo ''

-- =====================================================
-- CATEGORY B: Bloom Filter Tests (High-Cardinality)
-- Tests bloom filter effectiveness on trace_id and request_id
-- =====================================================

\echo '===================================================='
\echo 'CATEGORY B: Bloom Filter Tests'
\echo '===================================================='
\echo ''

\echo 'Q2: Trace ID lookup - Tests bloom filter on high-cardinality column'
\echo ''

\echo '  AO:'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM logs.log_entries_ao WHERE trace_id = 'trace-c4ca4238a0b923820dcc509a6f75849b' LIMIT 100;
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM logs.log_entries_aoco WHERE trace_id = 'trace-c4ca4238a0b923820dcc509a6f75849b' LIMIT 100;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM logs.log_entries_pax WHERE trace_id = 'trace-c4ca4238a0b923820dcc509a6f75849b' LIMIT 100;
\echo ''

\echo '  PAX (no-cluster):'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM logs.log_entries_pax_nocluster WHERE trace_id = 'trace-c4ca4238a0b923820dcc509a6f75849b' LIMIT 100;
\echo ''

\echo 'Q3: Request ID IN list - Tests bloom filter with multiple values'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS) SELECT log_level, COUNT(*) FROM logs.log_entries_aoco WHERE request_id IN ('req-abc123', 'req-def456', 'req-ghi789') GROUP BY log_level;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS) SELECT log_level, COUNT(*) FROM logs.log_entries_pax WHERE request_id IN ('req-abc123', 'req-def456', 'req-ghi789') GROUP BY log_level;
\echo ''

-- =====================================================
-- CATEGORY C: Z-order Clustering Tests
-- Tests multi-dimensional range queries (time + application)
-- =====================================================

\echo '===================================================='
\echo 'CATEGORY C: Z-order Clustering Tests'
\echo '===================================================='
\echo ''

\echo 'Q4: Application logs in time range - Tests Z-order clustering benefit'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS) SELECT log_level, COUNT(*) FROM logs.log_entries_aoco WHERE log_date = '2025-10-01' AND application_id LIKE 'payment-api-%' GROUP BY log_level;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS) SELECT log_level, COUNT(*) FROM logs.log_entries_pax WHERE log_date = '2025-10-01' AND application_id LIKE 'payment-api-%' GROUP BY log_level;
\echo ''

\echo '  PAX (no-cluster):'
EXPLAIN (ANALYZE, BUFFERS) SELECT log_level, COUNT(*) FROM logs.log_entries_pax_nocluster WHERE log_date = '2025-10-01' AND application_id LIKE 'payment-api-%' GROUP BY log_level;
\echo ''

-- =====================================================
-- CATEGORY D: Sparse Column Tests (PAX Advantage)
-- Tests queries on sparse columns (error_code, stack_trace)
-- =====================================================

\echo '===================================================='
\echo 'CATEGORY D: Sparse Column Tests'
\echo '===================================================='
\echo ''

\echo 'Q5: Error analysis - Tests sparse column filtering (95% NULL)'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS) SELECT application_id, error_code, COUNT(*) FROM logs.log_entries_aoco WHERE error_code IS NOT NULL GROUP BY application_id, error_code ORDER BY COUNT(*) DESC LIMIT 20;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS) SELECT application_id, error_code, COUNT(*) FROM logs.log_entries_pax WHERE error_code IS NOT NULL GROUP BY application_id, error_code ORDER BY COUNT(*) DESC LIMIT 20;
\echo ''

\echo 'Q6: Stack trace search - Tests text search on sparse column'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*) FROM logs.log_entries_aoco WHERE stack_trace LIKE '%NullPointerException%';
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*) FROM logs.log_entries_pax WHERE stack_trace LIKE '%NullPointerException%';
\echo ''

-- =====================================================
-- CATEGORY E: Log Level Analysis
-- Tests filtering on low-cardinality column (minmax only)
-- =====================================================

\echo '===================================================='
\echo 'CATEGORY E: Log Level Analysis'
\echo '===================================================='
\echo ''

\echo 'Q7: Error rate by application - Tests low-cardinality filtering'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT application_id, log_level, COUNT(*) as log_count
FROM logs.log_entries_aoco
WHERE log_level IN ('ERROR', 'FATAL')
  AND log_date = '2025-10-01'
GROUP BY application_id, log_level
ORDER BY log_count DESC
LIMIT 20;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS)
SELECT application_id, log_level, COUNT(*) as log_count
FROM logs.log_entries_pax
WHERE log_level IN ('ERROR', 'FATAL')
  AND log_date = '2025-10-01'
GROUP BY application_id, log_level
ORDER BY log_count DESC
LIMIT 20;
\echo ''

-- =====================================================
-- CATEGORY F: HTTP Performance Analysis
-- Tests queries on moderately sparse HTTP columns (40% NULL)
-- =====================================================

\echo '===================================================='
\echo 'CATEGORY F: HTTP Performance Analysis'
\echo '===================================================='
\echo ''

\echo 'Q8: Slow requests - Tests response_time filtering'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT application_id, http_method, AVG(response_time_ms)::INTEGER as avg_ms, COUNT(*)
FROM logs.log_entries_aoco
WHERE response_time_ms > 1000
  AND log_date = '2025-10-01'
GROUP BY application_id, http_method
ORDER BY avg_ms DESC
LIMIT 20;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS)
SELECT application_id, http_method, AVG(response_time_ms)::INTEGER as avg_ms, COUNT(*)
FROM logs.log_entries_pax
WHERE response_time_ms > 1000
  AND log_date = '2025-10-01'
GROUP BY application_id, http_method
ORDER BY avg_ms DESC
LIMIT 20;
\echo ''

\echo 'Q9: HTTP status code distribution - Tests status code filtering'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT http_status_code, COUNT(*) as count
FROM logs.log_entries_aoco
WHERE http_status_code >= 400
  AND log_timestamp >= timestamp '2025-10-01 12:00:00'
GROUP BY http_status_code
ORDER BY count DESC;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS)
SELECT http_status_code, COUNT(*) as count
FROM logs.log_entries_pax
WHERE http_status_code >= 400
  AND log_timestamp >= timestamp '2025-10-01 12:00:00'
GROUP BY http_status_code
ORDER BY count DESC;
\echo ''

-- =====================================================
-- CATEGORY G: Multi-Dimensional Analysis
-- Complex queries testing multiple PAX features together
-- =====================================================

\echo '===================================================='
\echo 'CATEGORY G: Multi-Dimensional Analysis'
\echo '===================================================='
\echo ''

\echo 'Q10: Regional error analysis - Tests Z-order + sparse columns'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT region, environment, application_id, COUNT(*) as error_count
FROM logs.log_entries_aoco
WHERE log_level IN ('ERROR', 'FATAL')
  AND log_date = '2025-10-01'
  AND error_code IS NOT NULL
GROUP BY region, environment, application_id
ORDER BY error_count DESC
LIMIT 30;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS)
SELECT region, environment, application_id, COUNT(*) as error_count
FROM logs.log_entries_pax
WHERE log_level IN ('ERROR', 'FATAL')
  AND log_date = '2025-10-01'
  AND error_code IS NOT NULL
GROUP BY region, environment, application_id
ORDER BY error_count DESC
LIMIT 30;
\echo ''

\echo 'Q11: User session analysis - Tests bloom filter + sparse columns'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, COUNT(DISTINCT session_id) as sessions, COUNT(*) as logs
FROM logs.log_entries_aoco
WHERE user_id IS NOT NULL
  AND log_date = '2025-10-01'
GROUP BY user_id
HAVING COUNT(*) > 100
ORDER BY logs DESC
LIMIT 20;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, COUNT(DISTINCT session_id) as sessions, COUNT(*) as logs
FROM logs.log_entries_pax
WHERE user_id IS NOT NULL
  AND log_date = '2025-10-01'
GROUP BY user_id
HAVING COUNT(*) > 100
ORDER BY logs DESC
LIMIT 20;
\echo ''

\echo 'Q12: Full scan aggregation - Tests compression efficiency'
\echo ''

\echo '  AOCO:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    log_level,
    environment,
    COUNT(*) as count,
    COUNT(DISTINCT application_id) as apps,
    COUNT(error_code) as errors,
    AVG(CASE WHEN response_time_ms IS NOT NULL THEN response_time_ms END)::INTEGER as avg_response_ms
FROM logs.log_entries_aoco
WHERE log_date = '2025-10-01'
GROUP BY log_level, environment
ORDER BY count DESC;
\echo ''

\echo '  PAX (clustered):'
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    log_level,
    environment,
    COUNT(*) as count,
    COUNT(DISTINCT application_id) as apps,
    COUNT(error_code) as errors,
    AVG(CASE WHEN response_time_ms IS NOT NULL THEN response_time_ms END)::INTEGER as avg_response_ms
FROM logs.log_entries_pax
WHERE log_date = '2025-10-01'
GROUP BY log_level, environment
ORDER BY count DESC;
\echo ''

-- =====================================================
-- Summary
-- =====================================================

\echo '===================================================='
\echo 'Query suite complete!'
\echo '===================================================='
\echo ''
\echo 'Tested query categories:'
\echo '  A. Time range filtering (sparse filter effectiveness)'
\echo '  B. Bloom filters (trace_id, request_id high-cardinality)'
\echo '  C. Z-order clustering (time + application multi-dimensional)'
\echo '  D. Sparse columns (error_code, stack_trace 95% NULL)'
\echo '  E. Log level analysis (low-cardinality filtering)'
\echo '  F. HTTP performance (moderately sparse columns 40% NULL)'
\echo '  G. Multi-dimensional (combined PAX features)'
\echo ''
\echo 'Next: Phase 8 - Collect comprehensive metrics'
\echo 'Run: psql -f sql/08_collect_metrics.sql'
\echo ''
