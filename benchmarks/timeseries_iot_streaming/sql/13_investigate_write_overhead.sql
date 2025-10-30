-- =====================================================
-- Phase 13: Investigate PAX Write Overhead
-- =====================================================
-- Goal: Identify why PAX is 9.7% slower than AOCO for INSERTs
--
-- Test Matrix:
--   1. PAX-minimal (no bloom, minimal minmax)
--   2. PAX-minmax-only (no bloom, full minmax)
--   3. PAX-1-bloom (1 bloom filter)
--   4. PAX-2-bloom (2 bloom filters)
--   5. PAX-3-bloom (3 bloom filters - current config)
--
-- Expected: Bloom filters add ~3-5% overhead each

\timing on

\echo '===================================================='
\echo 'PAX Write Overhead Investigation'
\echo '===================================================='
\echo ''
\echo 'Creating 5 PAX variants with different bloom filter counts...'
\echo ''

-- =====================================================
-- Variant 1: PAX Minimal (compression only)
-- =====================================================

\echo 'Creating PAX-minimal (compression only, no bloom, minimal minmax)...'

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
    compresstype='zstd',
    compresslevel=5,
    -- NO bloom filters
    minmax_columns='call_date',  -- Minimal (just 1 column)
    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ PAX-minimal created'
\echo ''

-- =====================================================
-- Variant 2: PAX MinMax Only (no bloom)
-- =====================================================

\echo 'Creating PAX-minmax-only (full minmax, no bloom)...'

DROP TABLE IF EXISTS cdr.cdr_pax_minmax CASCADE;

CREATE TABLE cdr.cdr_pax_minmax (
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
    compresstype='zstd',
    compresslevel=5,
    -- NO bloom filters
    minmax_columns='call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code,billing_amount',
    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ PAX-minmax-only created'
\echo ''

-- =====================================================
-- Variant 3: PAX with 1 Bloom Filter
-- =====================================================

\echo 'Creating PAX-1-bloom (1 bloom filter)...'

DROP TABLE IF EXISTS cdr.cdr_pax_1bloom CASCADE;

CREATE TABLE cdr.cdr_pax_1bloom (
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
    compresstype='zstd',
    compresslevel=5,
    bloomfilter_columns='caller_number',  -- Just 1
    minmax_columns='call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code,billing_amount',
    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ PAX-1-bloom created'
\echo ''

-- =====================================================
-- Variant 4: PAX with 2 Bloom Filters
-- =====================================================

\echo 'Creating PAX-2-bloom (2 bloom filters)...'

DROP TABLE IF EXISTS cdr.cdr_pax_2bloom CASCADE;

CREATE TABLE cdr.cdr_pax_2bloom (
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
    compresstype='zstd',
    compresslevel=5,
    bloomfilter_columns='caller_number,callee_number',  -- 2 bloom filters
    minmax_columns='call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code,billing_amount',
    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ PAX-2-bloom created'
\echo ''

-- =====================================================
-- Small INSERT Test (1M rows each)
-- =====================================================

\echo '===================================================='
\echo 'Running INSERT test: 1M rows per variant'
\echo '===================================================='
\echo ''

-- Test 1: AOCO (baseline columnar)
\echo 'Test 1: AOCO (baseline columnar)...'
INSERT INTO cdr.cdr_aoco
SELECT * FROM cdr.generate_cdr_batch(1, 1000000, 12);

-- Test 2: PAX-minimal
\echo 'Test 2: PAX-minimal (compression only)...'
INSERT INTO cdr.cdr_pax_minimal
SELECT * FROM cdr.generate_cdr_batch(1000001, 1000000, 12);

-- Test 3: PAX-minmax-only
\echo 'Test 3: PAX-minmax-only (9 minmax columns)...'
INSERT INTO cdr.cdr_pax_minmax
SELECT * FROM cdr.generate_cdr_batch(2000001, 1000000, 12);

-- Test 4: PAX-1-bloom
\echo 'Test 4: PAX-1-bloom (1 bloom filter)...'
INSERT INTO cdr.cdr_pax_1bloom
SELECT * FROM cdr.generate_cdr_batch(3000001, 1000000, 12);

-- Test 5: PAX-2-bloom
\echo 'Test 5: PAX-2-bloom (2 bloom filters)...'
INSERT INTO cdr.cdr_pax_2bloom
SELECT * FROM cdr.generate_cdr_batch(4000001, 1000000, 12);

-- Test 6: PAX-no-cluster (3 bloom filters - current config)
\echo 'Test 6: PAX-no-cluster (3 bloom filters - current config)...'
TRUNCATE cdr.cdr_pax_nocluster;
INSERT INTO cdr.cdr_pax_nocluster
SELECT * FROM cdr.generate_cdr_batch(5000001, 1000000, 12);

-- Test 7: AO (baseline row-oriented)
\echo 'Test 7: AO (baseline row-oriented)...'
TRUNCATE cdr.cdr_ao;
INSERT INTO cdr.cdr_ao
SELECT * FROM cdr.generate_cdr_batch(6000001, 1000000, 12);

\echo ''
\echo '===================================================='
\echo 'Results Summary'
\echo '===================================================='
\echo ''

-- Storage comparison
\echo 'Storage Comparison:'
\echo ''

SELECT
    variant,
    size,
    ROUND((size_bytes::NUMERIC / aoco_size_bytes * 100) - 100, 1) AS pct_vs_aoco,
    CASE
        WHEN bloom_count = 0 THEN '✅ No bloom overhead'
        WHEN pct_vs_aoco < 5 THEN '✅ Minimal overhead'
        WHEN pct_vs_aoco < 10 THEN '⚠️ Moderate overhead'
        ELSE '❌ High overhead'
    END AS assessment
FROM (
    SELECT
        'AO' AS variant,
        pg_size_pretty(pg_total_relation_size('cdr.cdr_ao')) AS size,
        pg_total_relation_size('cdr.cdr_ao') AS size_bytes,
        0 AS bloom_count
    UNION ALL
    SELECT
        'AOCO (baseline)' AS variant,
        pg_size_pretty(pg_total_relation_size('cdr.cdr_aoco')) AS size,
        pg_total_relation_size('cdr.cdr_aoco') AS size_bytes,
        0 AS bloom_count
    UNION ALL
    SELECT
        'PAX-minimal' AS variant,
        pg_size_pretty(pg_total_relation_size('cdr.cdr_pax_minimal')) AS size,
        pg_total_relation_size('cdr.cdr_pax_minimal') AS size_bytes,
        0 AS bloom_count
    UNION ALL
    SELECT
        'PAX-minmax-only' AS variant,
        pg_size_pretty(pg_total_relation_size('cdr.cdr_pax_minmax')) AS size,
        pg_total_relation_size('cdr.cdr_pax_minmax') AS size_bytes,
        0 AS bloom_count
    UNION ALL
    SELECT
        'PAX-1-bloom' AS variant,
        pg_size_pretty(pg_total_relation_size('cdr.cdr_pax_1bloom')) AS size,
        pg_total_relation_size('cdr.cdr_pax_1bloom') AS size_bytes,
        1 AS bloom_count
    UNION ALL
    SELECT
        'PAX-2-bloom' AS variant,
        pg_size_pretty(pg_total_relation_size('cdr.cdr_pax_2bloom')) AS size,
        pg_total_relation_size('cdr.cdr_pax_2bloom') AS size_bytes,
        2 AS bloom_count
    UNION ALL
    SELECT
        'PAX-no-cluster (3 bloom)' AS variant,
        pg_size_pretty(pg_total_relation_size('cdr.cdr_pax_nocluster')) AS size,
        pg_total_relation_size('cdr.cdr_pax_nocluster') AS size_bytes,
        3 AS bloom_count
) sizes
CROSS JOIN (
    SELECT pg_total_relation_size('cdr.cdr_aoco') AS aoco_size_bytes
) baseline
ORDER BY size_bytes;

\echo ''
\echo '===================================================='
\echo 'Analysis'
\echo '===================================================='
\echo ''
\echo 'Expected findings:'
\echo '  1. PAX-minimal should match AOCO INSERT time (isolate columnar encoding overhead)'
\echo '  2. PAX-minmax-only should be ~1-2% slower than PAX-minimal (minmax overhead)'
\echo '  3. Each bloom filter should add ~3-5% overhead'
\echo '  4. PAX-3-bloom should be ~9-15% slower than PAX-minimal'
\echo ''
\echo 'If PAX-minimal is still slower than AOCO:'
\echo '  → PAX write path has inherent inefficiency beyond bloom filters'
\echo '  → Investigate: auxiliary table writes, protobuf serialization, file creation'
\echo ''
\echo 'Check the timing output above to identify the overhead source.'
\echo ''

\echo '===================================================='
\echo 'Investigation complete!'
\echo '===================================================='
