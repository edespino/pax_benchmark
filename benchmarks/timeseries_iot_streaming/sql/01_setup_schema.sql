--
-- Phase 1: Setup Telecom CDR Schema
-- Creates dimension and fact tables for Call Detail Records
-- Designed for streaming INSERT performance testing
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 1: Setup CDR Schema'
\echo '===================================================='
\echo ''

-- Create main schema
DROP SCHEMA IF EXISTS cdr CASCADE;
CREATE SCHEMA cdr;

\echo 'Schema created: cdr'
\echo ''

-- =====================================================
-- Dimension Table: Cell Towers
-- Represents 10K cell tower locations
-- =====================================================

\echo 'Creating dimension table: cdr.cell_towers...'

CREATE TABLE cdr.cell_towers (
    cell_tower_id INTEGER PRIMARY KEY,
    tower_name VARCHAR(100) NOT NULL,
    location_code VARCHAR(20),           -- 'NYC-MAN-001'
    latitude NUMERIC(9,6),
    longitude NUMERIC(9,6),
    coverage_radius_km NUMERIC(5,2),
    network_type VARCHAR(10),            -- '4G', '5G'
    capacity_users INTEGER,              -- Max concurrent users
    install_date DATE,
    status VARCHAR(20) DEFAULT 'active', -- 'active', 'maintenance', 'offline'
    carrier VARCHAR(50)                  -- 'AT&T', 'Verizon', 'T-Mobile'
) DISTRIBUTED BY (cell_tower_id);

\echo '  ✓ cdr.cell_towers created'
\echo ''

-- =====================================================
-- Dimension Table: Rate Plans
-- Catalog of billing rate plans
-- =====================================================

\echo 'Creating dimension table: cdr.rate_plans...'

CREATE TABLE cdr.rate_plans (
    rate_plan_id INTEGER PRIMARY KEY,
    plan_name VARCHAR(100) NOT NULL,
    plan_type VARCHAR(20),               -- 'prepaid', 'postpaid', 'enterprise'
    base_monthly_fee NUMERIC(10,2),
    voice_rate_per_min NUMERIC(6,4),     -- $/minute
    sms_rate_per_message NUMERIC(6,4),
    data_rate_per_mb NUMERIC(8,6),       -- $/MB
    included_minutes INTEGER,
    included_sms INTEGER,
    included_data_mb INTEGER,
    overage_multiplier NUMERIC(3,2),     -- 1.5x for overages
    description TEXT
) DISTRIBUTED BY (rate_plan_id);

\echo '  ✓ cdr.rate_plans created'
\echo ''

-- =====================================================
-- Dimension Table: Termination Reasons
-- Lookup table for call termination causes
-- =====================================================

\echo 'Creating dimension table: cdr.termination_reasons...'

CREATE TABLE cdr.termination_reasons (
    termination_code INTEGER PRIMARY KEY,
    termination_reason VARCHAR(50) NOT NULL,
    category VARCHAR(20),                -- 'normal', 'error', 'network'
    billable BOOLEAN DEFAULT TRUE,
    description TEXT
) DISTRIBUTED BY (termination_code);

\echo '  ✓ cdr.termination_reasons created'
\echo ''

-- =====================================================
-- Populate Dimension Tables
-- =====================================================

\echo 'Populating dimension tables...'

-- Populate cell_towers (10K towers)
INSERT INTO cdr.cell_towers (
    cell_tower_id, tower_name, location_code,
    latitude, longitude, coverage_radius_km,
    network_type, capacity_users, install_date, status, carrier
)
SELECT
    gs AS cell_tower_id,
    'Tower-' || lpad(gs::TEXT, 5, '0') AS tower_name,
    CASE (gs % 5)
        WHEN 0 THEN 'NYC'
        WHEN 1 THEN 'LAX'
        WHEN 2 THEN 'CHI'
        WHEN 3 THEN 'HOU'
        ELSE 'SFO'
    END || '-' || lpad((gs % 100)::TEXT, 3, '0') AS location_code,
    -- Latitude range: 25.0 to 49.0 (US mainland)
    (25.0 + (random() * 24.0))::NUMERIC(9,6) AS latitude,
    -- Longitude range: -125.0 to -65.0 (US mainland)
    ((-125.0) + (random() * 60.0))::NUMERIC(9,6) AS longitude,
    -- Coverage radius: 0.5 to 15 km
    (0.5 + (random() * 14.5))::NUMERIC(5,2) AS coverage_radius_km,
    CASE
        WHEN gs <= 3000 THEN '4G'          -- 30% 4G
        WHEN gs <= 9000 THEN '5G'          -- 60% 5G
        ELSE '5G-mmWave'                   -- 10% 5G mmWave
    END AS network_type,
    -- Capacity: 500 to 5000 users
    (500 + (random() * 4500))::INTEGER AS capacity_users,
    DATE '2015-01-01' + (random() * 3650)::INTEGER AS install_date,
    CASE
        WHEN random() < 0.95 THEN 'active'
        WHEN random() < 0.98 THEN 'maintenance'
        ELSE 'offline'
    END AS status,
    CASE (gs % 4)
        WHEN 0 THEN 'AT&T'
        WHEN 1 THEN 'Verizon'
        WHEN 2 THEN 'T-Mobile'
        ELSE 'Sprint'
    END AS carrier
FROM generate_series(1, 10000) gs;

\echo '  ✓ Populated 10,000 cell towers'

-- Populate rate_plans (50 plans)
INSERT INTO cdr.rate_plans (
    rate_plan_id, plan_name, plan_type,
    base_monthly_fee, voice_rate_per_min, sms_rate_per_message, data_rate_per_mb,
    included_minutes, included_sms, included_data_mb,
    overage_multiplier, description
)
SELECT
    gs AS rate_plan_id,
    CASE
        WHEN gs <= 10 THEN 'Basic Plan ' || gs
        WHEN gs <= 30 THEN 'Premium Plan ' || gs
        ELSE 'Enterprise Plan ' || gs
    END AS plan_name,
    CASE
        WHEN gs <= 15 THEN 'prepaid'
        WHEN gs <= 40 THEN 'postpaid'
        ELSE 'enterprise'
    END AS plan_type,
    CASE
        WHEN gs <= 10 THEN 29.99 + (gs * 5.0)
        WHEN gs <= 30 THEN 79.99 + (gs * 3.0)
        ELSE 199.99 + (gs * 10.0)
    END AS base_monthly_fee,
    CASE
        WHEN gs <= 10 THEN 0.10
        WHEN gs <= 30 THEN 0.05
        ELSE 0.02
    END AS voice_rate_per_min,
    CASE
        WHEN gs <= 10 THEN 0.05
        WHEN gs <= 30 THEN 0.02
        ELSE 0.01
    END AS sms_rate_per_message,
    CASE
        WHEN gs <= 10 THEN 0.10
        WHEN gs <= 30 THEN 0.05
        ELSE 0.01
    END AS data_rate_per_mb,
    CASE
        WHEN gs <= 10 THEN 100
        WHEN gs <= 30 THEN 500
        ELSE 2000
    END AS included_minutes,
    CASE
        WHEN gs <= 10 THEN 100
        WHEN gs <= 30 THEN 500
        ELSE 5000
    END AS included_sms,
    CASE
        WHEN gs <= 10 THEN 1024
        WHEN gs <= 30 THEN 10240
        ELSE 102400
    END AS included_data_mb,
    1.5 AS overage_multiplier,
    'Rate plan ' || gs || ' with various billing rates' AS description
FROM generate_series(1, 50) gs;

\echo '  ✓ Populated 50 rate plans'

-- Populate termination_reasons (20 codes)
INSERT INTO cdr.termination_reasons (
    termination_code, termination_reason, category, billable, description
)
VALUES
    (1, 'Normal', 'normal', TRUE, 'Call completed normally by caller'),
    (2, 'Normal', 'normal', TRUE, 'Call completed normally by callee'),
    (16, 'Normal', 'normal', TRUE, 'Call clearing - normal'),
    (17, 'User Busy', 'normal', FALSE, 'Called party is busy'),
    (18, 'No Answer', 'normal', FALSE, 'No answer from called party'),
    (19, 'No Answer', 'normal', FALSE, 'No answer, alerting timeout'),
    (21, 'Call Rejected', 'normal', FALSE, 'Call rejected by called party'),
    (27, 'Destination Unavailable', 'network', FALSE, 'Destination out of service'),
    (28, 'Invalid Number', 'error', FALSE, 'Invalid number format'),
    (31, 'Normal', 'normal', TRUE, 'Normal, unspecified'),
    (34, 'Network Congestion', 'network', FALSE, 'No circuit available'),
    (38, 'Network Error', 'network', FALSE, 'Network out of order'),
    (41, 'Network Error', 'network', FALSE, 'Temporary failure'),
    (42, 'Network Congestion', 'network', FALSE, 'Switching equipment congestion'),
    (47, 'Network Error', 'network', FALSE, 'Resources unavailable'),
    (50, 'Network Error', 'network', FALSE, 'Requested facility not available'),
    (58, 'Network Error', 'network', FALSE, 'Bearer capability not available'),
    (102, 'Timeout', 'error', FALSE, 'Recovery on timer expiry'),
    (111, 'Protocol Error', 'error', FALSE, 'Protocol error, unspecified'),
    (127, 'System Error', 'error', FALSE, 'Interworking, unspecified');

\echo '  ✓ Populated 20 termination reason codes'

-- =====================================================
-- Analyze dimension tables
-- =====================================================

\echo ''
\echo 'Analyzing dimension tables...'

ANALYZE cdr.cell_towers;
ANALYZE cdr.rate_plans;
ANALYZE cdr.termination_reasons;

\echo '  ✓ Analysis complete'
\echo ''

-- =====================================================
-- Summary
-- =====================================================

\echo 'Schema setup summary:'
\echo ''

SELECT 'cell_towers' AS dimension_table,
       COUNT(*)::TEXT AS row_count,
       pg_size_pretty(pg_total_relation_size('cdr.cell_towers')) AS size
FROM cdr.cell_towers

UNION ALL

SELECT 'rate_plans',
       COUNT(*)::TEXT,
       pg_size_pretty(pg_total_relation_size('cdr.rate_plans'))
FROM cdr.rate_plans

UNION ALL

SELECT 'termination_reasons',
       COUNT(*)::TEXT,
       pg_size_pretty(pg_total_relation_size('cdr.termination_reasons'))
FROM cdr.termination_reasons;

\echo ''
\echo '===================================================='
\echo 'CDR schema setup complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 2 - Analyze cardinality for bloom filter validation'
