--
-- Phase 9: Query Performance Tests
-- Runs test queries on all 4 variants to measure query performance
-- after streaming INSERTs complete
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 9: Query Performance Tests'
\echo '===================================================='
\echo ''

-- =====================================================
-- Query 1: Time-Range Scan (Last Hour)
-- Tests: Sparse filtering, time-based pruning
-- =====================================================

\echo 'Q1: Time-range scan (last hour of calls)'
\echo ''

\echo '--- AO ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_ao
WHERE call_timestamp >= (SELECT MAX(call_timestamp) - interval '1 hour' FROM cdr.cdr_ao);

\echo ''
\echo '--- AOCO ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_aoco
WHERE call_timestamp >= (SELECT MAX(call_timestamp) - interval '1 hour' FROM cdr.cdr_aoco);

\echo ''
\echo '--- PAX ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_pax
WHERE call_timestamp >= (SELECT MAX(call_timestamp) - interval '1 hour' FROM cdr.cdr_pax);

\echo ''
\echo '--- PAX no-cluster ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_pax_nocluster
WHERE call_timestamp >= (SELECT MAX(call_timestamp) - interval '1 hour' FROM cdr.cdr_pax_nocluster);

\echo ''

-- =====================================================
-- Query 2: High-Cardinality Filter (Specific Caller)
-- Tests: Bloom filter effectiveness
-- =====================================================

\echo '===================================================='
\echo 'Q2: High-cardinality filter (specific caller number)'
\echo ''

\echo '--- AO ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_ao
WHERE caller_number = '+1-0000123456';

\echo ''
\echo '--- AOCO ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_aoco
WHERE caller_number = '+1-0000123456';

\echo ''
\echo '--- PAX ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_pax
WHERE caller_number = '+1-0000123456';

\echo ''
\echo '--- PAX no-cluster ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_pax_nocluster
WHERE caller_number = '+1-0000123456';

\echo ''

-- =====================================================
-- Query 3: Multi-Dimensional Filter (Time + Location)
-- Tests: Z-order clustering effectiveness
-- =====================================================

\echo '===================================================='
\echo 'Q3: Multi-dimensional filter (time + cell tower)'
\echo ''

\echo '--- AO ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_ao
WHERE call_date = DATE '2025-10-01'
  AND call_hour BETWEEN 8 AND 10
  AND cell_tower_id BETWEEN 1000 AND 1100;

\echo ''
\echo '--- AOCO ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_aoco
WHERE call_date = DATE '2025-10-01'
  AND call_hour BETWEEN 8 AND 10
  AND cell_tower_id BETWEEN 1000 AND 1100;

\echo ''
\echo '--- PAX ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_pax
WHERE call_date = DATE '2025-10-01'
  AND call_hour BETWEEN 8 AND 10
  AND cell_tower_id BETWEEN 1000 AND 1100;

\echo ''
\echo '--- PAX no-cluster ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duration_seconds), SUM(billing_amount)
FROM cdr.cdr_pax_nocluster
WHERE call_date = DATE '2025-10-01'
  AND call_hour BETWEEN 8 AND 10
  AND cell_tower_id BETWEEN 1000 AND 1100;

\echo ''

-- =====================================================
-- Query 4: Aggregation by Cell Tower
-- Tests: Column compression, aggregation performance
-- =====================================================

\echo '===================================================='
\echo 'Q4: Aggregation by cell tower (top 10 busiest)'
\echo ''

\echo '--- AO ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT cell_tower_id, COUNT(*) AS call_count,
       AVG(duration_seconds) AS avg_duration,
       SUM(billing_amount) AS total_revenue
FROM cdr.cdr_ao
GROUP BY cell_tower_id
ORDER BY call_count DESC
LIMIT 10;

\echo ''
\echo '--- AOCO ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT cell_tower_id, COUNT(*) AS call_count,
       AVG(duration_seconds) AS avg_duration,
       SUM(billing_amount) AS total_revenue
FROM cdr.cdr_aoco
GROUP BY cell_tower_id
ORDER BY call_count DESC
LIMIT 10;

\echo ''
\echo '--- PAX ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT cell_tower_id, COUNT(*) AS call_count,
       AVG(duration_seconds) AS avg_duration,
       SUM(billing_amount) AS total_revenue
FROM cdr.cdr_pax
GROUP BY cell_tower_id
ORDER BY call_count DESC
LIMIT 10;

\echo ''
\echo '--- PAX no-cluster ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT cell_tower_id, COUNT(*) AS call_count,
       AVG(duration_seconds) AS avg_duration,
       SUM(billing_amount) AS total_revenue
FROM cdr.cdr_pax_nocluster
GROUP BY cell_tower_id
ORDER BY call_count DESC
LIMIT 10;

\echo ''
\echo '===================================================='
\echo 'Query performance tests complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 10 - Collect comprehensive metrics'
