--
-- Phase 4d: Create Table Variants (INCLUDING HEAP)
-- Creates 5 variants: AO, AOCO, PAX (clustered), PAX (no-cluster), HEAP
-- Configuration based on cardinality analysis from Phase 2
--
-- ⚠️  WARNING: HEAP variant for ACADEMIC TESTING ONLY
-- ⚠️  NOT recommended for 50M rows in production (bloat expected)
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 4d: Create Table Variants (WITH HEAP)'
\echo '===================================================='
\echo ''
\echo '⚠️  WARNING: HEAP variant included for academic comparison'
\echo '⚠️  Expected: HEAP will show bloat and VACUUM overhead at scale'
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
    -- Limited to 2-3 columns per October 2025 lessons
    -- call_id: 1 unique ❌ (REMOVED - causes storage bloat)
    -- caller_number: ~2M unique ✅
    -- callee_number: ~2M unique ✅
    -- cell_tower_id: ~10K unique (could add if needed)
    bloomfilter_columns='caller_number,callee_number',

    -- MinMax statistics: Low overhead, use liberally
    minmax_columns='call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code,billing_amount',

    -- Z-order clustering: Time + Location correlation
    -- Using call_hour (24 distinct values) for true 2D Z-order benefits
    -- Nov 2025 optimization: call_hour vs call_date = -3.1% storage, -12% vs degenerate call_date
    cluster_type='zorder',
    cluster_columns='call_hour,cell_tower_id',

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

    -- Same bloom/minmax as cdr_pax (call_id removed - only 1 distinct value)
    bloomfilter_columns='caller_number,callee_number',
    minmax_columns='call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code,billing_amount',

    -- NO clustering (control group)
    -- cluster_type and cluster_columns intentionally omitted

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ cdr.cdr_pax_nocluster created (PAX without clustering)'
\echo ''

-- =====================================================
-- Variant 5: HEAP (Standard PostgreSQL Storage)
-- ⚠️  ACADEMIC TESTING ONLY - NOT FOR PRODUCTION
-- =====================================================

\echo 'Creating Variant 5: HEAP (standard PostgreSQL storage)...'
\echo '  ⚠️  WARNING: For academic comparison only'
\echo '  ⚠️  Expected behavior: Fast initial writes, catastrophic bloat at scale'
\echo ''

DROP TABLE IF EXISTS cdr.cdr_heap CASCADE;

CREATE TABLE cdr.cdr_heap (
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
) DISTRIBUTED BY (call_id);
-- NO WITH clause = HEAP storage (PostgreSQL default)

\echo '  ✓ cdr.cdr_heap created (standard PostgreSQL HEAP)'
\echo '  ⚠️  Expect table bloat and VACUUM overhead during Phase 2'
\echo ''

-- =====================================================
-- Summary
-- =====================================================

\echo '===================================================='
\echo 'All table variants created (INCLUDING HEAP)!'
\echo '===================================================='
\echo ''
\echo 'Variants:'
\echo '  1. cdr.cdr_ao (row-oriented baseline)'
\echo '  2. cdr.cdr_aoco (column-oriented baseline)'
\echo '  3. cdr.cdr_pax (PAX with Z-order clustering)'
\echo '  4. cdr.cdr_pax_nocluster (PAX without clustering)'
\echo '  5. cdr.cdr_heap (HEAP - academic testing only ⚠️ )'
\echo ''
\echo 'PAX Configuration:'
\echo '  ✅ Bloom filters: 2 columns (caller_number, callee_number) - high cardinality'
\echo '  ✅ MinMax: 9 columns (comprehensive coverage)'
\echo '  ✅ Z-order clustering: call_hour + cell_tower_id (Nov 2025 optimized)'
\echo '  ✅ All validated via cardinality analysis (Phase 2)'
\echo ''
\echo 'HEAP Warning:'
\echo '  ⚠️  HEAP variant for academic comparison only'
\echo '  ⚠️  Expected: Fast Phase 1 writes, but catastrophic bloat in Phase 2'
\echo '  ⚠️  Will demonstrate WHY append-only storage (AO/AOCO/PAX) exists'
\echo ''
\echo 'Next: Phase 5 - Create indexes (for Phase 2 testing)'
