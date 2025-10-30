# E-commerce Clickstream Benchmark

**Benchmark Duration**: 8-12 minutes  
**Dataset Size**: 10M clickstream events (~2M sessions, ~500K users, ~100K products)  
**Focus**: Multi-dimensional user behavior, funnel analysis, session tracking

---

## Overview

This benchmark validates PAX storage performance for e-commerce clickstream analytics—one of the most common modern data warehouse workloads. Tests session tracking (bloom filters), funnel analysis (Z-order clustering), and sparse product data.

### Key Features Tested

- **Session Analysis**: Bloom filters on `session_id` (~2M unique), `user_id` (~500K unique)
- **Product Analytics**: Bloom filters on `product_id` (~100K unique)
- **Funnel Patterns**: Z-order clustering on `event_hour` + `session_id`
- **Sparse Data**: 60-70% NULL in product/user fields
- **Multi-Dimensional**: 40 columns with mixed cardinality

---

## Dataset Characteristics

### Volume
- **10M events** across 7 days
- **~2M sessions** (avg 5 events per session, power law distribution)
- **~500K registered users** (30% of events)
- **~100K products**
- **~500 marketing campaigns**

### Event Distribution (Realistic Funnel)
- 40% page views
- 20% product views
- 10% product list views
- 5% add to cart
- 3% begin checkout
- 2% purchases ✅

### Cardinality Profile
| Column | Cardinality | Bloom Filter |
|--------|-------------|--------------|
| session_id | ~2M | ✅ High |
| product_id | ~100K | ✅ High |
| user_id | ~500K | ✅ High |
| anonymous_id | ~3M | ❌ Not needed |
| event_type | ~30 | ❌ Low (minmax only) |
| device_type | 3 | ❌ Very low (minmax only) |
| country_code | ~200 | ❌ Low (minmax only) |

### Sparse Columns (PAX Advantage)
- `product_id`: 60% NULL (non-product events)
- `user_id`: 70% NULL (anonymous sessions)
- `utm_campaign`: 40% NULL (organic traffic)

---

## PAX Configuration

```sql
CREATE TABLE ecommerce.clickstream_pax (...) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Low overhead, ALL filterable columns (8 columns)
    minmax_columns='event_date,event_timestamp,event_type,
                    product_category,device_type,country_code,
                    cart_value,is_returning_customer',

    -- Bloom: ONLY high-cardinality (3 columns validated >10K)
    bloomfilter_columns='session_id,user_id,product_id',

    -- Z-order: Time + session (funnel analysis pattern)
    cluster_type='zorder',
    cluster_columns='event_date,session_id',

    storage_format='porc'
);
```

**Configuration Rationale**:
- **3 bloom filters**: session_id, user_id, product_id (all >10K cardinality)
- **8 minmax columns**: Low overhead, filters on time/event/device/geography
- **Z-order (event_date + session_id)**: Optimizes funnel analysis queries (session journey over time)

---

## Query Categories (12 Queries)

| Category | Queries | PAX Feature Tested |
|----------|---------|-------------------|
| **1. Session Analysis** | Q1-Q2 | Bloom filters on session_id, user_id |
| **2. Funnel Analysis** | Q3-Q4 | Z-order clustering, time filtering |
| **3. Product Analytics** | Q5-Q6 | Bloom filter on product_id, sparse filtering |
| **4. Real-time Dashboards** | Q7-Q8 | MinMax on event_timestamp (recent data) |
| **5. Marketing Attribution** | Q9-Q10 | Sparse columns (utm_*), aggregations |
| **6. Device & Geography** | Q11-Q12 | MinMax on device_type, country_code |

---

## Expected Results

### Storage (Optimized Configuration)
- **AO**: ~900 MB (row-oriented baseline)
- **AOCO**: ~600 MB (column-oriented baseline)
- **PAX no-cluster**: ~630 MB (+5% vs AOCO) ✅
- **PAX clustered**: ~720 MB (+20% vs AOCO) ✅

### Compression
- **AO**: 2.5-3x
- **AOCO**: 4-5x
- **PAX no-cluster**: 4-5x
- **PAX clustered**: 3.5-4.5x

### Query Performance (Expected with file-level pruning enabled)
- **Session lookups (Q1-Q2)**: 4-6x faster (bloom on session_id)
- **Product queries (Q5-Q6)**: 3-4x faster (bloom on product_id)
- **Funnel queries (Q3-Q4)**: 2-3x faster (Z-order on time + session)
- **Real-time dashboards (Q7-Q8)**: 3-5x faster (minmax on timestamp)

**Note**: Query performance depends on file-level predicate pushdown being enabled in PAX scanner code.

---

## Validation Gates

### Gate 1: Row Count Consistency
- All 4 variants must have exactly 10M rows

### Gate 2: PAX Configuration Bloat Check
- PAX no-cluster: ≤20% overhead vs AOCO
- PAX clustered: ≤40% overhead vs AOCO

### Gate 3: Sparse Column Verification
- product_id: 55-65% NULL ✅
- user_id: 65-75% NULL ✅
- utm_campaign: 35-45% NULL ✅

### Gate 4: Cardinality Verification
- session_id: ≥10K unique (bloom filter validated)
- user_id: ≥10K unique (bloom filter validated)
- product_id: ≥10K unique (bloom filter validated)
- event_type: <100 unique (minmax only, correct)
- device_type: <10 unique (minmax only, correct)

---

## Execution

### Quick Start
```bash
cd benchmarks/ecommerce_clickstream
./scripts/run_clickstream_benchmark.sh
```

**Runtime**: 8-12 minutes
- Phase 0-4: Setup (1-2 min)
- Phase 5: Data generation (3-5 min)
- Phase 6: Z-order clustering (3-5 min)
- Phase 7-9: Queries + validation (1-2 min)

### Manual Execution
```bash
psql -f sql/00_validation_framework.sql  # Validation functions
psql -f sql/01_setup_schema.sql          # Dimension tables
psql -f sql/02_analyze_cardinality.sql   # 1M sample validation
psql -f sql/03_generate_config.sql       # Auto-generate config
psql -f sql/04_create_variants.sql       # 4 storage variants
psql -f sql/05_generate_data.sql         # 10M events (3-5 min)
psql -f sql/06_optimize_pax.sql          # Z-order clustering (3-5 min)
psql -f sql/07_run_queries.sql           # 12 queries × 4 variants
psql -f sql/08_collect_metrics.sql       # Storage comparison
psql -f sql/09_validate_results.sql      # Final validation
```

---

## Production Recommendations

### When to Use PAX for Clickstream
✅ **Recommended**:
- High session/user lookup frequency (bloom filters shine)
- Funnel analysis queries (Z-order clustering benefit)
- Sparse product/user data (70% NULL - PAX sparse filtering advantage)
- Multi-dimensional filtering (time × session × product)

⚠️  **Consider Carefully**:
- Pure time-series scans (AOCO may be sufficient)
- Very wide schemas (>100 columns) without selectivity
- Workloads with < 1000 distinct values per column (bloom filter bloat risk)

### Configuration Guidelines
1. **Bloom filters**: ONLY columns with >10K unique values
   - ✅ session_id, user_id, product_id
   - ❌ event_type, device_type, country_code
2. **MinMax columns**: ALL filterable columns (low overhead)
3. **Z-order clustering**: 2-3 correlated dimensions
   - Funnel analysis: time + session_id
   - Product-centric: time + product_id
4. **Memory**: Set `maintenance_work_mem=2GB` BEFORE clustering (10M rows)

---

## Key Findings

### Strengths
- ✅ **Session lookups**: Bloom filters on session_id enable fast user journey reconstruction
- ✅ **Sparse data**: 60-70% NULL columns (product/user fields) compress efficiently
- ✅ **Multi-dimensional queries**: Z-order clustering accelerates funnel analysis
- ✅ **Storage overhead**: PAX no-cluster adds only 5% vs AOCO

### Considerations
- ⚠️  **Clustering overhead**: 20-40% larger than no-cluster (depends on bloom filter count)
- ⚠️  **Wide schemas**: 40 columns → more metadata overhead than narrow tables
- ⚠️  **Marketing fields**: Sparse campaign data (40% NULL) → validate bloom filter benefit

---

## Comparison with Other Benchmarks

| Benchmark | Focus | PAX Strength | Expected Overhead |
|-----------|-------|--------------|-------------------|
| **IoT** | Time-series | Temporal filtering | +3% (no bloom) |
| **Trading** | High-frequency | High-cardinality bloom | +2% (12 bloom → 58% with cluster) |
| **Logs** | Text-heavy | Sparse columns (95% NULL) | +4% (text bloom bloat) |
| **Clickstream** | User behavior | Session tracking, funnels | +5-8% |

**Clickstream Uniqueness**: Combines high-cardinality session IDs with sparse product data and multi-dimensional funnel patterns.

---

## Troubleshooting

**High storage overhead?**
- Check bloom filter cardinality: `SELECT COUNT(DISTINCT session_id) FROM ...`
- Verify only >10K cardinality columns have bloom filters
- Review sparse column NULL percentages

**Slow session lookups?**
- Verify bloom filters on session_id and user_id
- Check PAX sparse filter setting: `SHOW pax.enable_sparse_filter;`
- Ensure file-level predicate pushdown is enabled (code-level)

**Clustering takes too long?**
- Increase `maintenance_work_mem` (2GB for 10M rows)
- Validate memory: `psql -f sql/04a_validate_clustering_config.sql` (if available)

---

**Part of PAX Benchmark Suite**  
See `/benchmarks/README.md` for suite overview and benchmark selection guide.
