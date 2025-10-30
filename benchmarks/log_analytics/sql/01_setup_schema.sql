--
-- Phase 1: Setup Log Analytics Schema
-- Creates dimension and fact tables for application observability data
--

\timing on

\echo '===================================================='
\echo 'Log Analytics Benchmark - Phase 1: Setup Schema'
\echo '===================================================='
\echo ''

-- Create main schema
DROP SCHEMA IF EXISTS logs CASCADE;
CREATE SCHEMA logs;

\echo 'Schema created: logs'
\echo ''

-- =====================================================
-- Dimension Table: Applications
-- Represents 200 microservices in a distributed system
-- =====================================================

\echo 'Creating dimension table: logs.applications...'

CREATE TABLE logs.applications (
    application_id VARCHAR(64) PRIMARY KEY,         -- 'auth-service', 'payment-api', etc.
    application_name VARCHAR(100) NOT NULL,
    team VARCHAR(50) NOT NULL,                      -- Owning team
    language VARCHAR(20),                           -- 'java', 'go', 'python', 'nodejs'
    framework VARCHAR(50),                          -- 'spring-boot', 'gin', 'django', 'express'
    version VARCHAR(20),                            -- Semantic version
    environment VARCHAR(20) NOT NULL,               -- 'production', 'staging', 'development'
    region VARCHAR(20) NOT NULL,                    -- 'us-east-1', 'eu-west-1', etc.
    instance_count INTEGER,                         -- Number of running instances
    criticality VARCHAR(10),                        -- 'critical', 'high', 'medium', 'low'
    on_call_contact VARCHAR(100),
    documentation_url TEXT,
    last_deployed TIMESTAMP
) DISTRIBUTED BY (application_id);

\echo '  ✓ logs.applications created'
\echo ''

-- =====================================================
-- Reference Table: Log Levels
-- Standard logging levels
-- =====================================================

\echo 'Creating reference table: logs.log_levels...'

CREATE TABLE logs.log_levels (
    log_level VARCHAR(10) PRIMARY KEY,
    level_numeric INTEGER NOT NULL,                 -- For ordering: DEBUG=10, INFO=20, etc.
    severity VARCHAR(20),                           -- 'low', 'medium', 'high', 'critical'
    description TEXT
) DISTRIBUTED REPLICATED;

\echo '  ✓ logs.log_levels created'
\echo ''

-- =====================================================
-- Dimension Table: Error Types
-- Catalog of known error patterns
-- =====================================================

\echo 'Creating dimension table: logs.error_types...'

CREATE TABLE logs.error_types (
    error_code VARCHAR(50) PRIMARY KEY,
    error_category VARCHAR(50) NOT NULL,            -- 'database', 'network', 'auth', 'business', etc.
    error_name VARCHAR(100) NOT NULL,
    http_status_code INTEGER,                       -- Associated HTTP status if applicable
    is_retryable BOOLEAN DEFAULT FALSE,
    typical_resolution TEXT,
    documentation_url TEXT
) DISTRIBUTED REPLICATED;

\echo '  ✓ logs.error_types created'
\echo ''

-- =====================================================
-- Populate Dimension Tables
-- =====================================================

\echo 'Populating dimension tables...'

-- Populate log_levels
INSERT INTO logs.log_levels (log_level, level_numeric, severity, description) VALUES
    ('TRACE',   5, 'low',      'Finest-grained informational events'),
    ('DEBUG',  10, 'low',      'Fine-grained informational events useful for debugging'),
    ('INFO',   20, 'medium',   'Informational messages highlighting application progress'),
    ('WARN',   30, 'medium',   'Potentially harmful situations'),
    ('ERROR',  40, 'high',     'Error events that might still allow the application to continue'),
    ('FATAL',  50, 'critical', 'Very severe error events that will presumably lead to abort');

\echo '  ✓ Populated 6 log levels'

-- Populate error_types (50 common error patterns)
INSERT INTO logs.error_types (
    error_code, error_category, error_name, http_status_code, is_retryable, typical_resolution
)
SELECT
    'ERR-' || lpad(gs::TEXT, 4, '0') AS error_code,
    CASE
        WHEN gs <= 10 THEN 'database'
        WHEN gs <= 20 THEN 'network'
        WHEN gs <= 30 THEN 'authentication'
        WHEN gs <= 40 THEN 'authorization'
        ELSE 'business_logic'
    END AS error_category,
    CASE
        WHEN gs <= 10 THEN 'Database Connection Error'
        WHEN gs <= 20 THEN 'Network Timeout'
        WHEN gs <= 30 THEN 'Authentication Failed'
        WHEN gs <= 40 THEN 'Permission Denied'
        ELSE 'Business Rule Violation'
    END AS error_name,
    CASE
        WHEN gs <= 10 THEN 503
        WHEN gs <= 20 THEN 504
        WHEN gs <= 30 THEN 401
        WHEN gs <= 40 THEN 403
        ELSE 422
    END AS http_status_code,
    CASE
        WHEN gs <= 10 OR gs <= 20 THEN TRUE
        ELSE FALSE
    END AS is_retryable,
    CASE
        WHEN gs <= 10 THEN 'Check database connectivity and connection pool'
        WHEN gs <= 20 THEN 'Increase timeout or check network infrastructure'
        WHEN gs <= 30 THEN 'Verify credentials and token expiration'
        WHEN gs <= 40 THEN 'Check user permissions and RBAC configuration'
        ELSE 'Review business rule implementation'
    END AS typical_resolution
FROM generate_series(1, 50) gs;

\echo '  ✓ Populated 50 error types'

-- Populate applications (200 microservices)
INSERT INTO logs.applications (
    application_id, application_name, team, language, framework,
    version, environment, region, instance_count, criticality,
    on_call_contact, last_deployed
)
SELECT
    CASE (gs % 10)
        WHEN 0 THEN 'auth-service-'
        WHEN 1 THEN 'payment-api-'
        WHEN 2 THEN 'user-service-'
        WHEN 3 THEN 'product-catalog-'
        WHEN 4 THEN 'order-service-'
        WHEN 5 THEN 'inventory-api-'
        WHEN 6 THEN 'notification-worker-'
        WHEN 7 THEN 'analytics-processor-'
        WHEN 8 THEN 'search-service-'
        ELSE 'cache-manager-'
    END || lpad((gs % 20)::TEXT, 2, '0') AS application_id,

    CASE (gs % 10)
        WHEN 0 THEN 'Authentication Service'
        WHEN 1 THEN 'Payment API'
        WHEN 2 THEN 'User Management Service'
        WHEN 3 THEN 'Product Catalog'
        WHEN 4 THEN 'Order Processing Service'
        WHEN 5 THEN 'Inventory API'
        WHEN 6 THEN 'Notification Worker'
        WHEN 7 THEN 'Analytics Processor'
        WHEN 8 THEN 'Search Service'
        ELSE 'Cache Manager'
    END AS application_name,

    CASE (gs % 8)
        WHEN 0 THEN 'Platform'
        WHEN 1 THEN 'Commerce'
        WHEN 2 THEN 'User Experience'
        WHEN 3 THEN 'Data'
        WHEN 4 THEN 'Infrastructure'
        WHEN 5 THEN 'Security'
        WHEN 6 THEN 'Analytics'
        ELSE 'Operations'
    END AS team,

    CASE (gs % 5)
        WHEN 0 THEN 'java'
        WHEN 1 THEN 'go'
        WHEN 2 THEN 'python'
        WHEN 3 THEN 'nodejs'
        ELSE 'rust'
    END AS language,

    CASE (gs % 5)
        WHEN 0 THEN 'spring-boot'
        WHEN 1 THEN 'gin'
        WHEN 2 THEN 'django'
        WHEN 3 THEN 'express'
        ELSE 'actix-web'
    END AS framework,

    'v' || (1 + (gs % 10)) || '.' || (gs % 20) || '.0' AS version,

    CASE (gs % 3)
        WHEN 0 THEN 'production'
        WHEN 1 THEN 'staging'
        ELSE 'development'
    END AS environment,

    CASE (gs % 6)
        WHEN 0 THEN 'us-east-1'
        WHEN 1 THEN 'us-west-2'
        WHEN 2 THEN 'eu-west-1'
        WHEN 3 THEN 'eu-central-1'
        WHEN 4 THEN 'ap-southeast-1'
        ELSE 'ap-northeast-1'
    END AS region,

    CASE (gs % 3)
        WHEN 0 THEN 3 + (gs % 8)     -- 3-10 instances
        WHEN 1 THEN 1                -- Single instance
        ELSE 2 + (gs % 5)            -- 2-6 instances
    END AS instance_count,

    CASE (gs % 4)
        WHEN 0 THEN 'critical'
        WHEN 1 THEN 'high'
        WHEN 2 THEN 'medium'
        ELSE 'low'
    END AS criticality,

    'team-' || (gs % 8) || '@company.com' AS on_call_contact,

    CURRENT_TIMESTAMP - (INTERVAL '1 day' * (gs % 30)) AS last_deployed

FROM generate_series(1, 200) gs;

\echo '  ✓ Populated 200 applications'
\echo ''

-- =====================================================
-- Verify Dimension Tables
-- =====================================================

\echo 'Dimension table summary:'
\echo ''

SELECT
    'logs.log_levels' AS table_name,
    COUNT(*) AS row_count,
    pg_size_pretty(pg_total_relation_size('logs.log_levels')) AS size
FROM logs.log_levels

UNION ALL

SELECT
    'logs.error_types',
    COUNT(*),
    pg_size_pretty(pg_total_relation_size('logs.error_types'))
FROM logs.error_types

UNION ALL

SELECT
    'logs.applications',
    COUNT(*),
    pg_size_pretty(pg_total_relation_size('logs.applications'))
FROM logs.applications;

\echo ''
\echo '===================================================='
\echo 'Schema setup complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 2 - Validate cardinality (CRITICAL)'
\echo 'Run: psql -f sql/02_validate_cardinality.sql'
\echo ''
