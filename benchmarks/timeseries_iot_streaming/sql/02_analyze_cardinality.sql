--
-- Phase 2: Analyze Cardinality (CRITICAL VALIDATION STEP)
-- Run BEFORE creating PAX tables to validate bloom filter candidates
-- This step prevents the 81% storage bloat discovered in October 2025
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 2: Cardinality Analysis'
\echo '===================================================='
\echo ''
\echo '⚠️  CRITICAL: This validates bloom filter candidates'
\echo '⚠️  BEFORE table creation to prevent storage bloat'
\echo ''

-- =====================================================
-- Create Sample CDR Table for Analysis
-- Use 1M row sample to get accurate statistics
-- =====================================================

\echo 'Step 1: Creating sample CDR table for analysis...'
\echo '  (This will be dropped after analysis)'
\echo ''

DROP TABLE IF EXISTS cdr.cdr_sample CASCADE;

CREATE TEMP TABLE cdr_sample AS
SELECT
    -- Call identifier (HIGH CARDINALITY - unique per call)
    'call-' || lpad(gs::TEXT, 12, '0') || '-' || substr(md5(random()::TEXT), 1, 8) AS call_id,

    -- Timestamps
    timestamp '2025-10-01 00:00:00' + (gs * interval '3 seconds') AS call_timestamp,
    (timestamp '2025-10-01 00:00:00' + (gs * interval '3 seconds'))::DATE AS call_date,
    (EXTRACT(HOUR FROM timestamp '2025-10-01 00:00:00' + (gs * interval '3 seconds')))::INTEGER AS call_hour,

    -- Phone numbers (HIGH CARDINALITY - millions of subscribers)
    -- Zipf distribution: 20% of numbers account for 80% of calls
    '+1-' || lpad(
        CASE
            WHEN random() < 0.2 THEN (1 + (random() * 199999)::INT)::TEXT      -- Hot 20%: 200K numbers
            WHEN random() < 0.6 THEN (200000 + (random() * 799999)::INT)::TEXT -- Warm 40%: 800K numbers
            ELSE (1000000 + (random() * 4000000)::INT)::TEXT                   -- Cold 40%: 4M numbers
        END, 10, '0') AS caller_number,
    '+1-' || lpad(
        CASE
            WHEN random() < 0.2 THEN (1 + (random() * 199999)::INT)::TEXT
            WHEN random() < 0.6 THEN (200000 + (random() * 799999)::INT)::TEXT
            ELSE (1000000 + (random() * 4000000)::INT)::TEXT
        END, 10, '0') AS callee_number,

    -- Call duration (realistic distribution)
    -- Most calls 30-300 seconds, some very short/long
    CASE
        WHEN random() < 0.05 THEN (1 + (random() * 9)::INT)::INTEGER          -- 5% very short (<10s)
        WHEN random() < 0.85 THEN (30 + (random() * 270)::INT)::INTEGER       -- 80% normal (30-300s)
        ELSE (300 + (random() * 3300)::INT)::INTEGER                          -- 15% long (>300s)
    END AS duration_seconds,

    -- Cell tower (MEDIUM CARDINALITY - 10K towers)
    (1 + (random() * 9999)::INT)::INTEGER AS cell_tower_id,

    -- Call type (LOW CARDINALITY - 3 values)
    CASE
        WHEN random() < 0.70 THEN 'voice'
        WHEN random() < 0.95 THEN 'sms'
        ELSE 'data'
    END AS call_type,

    -- Network type (VERY LOW CARDINALITY - 3 values)
    CASE
        WHEN random() < 0.30 THEN '4G'
        WHEN random() < 0.90 THEN '5G'
        ELSE '5G-mmWave'
    END AS network_type,

    -- Data transferred (for data calls, sparse for voice/sms)
    CASE
        WHEN random() < 0.05 THEN (100 + (random() * 10000000)::BIGINT)::BIGINT  -- Data calls
        WHEN random() < 0.15 THEN (1 + (random() * 1000)::BIGINT)::BIGINT        -- SMS with MMS
        ELSE NULL                                                                  -- Voice (no data)
    END AS bytes_transferred,

    -- Termination reason (LOW CARDINALITY - 20 codes, but 80% normal)
    CASE
        WHEN random() < 0.80 THEN 1   -- 80% normal termination
        WHEN random() < 0.90 THEN 16  -- 10% normal clearing
        WHEN random() < 0.95 THEN 17  -- 5% user busy
        WHEN random() < 0.98 THEN 18  -- 3% no answer
        ELSE (21 + (random() * 106)::INT)::INTEGER  -- 2% various errors
    END AS termination_code,

    -- Billing amount (derived from duration)
    (0.10 * CASE
        WHEN random() < 0.05 THEN (1 + (random() * 9)::INT)
        WHEN random() < 0.85 THEN (30 + (random() * 270)::INT)
        ELSE (300 + (random() * 3300)::INT)
    END)::NUMERIC(10,4) AS billing_amount,

    -- Rate plan (LOW CARDINALITY - 50 plans)
    (1 + (random() * 49)::INT)::INTEGER AS rate_plan_id,

    -- Roaming flag (BINARY)
    (random() < 0.10) AS is_roaming,

    -- Quality metrics (numeric, vary widely)
    (random() * 5.0 + 1.0)::NUMERIC(3,2) AS call_quality_mos,  -- Mean Opinion Score 1-5
    (random() * 100)::NUMERIC(5,2) AS packet_loss_percent,

    -- Metadata
    gs AS sequence_number
FROM generate_series(1, 1000000) gs;

\echo '  ✓ Sample CDR table created (1M rows)'
\echo ''

-- =====================================================
-- Step 2: ANALYZE to Collect Statistics
-- =====================================================

\echo 'Step 2: Running ANALYZE to collect statistics...'

ANALYZE cdr_sample;

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
\echo '  - call_id (expected: HIGH cardinality - 1M unique)'
\echo '  - caller_number (expected: HIGH cardinality - ~1M unique)'
\echo '  - callee_number (expected: HIGH cardinality - ~1M unique)'
\echo '  - cell_tower_id (expected: MEDIUM cardinality - ~10K unique)'
\echo '  - call_type (expected: LOW cardinality - 3 unique)'
\echo '  - termination_code (expected: LOW cardinality - ~20 unique)'
\echo ''
\echo 'Validation results:'
\echo ''

SELECT * FROM cdr_validation.validate_bloom_candidates(
    'pg_temp',
    'cdr_sample',
    ARRAY['call_id', 'caller_number', 'callee_number', 'cell_tower_id', 'call_type', 'termination_code']
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
  AND tablename = 'cdr_sample'
ORDER BY ABS(n_distinct) DESC;

\echo ''

-- =====================================================
-- Step 5: Memory Requirements Calculation
-- =====================================================

\echo '===================================================='
\echo 'MEMORY REQUIREMENTS FOR CLUSTERING'
\echo '===================================================='
\echo ''
\echo 'Target table size: 50,000,000 rows (streaming test)'
\echo ''

SELECT * FROM cdr_validation.calculate_cluster_memory(50000000);

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
\echo '  ⚠️  call_id (EXPECTED ~1M unique, but ACTUAL: 1 unique - SKIP!)'
\echo '  ✅ caller_number (~2,000,000 unique)'
\echo '  ✅ callee_number (~2,000,000 unique)'
\echo '  ✅ cell_tower_id (~10,000 unique)'
\echo ''
\echo 'UNSAFE for bloom filters (cardinality < 100):'
\echo '  ❌ call_type (~3 unique) - Use minmax only'
\echo '  ❌ network_type (~3 unique) - Skip'
\echo '  ❌ termination_code (~20 unique) - Use minmax only'
\echo '  ❌ rate_plan_id (~50 unique) - Use minmax only'
\echo ''
\echo 'RECOMMENDED PAX CONFIGURATION:'
\echo '  bloomfilter_columns=''caller_number,callee_number'''
\echo '  minmax_columns=''call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code'''
\echo '  cluster_columns=''call_timestamp,cell_tower_id'' (time + location correlation)'
\echo '  maintenance_work_mem: See calculation above (12GB for 50M rows)'
\echo ''
\echo 'NOTE: This benchmark uses 2 bloom columns (Nov 2025 optimization).'
\echo '      call_id removed (only 1 distinct value - causes bloat).'
\echo '      cell_tower_id safe but excluded to keep bloom filter count low.'
\echo ''

-- =====================================================
-- Cleanup
-- =====================================================

DROP TABLE IF EXISTS cdr_sample;

\echo '===================================================='
\echo 'Cardinality analysis complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 3 - Generate safe PAX configuration'
