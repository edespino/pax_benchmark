--
-- Phase 4: Create Table Variants
-- Creates 4 variants: AO, AOCO, PAX (clustered), PAX (no-cluster)
-- Configuration based on cardinality analysis from Phase 2
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 4: Create Table Variants'
\echo '===================================================='
\echo ''

-- =====================================================
-- Variant 1: AO (Row-Oriented Baseline)
-- =====================================================

\echo 'Creating Variant 1: AO (row-oriented baseline)...'

DROP TABLE IF EXISTS cdr.cdr_ao CASCADE;

CREATE TABLE cdr.cdr_ao (
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
) WITH (
    appendonly=true,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (call_id);

\echo '  ✓ cdr.cdr_ao created (AO row-oriented)'
\echo ''

-- =====================================================
-- Variant 2: AOCO (Column-Oriented Baseline)
-- =====================================================

\echo 'Creating Variant 2: AOCO (column-oriented baseline)...'

DROP TABLE IF EXISTS cdr.cdr_aoco CASCADE;

CREATE TABLE cdr.cdr_aoco (
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
) WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (call_id);

\echo '  ✓ cdr.cdr_aoco created (AOCO column-oriented)'
\echo ''

-- =====================================================
-- Variant 3: PAX with Clustering (Full Features)
-- Based on cardinality analysis - SAFE configuration
-- =====================================================

\echo 'Creating Variant 3: PAX with clustering (full features)...'

DROP TABLE IF EXISTS cdr.cdr_pax CASCADE;

CREATE TABLE cdr.cdr_pax (
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
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- Bloom filters: VALIDATED (cardinality >= 1000)
    -- Limited to 3 columns per October 2025 lessons
    -- call_id: ~1M unique ✅
    -- caller_number: ~1M unique ✅
    -- callee_number: ~1M unique ✅
    -- cell_tower_id: ~10K unique (excluded - already have 3)
    bloomfilter_columns='call_id,caller_number,callee_number',

    -- MinMax statistics: Low overhead, use liberally
    minmax_columns='call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code,billing_amount',

    -- Z-order clustering: Date + Location correlation
    -- NOTE: TIMESTAMP not supported for Z-order in current PAX version
    -- Using call_date (DATE type) instead
    cluster_type='zorder',
    cluster_columns='call_date,cell_tower_id',

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ cdr.cdr_pax created (PAX with Z-order clustering)'
\echo ''

-- =====================================================
-- Variant 4: PAX without Clustering (Control Group)
-- Same bloom/minmax config, NO clustering
-- =====================================================

\echo 'Creating Variant 4: PAX no-cluster (control group)...'

DROP TABLE IF EXISTS cdr.cdr_pax_nocluster CASCADE;

CREATE TABLE cdr.cdr_pax_nocluster (
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
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- Same bloom/minmax as cdr_pax
    bloomfilter_columns='call_id,caller_number,callee_number',
    minmax_columns='call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code,billing_amount',

    -- NO clustering (control group)
    -- cluster_type and cluster_columns intentionally omitted

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ cdr.cdr_pax_nocluster created (PAX without clustering)'
\echo ''

-- =====================================================
-- Summary
-- =====================================================

\echo '===================================================='
\echo 'All table variants created!'
\echo '===================================================='
\echo ''
\echo 'Variants:'
\echo '  1. cdr.cdr_ao (row-oriented baseline)'
\echo '  2. cdr.cdr_aoco (column-oriented baseline)'
\echo '  3. cdr.cdr_pax (PAX with Z-order clustering)'
\echo '  4. cdr.cdr_pax_nocluster (PAX without clustering)'
\echo ''
\echo 'PAX Configuration:'
\echo '  ✅ Bloom filters: 3 columns (call_id, caller_number, callee_number)'
\echo '  ✅ MinMax: 9 columns (comprehensive coverage)'
\echo '  ✅ Z-order clustering: call_timestamp + cell_tower_id'
\echo '  ✅ All validated via cardinality analysis (Phase 2)'
\echo ''
\echo 'Next: Phase 5 - Create indexes (for Phase 2 testing)'
