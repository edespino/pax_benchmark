# PAX Benchmark Suite

Four comprehensive benchmarks for evaluating PAX storage performance in Apache Cloudberry Database.

---

## Quick Reference

| Benchmark | Dataset | Rows | Runtime | Use Case |
|-----------|---------|------|---------|----------|
| **[retail_sales](retail_sales/)** | Sales transactions | 200M | 2-4 hrs | Large-scale comprehensive validation |
| **[timeseries_iot](timeseries_iot/)** | IoT sensor readings | 10M | 2-5 min | Fast iteration, validation-first framework |
| **[financial_trading](financial_trading/)** | High-frequency ticks | 10M | 4-8 min | High-cardinality column testing |
| **[log_analytics](log_analytics/)** | Application logs | 10M | 3-6 min | Sparse column testing, observability workloads |

---

## Benchmark Descriptions

### 1. Retail Sales Analytics (`retail_sales/`)

**Original PAX benchmark** - Comprehensive sales analytics workload.

- **Dataset**: 200M sales transactions, 10M customers, 100K products
- **Size**: ~210GB total (~70GB per variant)
- **Runtime**: 2-4 hours for full benchmark (10 min for small 1M row test)
- **Queries**: 20 analytical queries across 7 categories
- **Best for**: Large-scale production validation

**Run it**:
```bash
cd benchmarks/retail_sales
./scripts/run_full_benchmark.sh                 # Full 200M row benchmark
# OR for quick test:
psql -f sql/03_generate_data_SMALL.sql          # 1M rows only
```

---

### 2. IoT Time-Series (`timeseries_iot/`)

**Validation-first framework** - Fast iteration with 4 safety gates.

- **Dataset**: 10M IoT sensor readings from 100K devices
- **Size**: ~5GB total
- **Runtime**: 2-5 minutes
- **Safety gates**: Cardinality validation, auto-config generation, bloat detection
- **Best for**: Development, configuration testing, CI/CD validation

**Run it**:
```bash
cd benchmarks/timeseries_iot
./scripts/run_iot_benchmark.sh
```

**Key innovation**: Validates bloom filter cardinality BEFORE table creation to prevent 80%+ storage bloat.

---

### 3. Financial Trading (`financial_trading/`)

**High-cardinality workload** - Tests bloom filter effectiveness.

- **Dataset**: 10M trading ticks, 5K symbols, 20 exchanges
- **Size**: ~10GB total
- **Runtime**: 4-8 minutes
- **Safety gates**: 4 validation checkpoints (same as IoT)
- **Best for**: High-cardinality column validation, production PAX tuning

**Run it**:
```bash
cd benchmarks/financial_trading
./scripts/run_trading_benchmark.sh
```

**Notable finding**: 12 bloom filter columns caused 62% clustering overhead (vs 26% with 1-2 columns).

---

### 4. Log Analytics / Observability (`log_analytics/`)

**Sparse column showcase** - Tests PAX advantage on NULL-heavy data.

- **Dataset**: 10M log entries from 200 microservices
- **Size**: ~5-10GB total
- **Runtime**: 3-6 minutes
- **Safety gates**: 4 validation checkpoints (same as IoT/Trading)
- **Best for**: APM/observability testing, sparse column validation, text-heavy workloads

**Run it**:
```bash
cd benchmarks/log_analytics
./scripts/run_log_benchmark.sh
```

**Key innovation**: Tests PAX sparse filtering on highly NULL columns (95% NULL for stack_trace, error_code). Validates bloom filters on high-cardinality identifiers (trace_id, request_id).

**Dataset characteristics**:
- **Sparse columns**: stack_trace (95% NULL), error_code (95% NULL), user_id (30% NULL)
- **High-cardinality**: trace_id, request_id (~10M unique each)
- **Low-cardinality**: log_level (6 values), application_id (200 values)
- **Realistic distribution**: 80% INFO, 15% WARN, 4% ERROR, 1% FATAL

**Query categories**: Time filtering, bloom filters, Z-order clustering, sparse columns, HTTP performance, multi-dimensional analysis

---

## Common Features

All benchmarks test:
- ✅ **4 storage variants**: AO, AOCO, PAX (clustered), PAX (no-cluster)
- ✅ **Storage efficiency**: Compression ratios, overhead analysis
- ✅ **Z-order clustering**: Multi-dimensional space-filling curves
- ✅ **PAX features**: Sparse filtering, bloom filters, per-column encoding

---

## Choosing a Benchmark

**Start development?** → Use `timeseries_iot` (2-5 min, validation-first)

**Testing bloom filters?** → Use `financial_trading` (4-8 min, high cardinality)

**Testing sparse columns?** → Use `log_analytics` (3-6 min, 95% NULL data)

**APM/observability data?** → Use `log_analytics` (text-heavy, realistic log distributions)

**Production validation?** → Use `retail_sales` (2-4 hrs, comprehensive)

**Testing new config?** → Use `timeseries_iot` first (fast), then `retail_sales` (thorough)

---

## Results Location

Each benchmark creates timestamped results:
```
benchmarks/
├── retail_sales/results/run_YYYYMMDD_HHMMSS/
├── timeseries_iot/results/run_YYYYMMDD_HHMMSS/
├── financial_trading/results/run_YYYYMMDD_HHMMSS/
└── log_analytics/results/run_YYYYMMDD_HHMMSS/
```

---

## Key Learnings (October 2025)

### ✅ PAX Configuration Best Practices

1. **Always validate bloom filter cardinality first** (use IoT/Trading frameworks)
2. **Set maintenance_work_mem appropriately** (2GB for 10M rows, 8GB for 200M)
3. **Limit bloom filters to 1-3 high-cardinality columns** (>1000 unique values)
4. **Use minmax_columns liberally** (low overhead, works for all cardinalities)
5. **PAX no-cluster is production-ready** (3-5% overhead vs AOCO)

### ❌ Common Pitfalls

- **Low-cardinality bloom filters**: Cause 80%+ storage bloat
- **Too many bloom filters**: 12 columns caused 62% clustering overhead
- **Insufficient clustering memory**: Causes 2-3x storage bloat
- **No validation**: Silent failures, bloat appears gradually

---

## Documentation

Each benchmark includes:
- `README.md` - Detailed usage and configuration guide
- `sql/` - All SQL scripts with inline comments
- `scripts/` - Automation and analysis tools
- `results/` - Historical test results and analysis

See individual benchmark READMEs for detailed documentation.

---

## Related Documentation

- `../README.md` - Main repository overview
- `../CLAUDE.md` - AI assistant guidance and project context
- `../docs/TECHNICAL_ARCHITECTURE.md` - PAX internals (2,450+ lines)
- `../docs/CONFIGURATION_GUIDE.md` - Production tuning guide
