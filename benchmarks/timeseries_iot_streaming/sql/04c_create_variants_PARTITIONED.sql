--
-- Phase 4c: Create Partitioned Table Variants
-- Creates 4 variants with RANGE partitioning on call_date (24 partitions each)
-- Based on optimized configuration from Phase 2 and Phase 4
--
-- Partitioning Strategy:
--   - 24 daily partitions (one per hour of simulation, mapped to dates)
--   - Hour 0 → 2024-01-01, Hour 1 → 2024-01-02, ..., Hour 23 → 2024-01-24
--   - Each partition: ~1.74M rows (41.81M ÷ 24)
--   - Expected benefit: 18-35% Phase 2 speedup from smaller indexes
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 4c: Create Partitioned Variants'
\echo '===================================================='
\echo ''
\echo 'Creating 4 partitioned table variants with 24 daily partitions each:'
\echo '  - cdr.cdr_ao_partitioned (24 partitions)'
\echo '  - cdr.cdr_aoco_partitioned (24 partitions)'
\echo '  - cdr.cdr_pax_partitioned (24 partitions)'
\echo '  - cdr.cdr_pax_nocluster_partitioned (24 partitions)'
\echo ''
\echo 'Total: 96 partition tables (4 variants × 24 partitions)'
\echo ''

-- =====================================================
-- Variant 1: AO Partitioned (Row-Oriented Baseline)
-- =====================================================

\echo 'Creating Variant 1: AO Partitioned (row-oriented baseline)...'

DROP TABLE IF EXISTS cdr.cdr_ao_partitioned CASCADE;

CREATE TABLE cdr.cdr_ao_partitioned (
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
) PARTITION BY RANGE (call_date)
WITH (
    appendonly=true,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (call_id);

\echo '  ✓ Parent table created: cdr.cdr_ao_partitioned'

-- Create 24 daily partitions
DO $$
DECLARE
    day_offset INTEGER;
    part_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    FOR day_offset IN 0..23 LOOP
        part_name := 'cdr_ao_part_day' || lpad(day_offset::TEXT, 2, '0');
        start_date := '2024-01-01'::DATE + day_offset;
        end_date := start_date + 1;

        EXECUTE format(
            'CREATE TABLE cdr.%I PARTITION OF cdr.cdr_ao_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            part_name, start_date, end_date
        );
    END LOOP;
END $$;

\echo '  ✓ Created 24 partitions (day00 through day23)'
\echo ''

-- =====================================================
-- Variant 2: AOCO Partitioned (Column-Oriented Baseline)
-- =====================================================

\echo 'Creating Variant 2: AOCO Partitioned (column-oriented baseline)...'

DROP TABLE IF EXISTS cdr.cdr_aoco_partitioned CASCADE;

CREATE TABLE cdr.cdr_aoco_partitioned (
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
) PARTITION BY RANGE (call_date)
WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (call_id);

\echo '  ✓ Parent table created: cdr.cdr_aoco_partitioned'

-- Create 24 daily partitions
DO $$
DECLARE
    day_offset INTEGER;
    part_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    FOR day_offset IN 0..23 LOOP
        part_name := 'cdr_aoco_part_day' || lpad(day_offset::TEXT, 2, '0');
        start_date := '2024-01-01'::DATE + day_offset;
        end_date := start_date + 1;

        EXECUTE format(
            'CREATE TABLE cdr.%I PARTITION OF cdr.cdr_aoco_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            part_name, start_date, end_date
        );
    END LOOP;
END $$;

\echo '  ✓ Created 24 partitions (day00 through day23)'
\echo ''

-- =====================================================
-- Variant 3: PAX Partitioned with Clustering (Full Features)
-- Based on Nov 2025 optimized configuration
-- =====================================================

\echo 'Creating Variant 3: PAX Partitioned with clustering (full features)...'

DROP TABLE IF EXISTS cdr.cdr_pax_partitioned CASCADE;

CREATE TABLE cdr.cdr_pax_partitioned (
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
) PARTITION BY RANGE (call_date)
USING pax WITH (
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- Bloom filters: VALIDATED (Nov 2025 optimized - 2 columns only)
    -- call_id removed (only 1 distinct value)
    -- caller_number: ~2M unique ✅
    -- callee_number: ~2M unique ✅
    bloomfilter_columns='caller_number,callee_number',

    -- MinMax statistics: Low overhead, use liberally
    minmax_columns='call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code,billing_amount',

    -- Z-order clustering: Time + Location correlation
    -- Nov 2025 optimization: call_hour (24 values) vs call_date (1 value) = -3.1% storage
    cluster_type='zorder',
    cluster_columns='call_hour,cell_tower_id',

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ Parent table created: cdr.cdr_pax_partitioned'

-- Create 24 daily partitions
DO $$
DECLARE
    day_offset INTEGER;
    part_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    FOR day_offset IN 0..23 LOOP
        part_name := 'cdr_pax_part_day' || lpad(day_offset::TEXT, 2, '0');
        start_date := '2024-01-01'::DATE + day_offset;
        end_date := start_date + 1;

        EXECUTE format(
            'CREATE TABLE cdr.%I PARTITION OF cdr.cdr_pax_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            part_name, start_date, end_date
        );
    END LOOP;
END $$;

\echo '  ✓ Created 24 partitions (day00 through day23)'
\echo ''

-- =====================================================
-- Variant 4: PAX Partitioned without Clustering (Control Group)
-- Same bloom/minmax config as PAX, NO clustering
-- =====================================================

\echo 'Creating Variant 4: PAX Partitioned no-cluster (control group)...'

DROP TABLE IF EXISTS cdr.cdr_pax_nocluster_partitioned CASCADE;

CREATE TABLE cdr.cdr_pax_nocluster_partitioned (
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
) PARTITION BY RANGE (call_date)
USING pax WITH (
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- Same bloom/minmax as cdr_pax_partitioned (Nov 2025 optimized)
    bloomfilter_columns='caller_number,callee_number',
    minmax_columns='call_date,call_hour,caller_number,callee_number,cell_tower_id,duration_seconds,call_type,termination_code,billing_amount',

    -- NO clustering (control group)
    -- cluster_type and cluster_columns intentionally omitted

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (call_id);

\echo '  ✓ Parent table created: cdr.cdr_pax_nocluster_partitioned'

-- Create 24 daily partitions
DO $$
DECLARE
    day_offset INTEGER;
    part_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    FOR day_offset IN 0..23 LOOP
        part_name := 'cdr_pax_nocluster_part_day' || lpad(day_offset::TEXT, 2, '0');
        start_date := '2024-01-01'::DATE + day_offset;
        end_date := start_date + 1;

        EXECUTE format(
            'CREATE TABLE cdr.%I PARTITION OF cdr.cdr_pax_nocluster_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            part_name, start_date, end_date
        );
    END LOOP;
END $$;

\echo '  ✓ Created 24 partitions (day00 through day23)'
\echo ''

-- =====================================================
-- Summary
-- =====================================================

\echo '===================================================='
\echo 'All partitioned table variants created!'
\echo '===================================================='
\echo ''
\echo 'Variants created (96 total partition tables):'
\echo '  1. cdr.cdr_ao_partitioned (24 partitions)'
\echo '  2. cdr.cdr_aoco_partitioned (24 partitions)'
\echo '  3. cdr.cdr_pax_partitioned (24 partitions with Z-order clustering)'
\echo '  4. cdr.cdr_pax_nocluster_partitioned (24 partitions without clustering)'
\echo ''
\echo 'Partitioning strategy:'
\echo '  • Partition key: call_date (RANGE)'
\echo '  • Date range: 2024-01-01 through 2024-01-25 (24 days)'
\echo '  • Rows per partition: ~1.74M (vs 41.81M monolithic)'
\echo '  • Index size reduction: 24x smaller per partition'
\echo ''
\echo 'PAX Configuration (Nov 2025 optimized):'
\echo '  ✅ Bloom filters: 2 columns (caller_number, callee_number) - high cardinality'
\echo '  ✅ MinMax: 9 columns (comprehensive coverage)'
\echo '  ✅ Z-order clustering: call_hour + cell_tower_id (-3.1% storage vs no-cluster)'
\echo '  ✅ All validated via cardinality analysis'
\echo ''
\echo 'Expected benefits:'
\echo '  • Phase 2 runtime: 18-35% faster (smaller index maintenance)'
\echo '  • Partition pruning: 20-30% query speedup on date-range queries'
\echo '  • Index overhead: O(n log n) reduction per partition'
\echo ''
\echo 'Next: Phase 5b - Create indexes on partitioned tables'
