--
-- Phase 1: Setup IoT Schema
-- Creates dimension and fact tables for time-series sensor data
--

\timing on

\echo '===================================================='
\echo 'IoT Benchmark - Phase 1: Setup IoT Schema'
\echo '===================================================='
\echo ''

-- Create main schema
DROP SCHEMA IF EXISTS iot CASCADE;
CREATE SCHEMA iot;

\echo 'Schema created: iot'
\echo ''

-- =====================================================
-- Dimension Table: Devices
-- Represents 100K IoT devices (sensors, gateways, etc.)
-- =====================================================

\echo 'Creating dimension table: iot.devices...'

CREATE TABLE iot.devices (
    device_id VARCHAR(64) PRIMARY KEY,              -- UUID format
    device_type VARCHAR(50) NOT NULL,               -- 'temperature', 'humidity', 'pressure', etc.
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    location VARCHAR(100) NOT NULL,                 -- 'building-A-floor-3-room-12'
    install_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',   -- 'active', 'inactive', 'maintenance'
    firmware_version VARCHAR(20),
    last_maintenance DATE,
    notes TEXT
) DISTRIBUTED BY (device_id);

\echo '  ✓ iot.devices created'
\echo ''

-- =====================================================
-- Dimension Table: Sensor Types
-- Catalog of sensor models and specifications
-- =====================================================

\echo 'Creating dimension table: iot.sensor_types...'

CREATE TABLE iot.sensor_types (
    sensor_type_id INTEGER PRIMARY KEY,
    sensor_name VARCHAR(100) NOT NULL,
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    measurement_unit VARCHAR(20),                   -- 'celsius', 'percent', 'hPa'
    accuracy NUMERIC(5,3),                          -- e.g., 0.5°C accuracy
    min_value NUMERIC(10,2),
    max_value NUMERIC(10,2),
    typical_range_min NUMERIC(10,2),
    typical_range_max NUMERIC(10,2),
    description TEXT
) DISTRIBUTED BY (sensor_type_id);

\echo '  ✓ iot.sensor_types created'
\echo ''

-- =====================================================
-- Populate Dimension Tables
-- =====================================================

\echo 'Populating dimension tables...'

-- Populate sensor_types (100 sensor types)
INSERT INTO iot.sensor_types (
    sensor_type_id, sensor_name, manufacturer, model,
    measurement_unit, accuracy, min_value, max_value,
    typical_range_min, typical_range_max, description
)
SELECT
    gs AS sensor_type_id,
    CASE
        WHEN gs <= 30 THEN 'Temperature Sensor'
        WHEN gs <= 50 THEN 'Humidity Sensor'
        WHEN gs <= 70 THEN 'Pressure Sensor'
        WHEN gs <= 85 THEN 'Air Quality Sensor'
        ELSE 'Motion Sensor'
    END AS sensor_name,
    CASE (gs % 5)
        WHEN 0 THEN 'Bosch'
        WHEN 1 THEN 'Honeywell'
        WHEN 2 THEN 'Siemens'
        WHEN 3 THEN 'ABB'
        ELSE 'Schneider Electric'
    END AS manufacturer,
    'Model-' || lpad(gs::TEXT, 3, '0') AS model,
    CASE
        WHEN gs <= 30 THEN 'celsius'
        WHEN gs <= 50 THEN 'percent'
        WHEN gs <= 70 THEN 'hPa'
        WHEN gs <= 85 THEN 'ppm'
        ELSE 'boolean'
    END AS measurement_unit,
    CASE
        WHEN gs <= 30 THEN 0.5
        WHEN gs <= 50 THEN 2.0
        WHEN gs <= 70 THEN 1.0
        WHEN gs <= 85 THEN 5.0
        ELSE 0.0
    END AS accuracy,
    CASE
        WHEN gs <= 30 THEN -40
        WHEN gs <= 50 THEN 0
        WHEN gs <= 70 THEN 900
        WHEN gs <= 85 THEN 0
        ELSE 0
    END AS min_value,
    CASE
        WHEN gs <= 30 THEN 125
        WHEN gs <= 50 THEN 100
        WHEN gs <= 70 THEN 1100
        WHEN gs <= 85 THEN 1000
        ELSE 1
    END AS max_value,
    CASE
        WHEN gs <= 30 THEN 15
        WHEN gs <= 50 THEN 30
        WHEN gs <= 70 THEN 980
        WHEN gs <= 85 THEN 300
        ELSE 0
    END AS typical_range_min,
    CASE
        WHEN gs <= 30 THEN 30
        WHEN gs <= 50 THEN 70
        WHEN gs <= 70 THEN 1050
        WHEN gs <= 85 THEN 800
        ELSE 1
    END AS typical_range_max,
    'IoT sensor type ' || gs AS description
FROM generate_series(1, 100) gs;

\echo '  ✓ Populated 100 sensor types'

-- Populate devices (100K devices)
-- Note: This creates device metadata but NOT sensor readings
INSERT INTO iot.devices (
    device_id, device_type, manufacturer, model,
    location, install_date, status, firmware_version, last_maintenance
)
SELECT
    'device-' || lpad(gs::TEXT, 6, '0') AS device_id,
    CASE (gs % 5)
        WHEN 0 THEN 'temperature'
        WHEN 1 THEN 'humidity'
        WHEN 2 THEN 'pressure'
        WHEN 3 THEN 'air_quality'
        ELSE 'motion'
    END AS device_type,
    CASE (gs % 5)
        WHEN 0 THEN 'Bosch'
        WHEN 1 THEN 'Honeywell'
        WHEN 2 THEN 'Siemens'
        WHEN 3 THEN 'ABB'
        ELSE 'Schneider Electric'
    END AS manufacturer,
    'Model-' || lpad((1 + (gs % 100))::TEXT, 3, '0') AS model,
    'building-' || chr(65 + ((gs / 10000) % 26)) ||
    '-floor-' || (1 + ((gs / 1000) % 10)) ||
    '-room-' || lpad(((gs % 1000) + 1)::TEXT, 3, '0') AS location,
    DATE '2020-01-01' + (gs % 1825) AS install_date,  -- Installed over 5 years
    CASE
        WHEN gs % 100 < 95 THEN 'active'
        WHEN gs % 100 < 98 THEN 'maintenance'
        ELSE 'inactive'
    END AS status,
    'v' || (1 + (gs % 10)) || '.0' AS firmware_version,
    CURRENT_DATE - (gs % 365) AS last_maintenance
FROM generate_series(1, 100000) gs;

\echo '  ✓ Populated 100,000 devices'
\echo ''

-- =====================================================
-- Verify Dimension Tables
-- =====================================================

\echo 'Dimension table summary:'
\echo ''

SELECT
    'iot.sensor_types' AS table_name,
    COUNT(*) AS row_count,
    pg_size_pretty(pg_total_relation_size('iot.sensor_types')) AS size
FROM iot.sensor_types

UNION ALL

SELECT
    'iot.devices',
    COUNT(*),
    pg_size_pretty(pg_total_relation_size('iot.devices'))
FROM iot.devices;

\echo ''
\echo '===================================================='
\echo 'Schema setup complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 2 - Analyze cardinality (CRITICAL VALIDATION)'
