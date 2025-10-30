--
-- Phase 6: Optimize PAX with Z-order Clustering
-- Applies Z-order clustering to PAX (clustered) variant
--

\timing on

\echo '===================================================='
\echo 'E-commerce Clickstream - Phase 6: Optimize PAX'
\echo '===================================================='
\echo ''

-- =====================================================
-- Memory Configuration for Clustering
-- =====================================================

\echo 'Setting memory configuration for Z-order clustering...'

-- Calculate required memory
SELECT * FROM ecommerce_validation.calculate_cluster_memory('ecommerce', 'clickstream_pax');

-- Set maintenance_work_mem for clustering (2GB for 10M rows)
SET maintenance_work_mem = '2GB';

\echo '  ✓ maintenance_work_mem set to 2GB'
\echo ''

-- =====================================================
-- Apply Z-order Clustering
-- =====================================================

\echo 'Applying Z-order clustering to PAX variant...'
\echo '  (This will take 3-5 minutes for 10M rows)'
\echo ''

CLUSTER ecommerce.clickstream_pax;

\echo '  ✓ Z-order clustering complete'
\echo ''

-- =====================================================
-- Post-Clustering Analysis
-- =====================================================

\echo 'Post-clustering storage analysis:'
\echo ''

SELECT * FROM ecommerce_validation.detect_storage_bloat(
    'ecommerce',
    'clickstream_aoco',
    'clickstream_pax_nocluster',
    'clickstream_pax'
);

\echo ''
\echo '===================================================='
\echo 'PAX optimization complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 7 - Run benchmark queries'
\echo 'Run: psql -f sql/07_run_queries.sql'
\echo ''
