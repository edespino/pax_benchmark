# PAX Benchmark Suite - Multi-Scenario Master Plan

**Comprehensive validation of PAX storage across 6 real-world workloads**

---

## Executive Summary

**Goal**: Create production-ready benchmark suite demonstrating PAX storage effectiveness across diverse workload patterns, all using validation-first framework to prevent misconfiguration disasters.

**Scenarios**: 6 workloads covering major database use cases (3 completed as of Oct 2025)
**Timeline**: 1 scenario at a time, ~2-3 hours implementation each
**Validation**: Shared framework preventing 81% bloat disasters
**Output**: Unified comparison across all scenarios

**Completion Status**:
- ✅ Scenario 0: IoT Time-Series (Oct 2025)
- ✅ Scenario 1: Financial Trading (Oct 2025)
- ✅ Scenario 2: Log Analytics (Oct 2025)
- ⏳ Scenarios 3-6: Planned

---

## Suite Architecture

### Directory Structure

```
pax_benchmark/
├── PAX_BENCHMARK_SUITE_PLAN.md          # This file
├── CLAUDE.md                             # AI guidance (updated)
├── benchmarks/                           # All benchmark scenarios
│   ├── README.md                         # Benchmark suite overview
│   │
│   ├── timeseries_iot/                   # ✅ COMPLETED (Scenario 0)
│   │   ├── README.md
│   │   ├── sql/                          # 9 SQL scripts
│   │   ├── scripts/run_iot_benchmark.sh
│   │   └── results/                      # Timestamped runs
│   │
│   ├── financial_trading/                # ✅ COMPLETED (Scenario 1)
│   │   ├── README.md
│   │   ├── sql/                          # 9 SQL scripts
│   │   ├── scripts/run_trading_benchmark.sh
│   │   └── results/
│   │
│   ├── log_analytics/                    # ✅ COMPLETED (Scenario 2)
│   │   ├── README.md
│   │   ├── sql/                          # 10 SQL scripts
│   │   ├── scripts/run_log_benchmark.sh
│   │   └── results/
│   │
│   ├── ecommerce_clickstream/            # ⏳ Planned (Scenario 3)
│   ├── telecom_cdr/                      # ⏳ Planned (Scenario 4)
│   ├── geospatial_location/              # ⏳ Planned (Scenario 5)
│   └── healthcare_records/               # ⏳ Planned (Scenario 6)
│
├── retail_sales/                         # Original comprehensive benchmark
│   └── [200M row, 2-4 hour benchmark]
│
└── results/
    └── unified_comparison/
        ├── all_scenarios_summary.md
        ├── storage_comparison.csv
        ├── query_performance.csv
        └── configuration_patterns.md
```

---

## Scenario Definitions

### Scenario 0: IoT Time-Series ✅ COMPLETED

**Status**: Implemented, tested, committed (8518d94)

**Characteristics**:
- 10M sensor readings (100K devices)
- High-cardinality: device_id (100K unique)
- Low-cardinality: sensor_type (100 unique), status (3 unique)
- Z-order: reading_date + device_id

**Results**:
- PAX overhead: 3.3% vs AOCO
- Z-order overhead: 0.002%
- All 4 validation gates passed

**Lesson**: Bloom filters on low-cardinality columns cause 81% bloat

---

### Scenario 1: Financial Trading (High-Frequency Tick Data) ✅ COMPLETED

**Status**: Implemented, tested, committed (35036eb)

**Business Context**: Stock exchange tick data, high-frequency trading analytics

**Schema**:
```sql
CREATE TABLE trading.tick_data (
    -- Time dimension (microsecond precision)
    trade_timestamp TIMESTAMP(6) NOT NULL,
    trade_date DATE NOT NULL,
    trade_time_bucket TIMESTAMP NOT NULL,  -- Rounded to second for Z-order

    -- Identifiers (high cardinality)
    symbol VARCHAR(10) NOT NULL,           -- ~5,000 stocks
    exchange_id VARCHAR(10) NOT NULL,      -- ~20 exchanges
    trade_id BIGINT NOT NULL,              -- Unique per trade

    -- Price/volume
    price NUMERIC(18,6) NOT NULL,
    quantity INTEGER NOT NULL,
    volume_usd NUMERIC(20,2) NOT NULL,

    -- Market data
    bid_price NUMERIC(18,6),
    ask_price NUMERIC(18,6),
    bid_size INTEGER,
    ask_size INTEGER,

    -- Trade characteristics
    trade_type VARCHAR(10),                -- market/limit/stop (10 types)
    buyer_type VARCHAR(20),                -- institutional/retail/market_maker
    seller_type VARCHAR(20),

    -- Conditions
    trade_condition VARCHAR(4),            -- ~50 condition codes
    sale_condition VARCHAR(10),

    -- Derived fields
    price_change_bps NUMERIC(10,4),        -- Basis points vs previous
    is_block_trade BOOLEAN,

    -- Audit
    sequence_number BIGINT,
    checksum VARCHAR(64)
) DISTRIBUTED BY (symbol);
```

**Data Characteristics**:
- **Volume**: 50M trades/day (testing: 10M rows)
- **Time density**: Microsecond precision, bursts during market hours
- **Cardinality profile**:
  - trade_id: 10M unique (n_distinct = -1.0) ✅ High - bloom filter candidate
  - symbol: ~5,000 unique ✅ High - bloom filter candidate
  - exchange_id: ~20 unique ❌ Low - minmax only
  - trade_type: ~10 unique ❌ Low - minmax only
  - trade_condition: ~50 unique ❌ Low - minmax only

**PAX Configuration Strategy**:
```sql
USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: All filterable columns
    minmax_columns='trade_date,trade_timestamp,symbol,exchange_id,price,volume_usd,trade_type',

    -- Bloom: ONLY high-cardinality (symbol, trade_id)
    bloomfilter_columns='symbol,trade_id',

    -- Z-order: Time + symbol (most common query pattern)
    cluster_type='zorder',
    cluster_columns='trade_time_bucket,symbol',

    storage_format='porc'
);
```

**Query Patterns** (15 queries):

1. **Time-range queries** (recent data, market close analysis)
   - Q1: Last 5 minutes of trading
   - Q2: Specific hour across all symbols
   - Q3: Market open volatility (first 30 min)

2. **Symbol-specific queries** (bloom filter effectiveness)
   - Q4: Single symbol full day history
   - Q5: Top 10 symbols by volume
   - Q6: Symbol correlation (2 symbols, same timeframe)

3. **Price analytics** (compression + sparse filtering)
   - Q7: VWAP calculation (volume-weighted average price)
   - Q8: Price range detection (high/low for symbol)
   - Q9: Large price movements (>1% change)

4. **Market microstructure**
   - Q10: Bid-ask spread analysis
   - Q11: Block trade detection (quantity > threshold)
   - Q12: Trade type distribution

5. **Cross-exchange analysis**
   - Q13: Same symbol across multiple exchanges
   - Q14: Exchange-specific patterns
   - Q15: Arbitrage opportunity detection

**Expected Results**:
- **Storage**: PAX 5-10% overhead vs AOCO (high cardinality = more metadata)
- **Query performance**: 2-3x faster on symbol lookups (bloom filters)
- **Compression**: 6-8x (numeric data compresses well with ZSTD)
- **Z-order benefit**: 3-5x speedup on (time, symbol) queries

**Key Validation Points**:
- ✅ Verify symbol cardinality (should be ~5,000)
- ✅ Verify trade_id cardinality (should be ~10M)
- ❌ Ensure exchange_id NOT in bloom filters (only ~20 unique)
- ✅ Calculate memory for 10M rows: ~2.4 GB maintenance_work_mem

**Runtime**: ~6-8 minutes
- Phase 5 (10M trades): ~3-4 min
- Phase 7 (clustering): ~2-3 min

---

### Scenario 2: Log Analytics / Observability ✅ COMPLETED

**Status**: Implemented, tested, committed (18f8d30)

**Business Context**: Application logs, distributed tracing, system monitoring

**Schema**:
```sql
CREATE TABLE observability.application_logs (
    -- Time dimension
    log_timestamp TIMESTAMP(3) NOT NULL,
    log_date DATE NOT NULL,
    log_hour TIMESTAMP NOT NULL,          -- For Z-order

    -- Source identifiers
    service_name VARCHAR(100) NOT NULL,   -- ~200 microservices
    host_name VARCHAR(100) NOT NULL,      -- ~500 hosts
    pod_name VARCHAR(100),                -- ~2,000 pods (Kubernetes)
    container_id VARCHAR(64),             -- ~5,000 containers

    -- Log metadata
    log_level VARCHAR(10) NOT NULL,       -- DEBUG/INFO/WARN/ERROR/FATAL (5 values)
    logger_name VARCHAR(200),             -- ~1,000 logger classes
    thread_name VARCHAR(100),

    -- Request context
    trace_id VARCHAR(32),                 -- ~1M unique traces
    span_id VARCHAR(16),                  -- ~5M unique spans
    parent_span_id VARCHAR(16),

    -- Message content
    message TEXT,                         -- Variable length, sparse structure
    exception_type VARCHAR(200),          -- ~100 exception types
    exception_message TEXT,
    stack_trace TEXT,

    -- Structured fields (JSON/key-value)
    user_id VARCHAR(64),                  -- ~100K users
    request_id VARCHAR(64),               -- ~2M requests
    http_method VARCHAR(10),              -- 9 HTTP methods
    http_status INTEGER,                  -- ~60 status codes
    http_path VARCHAR(500),               -- ~10,000 unique paths

    -- Metrics
    duration_ms INTEGER,
    memory_mb INTEGER,
    cpu_percent NUMERIC(5,2),

    -- Labels/tags (sparse)
    environment VARCHAR(20),              -- dev/staging/prod (3 values)
    region VARCHAR(20),                   -- ~10 regions
    version VARCHAR(20),                  -- ~50 versions

    -- Metadata
    sequence_number BIGINT,
    ingestion_timestamp TIMESTAMP
) DISTRIBUTED BY (service_name);
```

**Data Characteristics**:
- **Volume**: 100M logs/day (testing: 10M rows)
- **Schema**: Wide (30 columns), many NULL/sparse fields
- **Text fields**: Variable length, poor compression candidates
- **Cardinality profile**:
  - trace_id: ~1M unique ✅ High - bloom filter
  - request_id: ~2M unique ✅ High - bloom filter
  - container_id: ~5,000 unique ✅ High - bloom filter
  - service_name: ~200 unique ❌ Low - minmax only
  - log_level: 5 values ❌ Very low - minmax only
  - http_method: 9 values ❌ Very low - minmax only

**PAX Configuration Strategy**:
```sql
USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Filterable columns (NOT text fields)
    minmax_columns='log_date,log_timestamp,service_name,log_level,http_status,duration_ms',

    -- Bloom: High-cardinality lookup columns
    -- WARNING: NOT message/stack_trace (text), NOT service_name (only 200 unique)
    bloomfilter_columns='trace_id,request_id,container_id',

    -- Z-order: Time + service (common pattern: logs for service in time range)
    cluster_type='zorder',
    cluster_columns='log_hour,service_name',

    storage_format='porc'
);
```

**Query Patterns** (15 queries):

1. **Recent logs** (time-based)
   - Q1: Last 15 minutes all services
   - Q2: Last hour for specific service
   - Q3: Errors in last day

2. **Trace analysis** (bloom filter effectiveness)
   - Q4: All logs for specific trace_id
   - Q5: Request timeline (request_id lookup)
   - Q6: Distributed trace reconstruction

3. **Error analysis**
   - Q7: All ERROR/FATAL logs
   - Q8: Specific exception type
   - Q9: Error rate by service

4. **Performance analysis**
   - Q10: Slow requests (duration_ms > threshold)
   - Q11: Memory spikes
   - Q12: HTTP 5xx errors

5. **Sparse field queries**
   - Q13: Logs with stack traces (WHERE stack_trace IS NOT NULL)
   - Q14: User activity (WHERE user_id = ?)
   - Q15: Regional patterns

**Expected Results**:
- **Storage**: PAX 10-15% overhead vs AOCO (wide schema, text fields, sparse data)
- **Compression**: 3-5x (text fields compress poorly)
- **Query performance**: 3-5x faster on trace_id/request_id lookups
- **Sparse filtering**: 70-90% file skip rate on ERROR logs (<5% of data)

**Actual Results** (Oct 30, 2025 - 10M rows):
- **AO**: 1,065 MB (baseline)
- **AOCO**: 690 MB (0.65x vs AO)
- **PAX no-cluster**: 717 MB (+4% vs AOCO) ✅ **Excellent**
- **PAX clustered**: 1,046 MB (+52% vs AOCO) ❌ High overhead
- **Compression**: 4.9x (PAX no-cluster), 3.3x (PAX clustered)
- **Sparse validation**: stack_trace (95% NULL), error_code (95% NULL), user_id (30% NULL) - all perfect
- **Bloom filters**: trace_id (10M unique), request_id (10M unique) - validated
- **Clustering overhead**: 46% (higher than expected, likely due to text-heavy data)

**Key Findings**:
- ✅ PAX no-cluster is **production-ready** for log analytics (4% overhead)
- ❌ PAX clustering adds excessive overhead on text-heavy workloads (46%)
- ✅ Sparse filtering works perfectly (95% NULL columns validated)
- ✅ Bloom filter configuration validated (only high-cardinality columns)
- 📝 Recommendation: Use PAX no-cluster for APM/observability data

**Key Validation Points**:
- ✅ Verify trace_id cardinality (~1M) - **PASSED**: 10M unique
- ✅ Verify request_id cardinality (~2M) - **PASSED**: 10M unique
- ✅ Exclude log_level from bloom filters (only 6 values) - **PASSED**
- ✅ Exclude http_method from bloom filters (only 9 values) - **PASSED**
- ✅ Do NOT use bloom filters on TEXT columns - **PASSED**

**Actual Runtime**: 5m 26s
- Phase 5 (10M logs with TEXT): 88s (~1.5 min)
- Phase 6 (Z-order clustering): 32s
- Phase 7 (12 queries): 24s
- Phase 8 (metrics): 36s
- Phase 9 (validation): 141s (~2.5 min)

---

### Scenario 3: E-commerce Clickstream

**Business Context**: User behavior analytics, funnel analysis, product recommendations

**Schema**:
```sql
CREATE TABLE ecommerce.clickstream (
    -- Time dimension
    event_timestamp TIMESTAMP NOT NULL,
    event_date DATE NOT NULL,
    event_hour TIMESTAMP NOT NULL,

    -- Session/user identifiers
    session_id VARCHAR(64) NOT NULL,      -- ~2M sessions
    user_id VARCHAR(64),                  -- ~500K registered users (nullable for anonymous)
    anonymous_id VARCHAR(64),             -- ~3M anonymous visitors

    -- Event classification
    event_type VARCHAR(50) NOT NULL,      -- ~30 event types
    event_name VARCHAR(100) NOT NULL,     -- ~100 specific events
    page_url VARCHAR(500),                -- ~50,000 unique URLs
    page_category VARCHAR(100),           -- ~500 categories

    -- Product context (nullable for non-product events)
    product_id VARCHAR(64),               -- ~100K products
    product_name VARCHAR(200),
    product_category VARCHAR(100),        -- ~200 categories
    product_price NUMERIC(10,2),
    product_quantity INTEGER,

    -- Shopping cart state
    cart_value NUMERIC(12,2),
    cart_item_count INTEGER,

    -- User characteristics
    user_segment VARCHAR(50),             -- ~20 segments
    is_returning_customer BOOLEAN,
    lifetime_value_bucket VARCHAR(20),    -- ~10 buckets

    -- Device/browser
    device_type VARCHAR(20),              -- mobile/tablet/desktop (3 values)
    browser VARCHAR(50),                  -- ~20 browsers
    os VARCHAR(50),                       -- ~15 OS
    screen_resolution VARCHAR(20),        -- ~50 resolutions

    -- Marketing attribution
    utm_source VARCHAR(100),              -- ~100 sources
    utm_medium VARCHAR(100),              -- ~30 mediums
    utm_campaign VARCHAR(100),            -- ~500 campaigns
    referrer_url VARCHAR(500),            -- ~10,000 referrers

    -- Geography
    country_code VARCHAR(2),              -- ~200 countries
    region VARCHAR(100),                  -- ~2,000 regions
    city VARCHAR(100),                    -- ~10,000 cities

    -- Experiment/personalization
    experiment_id VARCHAR(64),            -- ~100 A/B tests
    variant_id VARCHAR(64),               -- ~300 variants
    personalization_segment VARCHAR(100), -- ~50 segments

    -- Event metadata
    event_value NUMERIC(12,2),
    event_properties JSONB,               -- Flexible schema
    sequence_in_session INTEGER,
    time_on_page_seconds INTEGER
) DISTRIBUTED BY (session_id);
```

**Data Characteristics**:
- **Volume**: 50M events/day (testing: 10M rows)
- **Multi-dimensional**: User × Product × Time × Campaign
- **High-cardinality columns**: session_id, product_id, user_id
- **Cardinality profile**:
  - session_id: ~2M unique ✅ High - bloom filter
  - product_id: ~100K unique ✅ High - bloom filter
  - user_id: ~500K unique ✅ High - bloom filter
  - event_type: ~30 unique ❌ Low - minmax only
  - device_type: 3 values ❌ Very low - minmax only
  - utm_medium: ~30 unique ❌ Low - minmax only

**PAX Configuration Strategy**:
```sql
USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Filterable dimensions
    minmax_columns='event_date,event_timestamp,event_type,product_category,device_type,country_code,cart_value',

    -- Bloom: High-cardinality lookup columns
    bloomfilter_columns='session_id,user_id,product_id',

    -- Z-order: Time + session (funnel analysis pattern)
    -- Alternative: Time + product_id (product analytics pattern)
    cluster_type='zorder',
    cluster_columns='event_hour,session_id',

    storage_format='porc'
);
```

**Query Patterns** (20 queries):

1. **Session analysis** (bloom filter effectiveness)
   - Q1: Full session journey (session_id lookup)
   - Q2: User behavior across sessions (user_id lookup)
   - Q3: Anonymous visitor tracking

2. **Funnel analysis** (time-series + event filtering)
   - Q4: Home → Product → Cart → Checkout conversion
   - Q5: Cart abandonment analysis
   - Q6: Time between events in funnel

3. **Product analytics**
   - Q7: Product views vs purchases
   - Q8: Top products by category
   - Q9: Product affinity (co-viewing patterns)

4. **Real-time dashboards** (recent data)
   - Q10: Last hour events by type
   - Q11: Active sessions (last 30 min)
   - Q12: Real-time conversion rate

5. **Marketing attribution**
   - Q13: Campaign performance (utm_campaign)
   - Q14: Channel ROI (utm_source + purchases)
   - Q15: Referrer analysis

6. **Cohort analysis**
   - Q16: New vs returning customers
   - Q17: User segment behavior
   - Q18: Geographic patterns

7. **A/B testing**
   - Q19: Experiment conversion rates
   - Q20: Variant performance comparison

**Expected Results**:
- **Storage**: PAX 8-12% overhead vs AOCO (many low-cardinality dimensions)
- **Compression**: 5-7x (mix of numeric, varchar, nullable fields)
- **Query performance**:
  - Session lookups: 4-6x faster (bloom on session_id)
  - Product queries: 3-4x faster (bloom on product_id)
  - Funnel queries: 2-3x faster (Z-order on time + session)

**Key Validation Points**:
- ✅ Verify session_id cardinality (~2M)
- ✅ Verify product_id cardinality (~100K)
- ✅ Verify user_id cardinality (~500K)
- ❌ Exclude event_type from bloom filters (~30 unique)
- ❌ Exclude device_type from bloom filters (only 3 values)
- ⚠️  Consider alternative Z-order: event_date + product_id for product-centric analytics

**Runtime**: ~8-10 minutes
- Phase 5 (10M events): ~4-5 min
- Phase 7 (clustering): ~3-4 min (multi-dimensional Z-order)

---

### Scenario 4: Telecommunications CDR (Call Detail Records)

**Business Context**: Billing, fraud detection, network analytics, regulatory compliance

**Schema**:
```sql
CREATE TABLE telecom.call_detail_records (
    -- Time dimension
    call_start_time TIMESTAMP NOT NULL,
    call_end_time TIMESTAMP NOT NULL,
    call_date DATE NOT NULL,
    call_hour TIMESTAMP NOT NULL,
    call_duration_seconds INTEGER NOT NULL,

    -- Phone numbers (high cardinality, PII)
    calling_number VARCHAR(20) NOT NULL,  -- ~10M subscribers
    called_number VARCHAR(20) NOT NULL,   -- ~50M possible destinations

    -- Call classification
    call_type VARCHAR(20) NOT NULL,       -- voice/sms/data/mms (~10 types)
    service_type VARCHAR(50),             -- standard/premium/international (~30 types)
    call_direction VARCHAR(10),           -- inbound/outbound/local (~5 types)

    -- Network information
    cell_id VARCHAR(20) NOT NULL,         -- ~50,000 cell towers
    sector_id VARCHAR(20),                -- ~150,000 sectors
    lac_code VARCHAR(10),                 -- ~5,000 location area codes

    -- Switching/routing
    originating_switch VARCHAR(20),       -- ~500 switches
    terminating_switch VARCHAR(20),       -- ~500 switches
    trunk_group VARCHAR(50),              -- ~1,000 trunk groups
    route_id VARCHAR(50),                 -- ~5,000 routes

    -- Quality metrics
    call_quality_mos NUMERIC(3,2),        -- Mean opinion score (1.0-5.0)
    packet_loss_percent NUMERIC(5,2),
    jitter_ms INTEGER,
    setup_time_ms INTEGER,

    -- Billing information
    charged_amount NUMERIC(10,4),
    currency_code VARCHAR(3),             -- ~50 currencies
    rating_plan_id VARCHAR(50),           -- ~1,000 plans
    discount_applied NUMERIC(10,4),

    -- Status/outcome
    call_completion_status VARCHAR(20),   -- ~20 statuses (completed/busy/failed/etc)
    termination_reason VARCHAR(50),       -- ~50 reasons
    is_roaming BOOLEAN,
    roaming_partner VARCHAR(100),         -- ~200 partners

    -- Fraud detection flags
    fraud_score NUMERIC(5,2),
    is_fraud_suspect BOOLEAN,
    fraud_reason VARCHAR(100),

    -- Regulatory/compliance
    lawful_intercept_flag BOOLEAN,
    data_retention_class VARCHAR(20),     -- ~10 retention classes

    -- Geography
    originating_country VARCHAR(2),       -- ~200 countries
    terminating_country VARCHAR(2),
    originating_region VARCHAR(100),      -- ~2,000 regions

    -- Record metadata
    record_id BIGINT NOT NULL,            -- Unique per record
    billing_cycle VARCHAR(10),            -- YYYYMM format
    processing_timestamp TIMESTAMP,
    record_checksum VARCHAR(64)
) DISTRIBUTED BY (calling_number);
```

**Data Characteristics**:
- **Volume**: 500M CDRs/day (testing: 10M rows)
- **Regulatory**: Fast retrieval required for lawful intercept
- **Billing critical**: Must support accurate billing queries
- **Cardinality profile**:
  - calling_number: ~10M unique ✅ High - bloom filter (critical for compliance)
  - called_number: ~50M unique ✅ High - bloom filter
  - cell_id: ~50K unique ✅ High - bloom filter
  - record_id: ~10M unique ✅ High - bloom filter
  - call_type: ~10 unique ❌ Low - minmax only
  - call_direction: ~5 unique ❌ Low - minmax only
  - originating_switch: ~500 unique ❌ Low - minmax only

**PAX Configuration Strategy**:
```sql
USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Time, status, quality, billing
    minmax_columns='call_date,call_start_time,call_type,call_duration_seconds,charged_amount,cell_id,call_completion_status',

    -- Bloom: Phone numbers (compliance), cell_id (network analysis)
    -- CRITICAL: Phone number lookup must be fast for lawful intercept
    bloomfilter_columns='calling_number,called_number,cell_id',

    -- Z-order: Time + calling_number (billing queries, compliance)
    cluster_type='zorder',
    cluster_columns='call_date,calling_number',

    storage_format='porc'
);
```

**Query Patterns** (20 queries):

1. **Regulatory compliance** (must be fast!)
   - Q1: All calls for phone number (lawful intercept)
   - Q2: Call history between two numbers
   - Q3: Calls to high-risk destinations

2. **Billing queries**
   - Q4: Monthly bill calculation (calling_number + date range)
   - Q5: International call charges
   - Q6: Roaming charges by country

3. **Network performance**
   - Q7: Cell tower usage (cell_id lookup)
   - Q8: Poor call quality analysis (MOS < 3.0)
   - Q9: Failed call analysis

4. **Fraud detection**
   - Q10: High fraud score calls
   - Q11: Unusual calling patterns (duration, frequency)
   - Q12: International premium rate fraud

5. **Customer analytics**
   - Q13: Top callers by duration
   - Q14: Customer churn indicators (decreasing usage)
   - Q15: Service adoption (data vs voice)

6. **Network planning**
   - Q16: Peak hour traffic analysis
   - Q17: Trunk group utilization
   - Q18: Switch performance metrics

7. **Revenue analysis**
   - Q19: Revenue by service type
   - Q20: Discount effectiveness

**Expected Results**:
- **Storage**: PAX 7-10% overhead vs AOCO (many high-cardinality columns)
- **Compression**: 6-8x (numeric billing data, timestamps)
- **Query performance**:
  - Phone number lookups: 5-10x faster (CRITICAL for compliance)
  - Billing queries: 3-5x faster (Z-order on date + phone)
  - Network analysis: 4-6x faster (bloom on cell_id)

**Key Validation Points**:
- ✅ Verify calling_number cardinality (~10M) - CRITICAL
- ✅ Verify called_number cardinality (~50M)
- ✅ Verify cell_id cardinality (~50K)
- ❌ Exclude call_type from bloom filters (~10 unique)
- ❌ Exclude call_direction from bloom filters (~5 unique)
- ⚠️  Memory: 10M rows = 2.4GB maintenance_work_mem

**Compliance Note**: Phone number queries must complete in <1 second for lawful intercept requirements. PAX bloom filters are essential.

**Runtime**: ~7-10 minutes
- Phase 5 (10M CDRs): ~3-4 min
- Phase 7 (clustering): ~3-4 min

---

### Scenario 5: Geospatial / Location Data

**Business Context**: GPS tracking, fleet management, geofencing, proximity analysis

**Schema**:
```sql
CREATE TABLE geospatial.location_events (
    -- Time dimension
    event_timestamp TIMESTAMP NOT NULL,
    event_date DATE NOT NULL,
    event_hour TIMESTAMP NOT NULL,

    -- Location coordinates
    latitude NUMERIC(10,7) NOT NULL,      -- -90.0000000 to 90.0000000
    longitude NUMERIC(10,7) NOT NULL,     -- -180.0000000 to 180.0000000
    altitude_meters NUMERIC(8,2),
    accuracy_meters NUMERIC(8,2),

    -- Geohash for spatial indexing
    geohash_1 CHAR(1),                    -- ~32 grid cells (global)
    geohash_2 CHAR(2),                    -- ~1,024 grid cells
    geohash_3 CHAR(3),                    -- ~32,768 grid cells
    geohash_4 CHAR(4),                    -- ~1M grid cells
    geohash_5 CHAR(5),                    -- ~33M grid cells
    geohash_6 CHAR(6),                    -- ~1B grid cells (156m precision)

    -- Asset/device identifiers
    device_id VARCHAR(64) NOT NULL,       -- ~100K vehicles/devices
    asset_type VARCHAR(50),               -- ~50 asset types
    fleet_id VARCHAR(50),                 -- ~1,000 fleets
    driver_id VARCHAR(64),                -- ~200K drivers

    -- Movement characteristics
    speed_kmh NUMERIC(6,2),
    heading_degrees INTEGER,              -- 0-359
    movement_type VARCHAR(20),            -- stationary/walking/driving/flying (~10 types)

    -- Geography (reverse geocoded)
    country_code VARCHAR(2),              -- ~200 countries
    state_province VARCHAR(100),          -- ~5,000 states/provinces
    city VARCHAR(100),                    -- ~100,000 cities
    postal_code VARCHAR(20),              -- ~1M postal codes
    street_address VARCHAR(200),          -- ~10M addresses

    -- Points of interest
    poi_id VARCHAR(64),                   -- ~1M POIs
    poi_name VARCHAR(200),
    poi_category VARCHAR(100),            -- ~500 categories
    poi_distance_meters INTEGER,

    -- Geofences
    geofence_id VARCHAR(64),              -- ~50,000 geofences
    geofence_event_type VARCHAR(20),      -- enter/exit/dwell (~5 types)
    dwell_time_seconds INTEGER,

    -- Trip/journey context
    trip_id VARCHAR(64),                  -- ~5M trips
    trip_sequence INTEGER,
    is_trip_start BOOLEAN,
    is_trip_end BOOLEAN,

    -- Environmental context
    weather_condition VARCHAR(50),        -- ~30 conditions
    temperature_celsius NUMERIC(5,2),
    road_type VARCHAR(50),                -- ~20 road types
    traffic_level VARCHAR(20),            -- ~5 levels

    -- Device/sensor metadata
    battery_percent INTEGER,
    signal_strength_dbm INTEGER,
    gps_satellites INTEGER,
    location_method VARCHAR(20),          -- gps/wifi/cell/ip (~5 methods)

    -- Event metadata
    event_id BIGINT NOT NULL,
    processing_timestamp TIMESTAMP
) DISTRIBUTED BY (device_id);
```

**Data Characteristics**:
- **Volume**: 100M location events/day (testing: 10M rows)
- **Spatial queries**: Bounding box, proximity, route analysis
- **Continuous coordinates**: High uniqueness (lat/lon pairs)
- **Cardinality profile**:
  - device_id: ~100K unique ✅ High - bloom filter
  - trip_id: ~5M unique ✅ High - bloom filter
  - geofence_id: ~50K unique ✅ High - bloom filter
  - poi_id: ~1M unique ✅ High - bloom filter
  - geohash_6: ~1M unique (depends on area coverage) ✅ High - bloom filter
  - geohash_3: ~10K unique ❌ Low - minmax only
  - movement_type: ~10 unique ❌ Low - minmax only
  - geofence_event_type: ~5 unique ❌ Low - minmax only

**PAX Configuration Strategy**:
```sql
USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Time, spatial bounds, geohashes
    minmax_columns='event_date,event_timestamp,latitude,longitude,geohash_3,geohash_4,speed_kmh,poi_distance_meters',

    -- Bloom: Device tracking, trip analysis, geofence lookups
    bloomfilter_columns='device_id,trip_id,geofence_id,geohash_6',

    -- Z-order: Geohash + time (spatial-temporal co-location)
    -- Alternative: device_id + time (device tracking)
    cluster_type='zorder',
    cluster_columns='geohash_4,event_hour',

    storage_format='porc'
);
```

**Query Patterns** (20 queries):

1. **Device tracking**
   - Q1: Full device trajectory (device_id lookup)
   - Q2: Device location history (time range)
   - Q3: Multi-device convoy detection

2. **Spatial bounding box** (Z-order effectiveness)
   - Q4: All events in lat/lon rectangle
   - Q5: Events within city bounds
   - Q6: Geohash prefix matching (geohash_3 = 'abc')

3. **Proximity analysis**
   - Q7: Devices near POI (poi_distance_meters < 100)
   - Q8: Co-location detection (devices in same area/time)
   - Q9: Closest device to coordinates

4. **Geofence analysis**
   - Q10: Geofence entry/exit events (geofence_id lookup)
   - Q11: Dwell time in geofence
   - Q12: Geofence violation detection

5. **Trip analysis**
   - Q13: Complete trip reconstruction (trip_id lookup)
   - Q14: Trip duration and distance
   - Q15: Route optimization analysis

6. **Fleet management**
   - Q16: Fleet location snapshot (all devices, latest position)
   - Q17: Idle vehicle detection (speed = 0, duration > threshold)
   - Q18: Fleet utilization by region

7. **Movement patterns**
   - Q19: Speed violations (speed_kmh > limit)
   - Q20: Stationary periods (movement_type = 'stationary')

**Expected Results**:
- **Storage**: PAX 10-15% overhead vs AOCO (many unique lat/lon coordinates)
- **Compression**: 4-6x (numeric coordinates, many VARCHAR fields)
- **Query performance**:
  - Device lookups: 4-6x faster (bloom on device_id)
  - Bounding box queries: 3-5x faster (Z-order on geohash + time)
  - Geofence queries: 5-8x faster (bloom on geofence_id)
  - **Spatial Z-order benefit**: 4-10x speedup on co-located data

**Key Validation Points**:
- ✅ Verify device_id cardinality (~100K)
- ✅ Verify trip_id cardinality (~5M)
- ✅ Verify geofence_id cardinality (~50K)
- ✅ Verify geohash_6 cardinality (depends on coverage area)
- ❌ Exclude geohash_3 from bloom filters (low cardinality, use minmax)
- ❌ Exclude movement_type from bloom filters (~10 unique)
- ⚠️  Z-order decision: geohash_4 + time vs device_id + time (depends on query pattern)

**Special Notes**:
- **Z-order on geohash**: Provides spatial co-location benefit
- **Geohash hierarchy**: Use geohash_3/4 in minmax, geohash_6 in bloom
- **Latitude/longitude**: Use minmax for range queries, bloom not helpful

**Runtime**: ~8-12 minutes
- Phase 5 (10M locations): ~4-6 min (many columns, geocoding)
- Phase 7 (clustering): ~3-5 min (spatial Z-order is compute-intensive)

---

### Scenario 6: Healthcare / Medical Records

**Business Context**: Patient vitals monitoring, lab results, medication tracking, clinical research

**Schema**:
```sql
CREATE TABLE healthcare.patient_vitals (
    -- Time dimension
    measurement_timestamp TIMESTAMP NOT NULL,
    measurement_date DATE NOT NULL,
    measurement_hour TIMESTAMP NOT NULL,

    -- Patient identifiers (PII - must protect)
    patient_id VARCHAR(64) NOT NULL,      -- ~1M patients
    medical_record_number VARCHAR(50),    -- ~1M MRNs
    encounter_id VARCHAR(64),             -- ~5M encounters

    -- Provider/facility
    provider_id VARCHAR(64),              -- ~10,000 doctors
    facility_id VARCHAR(50),              -- ~1,000 facilities
    department VARCHAR(100),              -- ~200 departments
    unit VARCHAR(100),                    -- ~500 units (ICU, ER, etc)

    -- Measurement type
    measurement_type VARCHAR(100) NOT NULL, -- ~500 measurement types
    measurement_category VARCHAR(50),      -- ~50 categories (vital/lab/imaging/etc)
    test_code VARCHAR(20),                 -- ~2,000 test codes (LOINC)
    test_name VARCHAR(200),

    -- Vital signs (sparse - not all recorded every time)
    heart_rate_bpm INTEGER,
    blood_pressure_systolic INTEGER,
    blood_pressure_diastolic INTEGER,
    temperature_celsius NUMERIC(4,2),
    respiratory_rate INTEGER,
    oxygen_saturation_percent INTEGER,

    -- Lab results (sparse - depends on test ordered)
    lab_value_numeric NUMERIC(20,6),
    lab_value_text VARCHAR(500),
    lab_unit VARCHAR(50),                  -- ~200 units (mg/dL, mmol/L, etc)
    reference_range_min NUMERIC(20,6),
    reference_range_max NUMERIC(20,6),
    is_abnormal BOOLEAN,
    abnormal_flag VARCHAR(10),             -- high/low/critical (~5 flags)

    -- Clinical context
    diagnosis_code VARCHAR(20),            -- ~70,000 ICD-10 codes
    diagnosis_description VARCHAR(500),
    severity VARCHAR(20),                  -- ~10 severity levels
    acuity VARCHAR(20),                    -- ~5 acuity levels

    -- Medication context (if applicable)
    medication_id VARCHAR(64),             -- ~10,000 medications
    medication_name VARCHAR(200),
    dosage VARCHAR(100),
    route VARCHAR(50),                     -- ~30 routes (oral/IV/etc)

    -- Device/method
    measurement_device_id VARCHAR(64),     -- ~5,000 devices
    measurement_method VARCHAR(100),       -- ~100 methods
    device_calibration_date DATE,

    -- Quality/validity
    measurement_quality VARCHAR(20),       -- ~10 quality indicators
    is_validated BOOLEAN,
    is_critical_alert BOOLEAN,
    alert_acknowledged BOOLEAN,

    -- Patient demographics (denormalized for analytics)
    patient_age_years INTEGER,
    patient_gender VARCHAR(20),            -- ~5 gender identities
    patient_race VARCHAR(50),              -- ~15 race categories
    patient_ethnicity VARCHAR(50),         -- ~10 ethnicity categories

    -- Clinical study (optional)
    study_id VARCHAR(64),                  -- ~1,000 clinical studies
    study_arm VARCHAR(50),                 -- ~5,000 study arms
    is_control_group BOOLEAN,

    -- Compliance/audit
    recorded_by_user_id VARCHAR(64),       -- ~50,000 clinical staff
    verified_by_user_id VARCHAR(64),
    measurement_source VARCHAR(50),        -- manual/auto/imported (~10 sources)

    -- Privacy/security
    data_sensitivity_level VARCHAR(20),    -- ~5 sensitivity levels
    access_log_id VARCHAR(64),

    -- Metadata
    record_id BIGINT NOT NULL,
    last_updated_timestamp TIMESTAMP,
    record_version INTEGER
) DISTRIBUTED BY (patient_id);
```

**Data Characteristics**:
- **Volume**: 50M measurements/day (testing: 10M rows)
- **Sparse schema**: Many NULL values (different tests = different fields)
- **HIPAA compliance**: Fast patient lookup required for care delivery
- **Research use**: Cohort analysis, outcome studies
- **Cardinality profile**:
  - patient_id: ~1M unique ✅ High - bloom filter (CRITICAL for care)
  - encounter_id: ~5M unique ✅ High - bloom filter
  - medical_record_number: ~1M unique ✅ High - bloom filter
  - diagnosis_code: ~70K unique ✅ High - bloom filter
  - medication_id: ~10K unique ✅ High - bloom filter
  - provider_id: ~10K unique ✅ High - bloom filter
  - measurement_type: ~500 unique ❌ Low - minmax only
  - patient_gender: ~5 unique ❌ Very low - minmax only
  - abnormal_flag: ~5 unique ❌ Very low - minmax only

**PAX Configuration Strategy**:
```sql
USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Time, numeric vitals, categorical fields
    minmax_columns='measurement_date,measurement_timestamp,heart_rate_bpm,blood_pressure_systolic,temperature_celsius,measurement_type,is_abnormal',

    -- Bloom: Patient care (critical), diagnosis, medication
    -- CRITICAL: Patient lookup must be fast for clinical care
    bloomfilter_columns='patient_id,medical_record_number,encounter_id,diagnosis_code',

    -- Z-order: Time + patient (longitudinal patient history)
    cluster_type='zorder',
    cluster_columns='measurement_date,patient_id',

    storage_format='porc'
);
```

**Query Patterns** (20 queries):

1. **Patient care** (must be fast for clinical use!)
   - Q1: All vitals for patient (patient_id lookup)
   - Q2: Recent 24 hours for patient
   - Q3: Encounter summary (encounter_id lookup)

2. **Clinical alerts**
   - Q4: All critical alerts (is_critical_alert = true)
   - Q5: Abnormal lab results (is_abnormal = true)
   - Q6: Unacknowledged alerts

3. **Vital signs monitoring**
   - Q7: Heart rate trends for patient
   - Q8: Blood pressure history
   - Q9: Temperature spikes (> 38.5°C)

4. **Lab result analysis**
   - Q10: Specific test results (test_code lookup)
   - Q11: Out-of-range labs
   - Q12: Lab turnaround time

5. **Diagnosis-based cohorts**
   - Q13: All patients with diagnosis (diagnosis_code lookup)
   - Q14: Comorbidity analysis
   - Q15: Severity distribution

6. **Medication monitoring**
   - Q16: Patients on specific medication (medication_id lookup)
   - Q17: Adverse event detection
   - Q18: Medication effectiveness

7. **Research queries**
   - Q19: Clinical study data (study_id + study_arm)
   - Q20: Outcome analysis by patient demographics

**Expected Results**:
- **Storage**: PAX 12-18% overhead vs AOCO (very sparse schema, many NULLs)
- **Compression**: 3-5x (sparse data, text fields, many NULLs)
- **Query performance**:
  - Patient lookups: 5-10x faster (CRITICAL for clinical care)
  - Diagnosis queries: 4-6x faster (bloom on diagnosis_code)
  - Longitudinal patient history: 3-5x faster (Z-order on date + patient)

**Key Validation Points**:
- ✅ Verify patient_id cardinality (~1M) - CRITICAL
- ✅ Verify encounter_id cardinality (~5M)
- ✅ Verify diagnosis_code cardinality (~70K)
- ❌ Exclude measurement_type from bloom filters (~500 unique, borderline)
- ❌ Exclude patient_gender from bloom filters (~5 unique)
- ❌ Exclude abnormal_flag from bloom filters (~5 unique)
- ⚠️  Sparse data: Many NULLs may affect compression effectiveness

**Compliance Notes**:
- **HIPAA**: Patient queries must complete quickly (<1 second)
- **Audit**: All queries logged via access_log_id
- **Privacy**: data_sensitivity_level determines access control

**Runtime**: ~8-12 minutes
- Phase 5 (10M measurements): ~4-6 min (sparse schema, many columns)
- Phase 7 (clustering): ~3-4 min

---

## Implementation Order and Dependencies

### Phase 1: Framework Setup ✅ COMPLETED
- [x] Create shared validation framework
- [x] Create IoT benchmark (reference implementation)
- [x] Document lessons learned (CLAUDE.md updated)

### Phase 2: High-Density Time-Series (Scenarios 1-2)
**Order**: Financial Trading → Log Analytics

**Rationale**: Both are time-series dominant, validate bloom filters on different cardinality profiles

**Duration**: ~4-6 hours total

### Phase 3: Multi-Dimensional Analytics (Scenarios 3-4)
**Order**: E-commerce Clickstream → Telecommunications CDR

**Rationale**: Both have multiple high-cardinality dimensions, test Z-order effectiveness

**Duration**: ~4-6 hours total

### Phase 4: Specialized Patterns (Scenarios 5-6)
**Order**: Geospatial Location → Healthcare Records

**Rationale**: Test spatial Z-order (geohash), then sparse schema (healthcare)

**Duration**: ~4-6 hours total

---

## Unified Comparison Framework

After all scenarios are complete, create comprehensive cross-scenario analysis:

### Comparison Dimensions

1. **Storage Efficiency**
   - PAX overhead % vs AOCO
   - Compression ratios
   - Per-column encoding effectiveness

2. **Query Performance**
   - Bloom filter speedup by cardinality tier
   - Z-order clustering benefit by dimensionality
   - Sparse filtering effectiveness

3. **Configuration Patterns**
   - Bloom filter column selection rules
   - Z-order column selection patterns
   - Memory requirements by row count

4. **Workload Characteristics**
   - Time-series density impact
   - Schema width impact (column count)
   - Data sparsity impact (NULL %)

### Final Deliverables

**Cross-Scenario Report** (`results/unified_comparison/`):
```
all_scenarios_summary.md              # Executive summary
storage_comparison.csv                # Storage metrics table
query_performance.csv                 # Performance metrics table
configuration_patterns.md             # Best practices by workload type
lessons_learned.md                    # Production deployment guide
pax_decision_tree.md                  # When to use PAX (decision flowchart)
```

**Summary Table**:
| Scenario | Rows | Storage Overhead | Bloom Speedup | Z-order Speedup | Config Complexity | Validation Critical? |
|----------|------|-----------------|---------------|-----------------|-------------------|---------------------|
| IoT | 10M | 3.3% | 1.4x | 2.4x | Low | ✅ High |
| Financial | 10M | 5-10% | 2-3x | 3-5x | Medium | ✅ High |
| Log Analytics | 10M | 10-15% | 3-5x | 2-3x | High | ✅ Critical |
| E-commerce | 10M | 8-12% | 4-6x | 2-3x | High | ✅ High |
| Telecom | 10M | 7-10% | 5-10x | 3-5x | Medium | ✅ Critical |
| Geospatial | 10M | 10-15% | 4-6x | 4-10x | High | ✅ High |
| Healthcare | 10M | 12-18% | 5-10x | 3-5x | High | ✅ Critical |

---

## Success Criteria

Each scenario must demonstrate:

1. ✅ **Validation Framework Success**
   - All 4 safety gates pass
   - Zero bloom filter misconfiguration
   - Correct memory calculation

2. ✅ **Storage Efficiency**
   - PAX overhead < 20% vs AOCO
   - Compression ratio > 3x
   - No catastrophic bloat (>50%)

3. ✅ **Query Performance**
   - Bloom filter queries: 2x+ faster
   - Z-order range queries: 2x+ faster
   - No performance regressions

4. ✅ **Documentation**
   - README with expected results
   - Cardinality analysis documented
   - Configuration rationale explained

5. ✅ **Reproducibility**
   - Single script execution
   - Runtime < 15 minutes
   - Clear pass/fail criteria

---

## Next Steps

**Immediate Action**: Implement Scenario 1 (Financial Trading)

**Command**:
```bash
mkdir -p financial_trading_benchmark/{sql,scripts,results}
cd financial_trading_benchmark
# Start with 01_setup_schema.sql
```

**Questions to resolve before starting**:
1. Confirm scenario order: Financial → Log → Ecommerce → Telecom → Geospatial → Healthcare?
2. Dataset size: Continue with 10M rows for all scenarios?
3. Should shared/validation_framework.sql be extracted from IoT benchmark for reuse?

---

**Status**: Ready to implement Scenario 1 (Financial Trading)
**Last Updated**: October 29, 2025
