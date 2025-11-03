--
-- Phase 5b: Create Indexes on Partitioned Tables (for Phase 2 Testing)
-- Creates indexes on partitioned variants for realistic production scenario
-- Phase 2 will measure INSERT throughput WITH index maintenance overhead
--
-- Index Strategy for Partitioned Tables:
--   - Create index on parent table → automatically creates on all child partitions
--   - 5 indexes per variant × 4 variants = 20 parent index definitions
--   - Each parent index creates 24 child indexes (one per partition)
--   - Total: 480 indexes (20 × 24), but each index is 24x smaller
--   - Expected benefit: 18-22% faster index maintenance (O(n log n) reduction)
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 5b: Create Indexes (Partitioned)'
\echo '===================================================='
\echo ''
\echo 'NOTE: This phase is for Phase 2 testing ONLY'
\echo '      Phase 1 tests INSERT performance WITHOUT indexes'
\echo ''
\echo 'Creating indexes on partitioned parent tables...'
\echo '  (Each index will cascade to 24 child partitions automatically)'
\echo ''

-- =====================================================
-- Indexes for AO Partitioned Variant
-- =====================================================

\echo 'Creating indexes for cdr.cdr_ao_partitioned...'

CREATE INDEX idx_cdr_ao_part_timestamp ON cdr.cdr_ao_partitioned (call_timestamp);
CREATE INDEX idx_cdr_ao_part_caller ON cdr.cdr_ao_partitioned (caller_number);
CREATE INDEX idx_cdr_ao_part_callee ON cdr.cdr_ao_partitioned (callee_number);
CREATE INDEX idx_cdr_ao_part_tower ON cdr.cdr_ao_partitioned (cell_tower_id);
CREATE INDEX idx_cdr_ao_part_date ON cdr.cdr_ao_partitioned (call_date);

\echo '  ✓ 5 indexes created on parent (120 total: 5 × 24 partitions)'

-- =====================================================
-- Indexes for AOCO Partitioned Variant
-- =====================================================

\echo 'Creating indexes for cdr.cdr_aoco_partitioned...'

CREATE INDEX idx_cdr_aoco_part_timestamp ON cdr.cdr_aoco_partitioned (call_timestamp);
CREATE INDEX idx_cdr_aoco_part_caller ON cdr.cdr_aoco_partitioned (caller_number);
CREATE INDEX idx_cdr_aoco_part_callee ON cdr.cdr_aoco_partitioned (callee_number);
CREATE INDEX idx_cdr_aoco_part_tower ON cdr.cdr_aoco_partitioned (cell_tower_id);
CREATE INDEX idx_cdr_aoco_part_date ON cdr.cdr_aoco_partitioned (call_date);

\echo '  ✓ 5 indexes created on parent (120 total: 5 × 24 partitions)'

-- =====================================================
-- Indexes for PAX Partitioned (Clustered) Variant
-- =====================================================

\echo 'Creating indexes for cdr.cdr_pax_partitioned...'

CREATE INDEX idx_cdr_pax_part_timestamp ON cdr.cdr_pax_partitioned (call_timestamp);
CREATE INDEX idx_cdr_pax_part_caller ON cdr.cdr_pax_partitioned (caller_number);
CREATE INDEX idx_cdr_pax_part_callee ON cdr.cdr_pax_partitioned (callee_number);
CREATE INDEX idx_cdr_pax_part_tower ON cdr.cdr_pax_partitioned (cell_tower_id);
CREATE INDEX idx_cdr_pax_part_date ON cdr.cdr_pax_partitioned (call_date);

\echo '  ✓ 5 indexes created on parent (120 total: 5 × 24 partitions)'

-- =====================================================
-- Indexes for PAX Partitioned (No-Cluster) Variant
-- =====================================================

\echo 'Creating indexes for cdr.cdr_pax_nocluster_partitioned...'

CREATE INDEX idx_cdr_pax_nocluster_part_timestamp ON cdr.cdr_pax_nocluster_partitioned (call_timestamp);
CREATE INDEX idx_cdr_pax_nocluster_part_caller ON cdr.cdr_pax_nocluster_partitioned (caller_number);
CREATE INDEX idx_cdr_pax_nocluster_part_callee ON cdr.cdr_pax_nocluster_partitioned (callee_number);
CREATE INDEX idx_cdr_pax_nocluster_part_tower ON cdr.cdr_pax_nocluster_partitioned (cell_tower_id);
CREATE INDEX idx_cdr_pax_nocluster_part_date ON cdr.cdr_pax_nocluster_partitioned (call_date);

\echo '  ✓ 5 indexes created on parent (120 total: 5 × 24 partitions)'

-- =====================================================
-- Analyze Partitioned Tables
-- =====================================================

\echo ''
\echo 'Analyzing partitioned tables...'

ANALYZE cdr.cdr_ao_partitioned;
ANALYZE cdr.cdr_aoco_partitioned;
ANALYZE cdr.cdr_pax_partitioned;
ANALYZE cdr.cdr_pax_nocluster_partitioned;

\echo '  ✓ Analysis complete'

-- =====================================================
-- Summary
-- =====================================================

\echo ''
\echo '===================================================='
\echo 'Index creation complete!'
\echo '===================================================='
\echo ''
\echo 'Indexes created on each partitioned variant:'
\echo '  • call_timestamp (range queries)'
\echo '  • caller_number (equality lookups)'
\echo '  • callee_number (equality lookups)'
\echo '  • cell_tower_id (filtering)'
\echo '  • call_date (range queries + partition pruning)'
\echo ''
\echo 'Index distribution:'
\echo '  • Parent index definitions: 20 (5 per variant × 4 variants)'
\echo '  • Child partition indexes: 480 (20 × 24 partitions)'
\echo '  • Rows per partition index: ~1.74M (vs 41.81M monolithic)'
\echo '  • Index size reduction: 24x smaller per partition'
\echo ''
\echo 'Expected benefits:'
\echo '  • Index maintenance: 18-22% faster (O(n log n) reduction)'
\echo '  • Partition pruning: date-range queries scan fewer partitions'
\echo '  • Phase 2 speedup: 18-35% vs monolithic (target)'
\echo ''
\echo 'Next: Phase 6b/7b - Streaming INSERTs (partitioned variants)'
