--
-- Phase 5: Create Indexes (for Phase 2 Testing)
-- Creates indexes on all variants for realistic production scenario
-- Phase 2 will measure INSERT throughput WITH index maintenance overhead
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 5: Create Indexes'
\echo '===================================================='
\echo ''
\echo 'NOTE: This phase is for Phase 2 testing ONLY'
\echo '      Phase 1 tests INSERT performance WITHOUT indexes'
\echo ''

-- =====================================================
-- Indexes for AO Variant
-- =====================================================

\echo 'Creating indexes for cdr.cdr_ao...'

CREATE INDEX idx_cdr_ao_timestamp ON cdr.cdr_ao (call_timestamp);
CREATE INDEX idx_cdr_ao_caller ON cdr.cdr_ao (caller_number);
CREATE INDEX idx_cdr_ao_callee ON cdr.cdr_ao (callee_number);
CREATE INDEX idx_cdr_ao_tower ON cdr.cdr_ao (cell_tower_id);
CREATE INDEX idx_cdr_ao_date ON cdr.cdr_ao (call_date);

\echo '  ✓ 5 indexes created for cdr_ao'

-- =====================================================
-- Indexes for AOCO Variant
-- =====================================================

\echo 'Creating indexes for cdr.cdr_aoco...'

CREATE INDEX idx_cdr_aoco_timestamp ON cdr.cdr_aoco (call_timestamp);
CREATE INDEX idx_cdr_aoco_caller ON cdr.cdr_aoco (caller_number);
CREATE INDEX idx_cdr_aoco_callee ON cdr.cdr_aoco (callee_number);
CREATE INDEX idx_cdr_aoco_tower ON cdr.cdr_aoco (cell_tower_id);
CREATE INDEX idx_cdr_aoco_date ON cdr.cdr_aoco (call_date);

\echo '  ✓ 5 indexes created for cdr_aoco'

-- =====================================================
-- Indexes for PAX (Clustered) Variant
-- =====================================================

\echo 'Creating indexes for cdr.cdr_pax...'

CREATE INDEX idx_cdr_pax_timestamp ON cdr.cdr_pax (call_timestamp);
CREATE INDEX idx_cdr_pax_caller ON cdr.cdr_pax (caller_number);
CREATE INDEX idx_cdr_pax_callee ON cdr.cdr_pax (callee_number);
CREATE INDEX idx_cdr_pax_tower ON cdr.cdr_pax (cell_tower_id);
CREATE INDEX idx_cdr_pax_date ON cdr.cdr_pax (call_date);

\echo '  ✓ 5 indexes created for cdr_pax'

-- =====================================================
-- Indexes for PAX (No-Cluster) Variant
-- =====================================================

\echo 'Creating indexes for cdr.cdr_pax_nocluster...'

CREATE INDEX idx_cdr_pax_nocluster_timestamp ON cdr.cdr_pax_nocluster (call_timestamp);
CREATE INDEX idx_cdr_pax_nocluster_caller ON cdr.cdr_pax_nocluster (caller_number);
CREATE INDEX idx_cdr_pax_nocluster_callee ON cdr.cdr_pax_nocluster (callee_number);
CREATE INDEX idx_cdr_pax_nocluster_tower ON cdr.cdr_pax_nocluster (cell_tower_id);
CREATE INDEX idx_cdr_pax_nocluster_date ON cdr.cdr_pax_nocluster (call_date);

\echo '  ✓ 5 indexes created for cdr_pax_nocluster'

-- =====================================================
-- Analyze Tables
-- =====================================================

\echo ''
\echo 'Analyzing tables...'

ANALYZE cdr.cdr_ao;
ANALYZE cdr.cdr_aoco;
ANALYZE cdr.cdr_pax;
ANALYZE cdr.cdr_pax_nocluster;

\echo '  ✓ Analysis complete'

-- =====================================================
-- Summary
-- =====================================================

\echo ''
\echo '===================================================='
\echo 'Index creation complete!'
\echo '===================================================='
\echo ''
\echo 'Indexes created on each variant:'
\echo '  • call_timestamp (range queries)'
\echo '  • caller_number (equality lookups)'
\echo '  • callee_number (equality lookups)'
\echo '  • cell_tower_id (filtering)'
\echo '  • call_date (range queries)'
\echo ''
\echo 'Total: 20 indexes (5 per variant × 4 variants)'
\echo ''
\echo 'Next: Phase 6 - Streaming INSERTs (no indexes) OR'
\echo '      Phase 7 - Streaming INSERTs (with indexes)'
