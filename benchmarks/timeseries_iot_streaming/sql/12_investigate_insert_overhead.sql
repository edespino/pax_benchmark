-- =====================================================
-- Phase 12: Investigate INSERT Performance Gap
-- =====================================================
-- Goal: Determine why PAX is 20% slower than AO for INSERT
-- Hypothesis: Bloom filter building during INSERT
--
-- Test: Create PAX variant WITHOUT bloom filters
-- Compare: PAX-minimal vs PAX-full vs AO

\timing on
\echo '===================================================='
\echo 'Investigating PAX INSERT Overhead'
\echo '===================================================='
\echo ''

-- =====================================================
-- Create Minimal PAX Variant (No Bloom Filters)
-- =====================================================

\echo 'Creating test variant: PAX-minimal (no bloom filters)...'

DROP TABLE IF EXISTS cdr.cdr_pax_minimal CASCADE;

CREATE TABLE cdr.cdr_pax_minimal (
    call_id TEXT NOT NULL,
    call_timestamp TIMESTAMP NOT NULL,
    call_date DATE NOT NULL,
    call_hour INTEGER NOT NULL,
    caller_number TEXT NOT NULL,
    callee_number TEXT NOT NULL,
    duration_seconds INTEGER NOT NULL,
    cell_tower_id INTEGER NOT NULL,
    call_type TEXT NOT NULL,
    network_type TEXT NOT NULL,
    bytes_transferred BIGINT,
    termination_code INTEGER NOT NULL,
    billing_amount NUMERIC(10,4) NOT NULL,
    rate_plan_id INTEGER,
    is_roaming BOOLEAN DEFAULT FALSE,
    call_quality_mos NUMERIC(3,2),
    packet_loss_percent NUMERIC(5,2),
    sequence_number BIGINT
) USING pax WITH (
    -- Core compression only
    compresstype='zstd',
    compresslevel=5,

    -- NO bloom filters (hypothesis: this is the INSERT overhead)
    -- bloomfilter_columns='',  -- Omitted entirely

    -- MinMax only (low overhead)
    minmax_columns='call_date,call_hour,duration_seconds',

    -- NO clustering
    -- cluster_type and cluster_columns intentionally omitted

    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ cdr.cdr_pax_minimal created (PAX minimal config)'
\echo ''

-- =====================================================
-- Small INSERT Test (1M rows)
-- =====================================================

\echo 'Running INSERT test: 1M rows into each variant...'
\echo ''

-- Create test data generation function
CREATE OR REPLACE FUNCTION cdr.generate_test_batch(p_size INTEGER)
RETURNS TABLE (
    call_id TEXT,
    call_timestamp TIMESTAMP,
    call_date DATE,
    call_hour INTEGER,
    caller_number TEXT,
    callee_number TEXT,
    duration_seconds INTEGER,
    cell_tower_id INTEGER,
    call_type TEXT,
    network_type TEXT,
    bytes_transferred BIGINT,
    termination_code INTEGER,
    billing_amount NUMERIC(10,4),
    rate_plan_id INTEGER,
    is_roaming BOOLEAN,
    call_quality_mos NUMERIC(3,2),
    packet_loss_percent NUMERIC(5,2),
    sequence_number BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        md5(random()::TEXT)::TEXT AS call_id,
        NOW() - (random() * INTERVAL '24 hours') AS call_timestamp,
        CURRENT_DATE - (random() * 30)::INTEGER AS call_date,
        (random() * 23)::INTEGER AS call_hour,
        '1' || LPAD((random() * 9999999999)::BIGINT::TEXT, 10, '0') AS caller_number,
        '1' || LPAD((random() * 9999999999)::BIGINT::TEXT, 10, '0') AS callee_number,
        (random() * 3600)::INTEGER AS duration_seconds,
        (random() * 10000)::INTEGER + 1 AS cell_tower_id,
        CASE (random() * 4)::INTEGER
            WHEN 0 THEN 'VOICE'
            WHEN 1 THEN 'SMS'
            WHEN 2 THEN 'DATA'
            WHEN 3 THEN 'VIDEO'
            ELSE 'MMS'
        END AS call_type,
        CASE (random() * 2)::INTEGER
            WHEN 0 THEN '4G'
            WHEN 1 THEN '5G'
            ELSE '3G'
        END AS network_type,
        (random() * 1000000000)::BIGINT AS bytes_transferred,
        (random() * 20)::INTEGER AS termination_code,
        (random() * 100)::NUMERIC(10,4) AS billing_amount,
        (random() * 50)::INTEGER + 1 AS rate_plan_id,
        random() > 0.9 AS is_roaming,
        (random() * 5)::NUMERIC(3,2) AS call_quality_mos,
        (random() * 10)::NUMERIC(5,2) AS packet_loss_percent,
        gs AS sequence_number
    FROM generate_series(1, p_size) gs;
END;
$$ LANGUAGE plpgsql;

-- Test 1: AO (baseline)
\echo 'Test 1: AO (baseline - fastest writes)...'
TRUNCATE cdr.cdr_ao;
INSERT INTO cdr.cdr_ao SELECT * FROM cdr.generate_test_batch(1000000);
\echo ''

-- Test 2: PAX-minimal (no bloom filters)
\echo 'Test 2: PAX-minimal (no bloom filters)...'
INSERT INTO cdr.cdr_pax_minimal SELECT * FROM cdr.generate_test_batch(1000000);
\echo ''

-- Test 3: PAX-no-cluster (3 bloom filters, no clustering)
\echo 'Test 3: PAX-no-cluster (3 bloom filters, no clustering)...'
TRUNCATE cdr.cdr_pax_nocluster;
INSERT INTO cdr.cdr_pax_nocluster SELECT * FROM cdr.generate_test_batch(1000000);
\echo ''

-- Test 4: AOCO (baseline columnar)
\echo 'Test 4: AOCO (baseline columnar)...'
TRUNCATE cdr.cdr_aoco;
INSERT INTO cdr.cdr_aoco SELECT * FROM cdr.generate_test_batch(1000000);
\echo ''

-- =====================================================
-- Compare Results
-- =====================================================

\echo '===================================================='
\echo 'Storage Comparison'
\echo '===================================================='
\echo ''

SELECT
    'AO' AS variant,
    pg_size_pretty(pg_total_relation_size('cdr.cdr_ao')) AS size,
    1.00 AS vs_ao_ratio,
    'Row-oriented baseline' AS description
UNION ALL
SELECT
    'AOCO' AS variant,
    pg_size_pretty(pg_total_relation_size('cdr.cdr_aoco')) AS size,
    pg_total_relation_size('cdr.cdr_aoco')::NUMERIC /
        NULLIF(pg_total_relation_size('cdr.cdr_ao'), 0) AS vs_ao_ratio,
    'Column-oriented baseline' AS description
UNION ALL
SELECT
    'PAX-minimal' AS variant,
    pg_size_pretty(pg_total_relation_size('cdr.cdr_pax_minimal')) AS size,
    pg_total_relation_size('cdr.cdr_pax_minimal')::NUMERIC /
        NULLIF(pg_total_relation_size('cdr.cdr_ao'), 0) AS vs_ao_ratio,
    'PAX: compression + minmax only' AS description
UNION ALL
SELECT
    'PAX-no-cluster' AS variant,
    pg_size_pretty(pg_total_relation_size('cdr.cdr_pax_nocluster')) AS size,
    pg_total_relation_size('cdr.cdr_pax_nocluster')::NUMERIC /
        NULLIF(pg_total_relation_size('cdr.cdr_ao'), 0) AS vs_ao_ratio,
    'PAX: + 3 bloom filters' AS description
ORDER BY vs_ao_ratio;

\echo ''
\echo '===================================================='
\echo 'Analysis'
\echo '===================================================='
\echo ''
\echo 'Expected findings if bloom filters cause INSERT overhead:'
\echo '  1. PAX-minimal INSERT time ≈ AO INSERT time'
\echo '  2. PAX-no-cluster INSERT time > PAX-minimal INSERT time'
\echo '  3. Time difference ≈ bloom filter building overhead'
\echo ''
\echo 'Expected findings if columnar encoding causes overhead:'
\echo '  1. PAX-minimal INSERT time ≈ AOCO INSERT time'
\echo '  2. Both slower than AO by similar margin'
\echo ''
\echo 'Check the timing output above to determine root cause.'
\echo ''

-- Cleanup
DROP FUNCTION cdr.generate_test_batch(INTEGER);

\echo '===================================================='
\echo 'Investigation complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Review timing output to identify INSERT overhead source'
\echo ''
