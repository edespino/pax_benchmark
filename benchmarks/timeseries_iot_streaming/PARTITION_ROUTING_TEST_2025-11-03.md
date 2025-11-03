# Partition Routing Test Results - November 3, 2025

## Test Objective

Validate that partitioned tables correctly route data to the appropriate partition based on `call_date` column.

**Test Date**: 2025-11-03
**Duration**: 5 minutes

---

## Test Environment

**Database**: Cloudberry 3.0.0-devel
**Partitioning Type**: RANGE on `call_date`
**Partition Count**: 24 partitions per variant (96 total)
**Date Range**: 2024-01-01 through 2024-01-25

---

## Test Results

### ✅ Partition Creation

**Command**: `psql -f sql/04c_create_variants_PARTITIONED.sql`

**Result**: SUCCESS

**Partitions Created**:
- ✅ AO variant: 24 partitions (cdr_ao_part_day00 through cdr_ao_part_day23)
- ✅ AOCO variant: 24 partitions (cdr_aoco_part_day00 through cdr_aoco_part_day23)
- ✅ PAX variant: 24 partitions (cdr_pax_part_day00 through cdr_pax_part_day23)
- ✅ PAX-no-cluster variant: 24 partitions (cdr_pax_nocluster_part_day00 through cdr_pax_nocluster_part_day23)

**Total**: 96 partition tables

---

### ✅ Partition Routing Test (AO Variant)

**Test Data**: 4 test rows inserted into `cdr.cdr_ao_partitioned`

| call_id | call_date | Expected Partition | Actual Partition | Status |
|---------|-----------|-------------------|------------------|--------|
| test-hour-0 | 2024-01-01 | day00 | day00 (1 row) | ✅ PASS |
| test-hour-5 | 2024-01-06 | day05 | day05 (1 row) | ✅ PASS |
| test-hour-12 | 2024-01-13 | day12 | day12 (1 row) | ✅ PASS |
| test-hour-23 | 2024-01-24 | day23 | day23 (1 row) | ✅ PASS |

**Parent Table Aggregate**: 4 rows (correct sum across all partitions)

---

### ✅ Partition Routing Test (PAX Variant)

**Test Data**: 2 test rows inserted into `cdr.cdr_pax_partitioned`

| call_id | call_date | Expected Partition | Actual Partition | Status |
|---------|-----------|-------------------|------------------|--------|
| pax-test-hour-7 | 2024-01-08 | day07 | day07 (1 row) | ✅ PASS |
| pax-test-hour-18 | 2024-01-19 | day18 | day18 (1 row) | ✅ PASS |

**Parent Table Aggregate**: 2 rows (correct sum)

---

## Validation

### Hour-to-Date Mapping

The partition routing correctly maps hour values to dates as designed:

```
Hour 0  → call_date = '2024-01-01' → partition day00 ✓
Hour 1  → call_date = '2024-01-02' → partition day01 (not tested)
...
Hour 5  → call_date = '2024-01-06' → partition day05 ✓
Hour 7  → call_date = '2024-01-08' → partition day07 ✓
...
Hour 12 → call_date = '2024-01-13' → partition day12 ✓
...
Hour 18 → call_date = '2024-01-19' → partition day18 ✓
...
Hour 23 → call_date = '2024-01-24' → partition day23 ✓
```

---

## Key Findings

### ✅ Successful

1. **Partition Creation**: All 96 partitions created without errors
2. **Automatic Routing**: PostgreSQL correctly routes INSERTs to partitions based on `call_date`
3. **Parent Aggregation**: Parent tables correctly aggregate data from child partitions
4. **PAX Compatibility**: PAX storage format works correctly with partitioning
5. **Distribution**: Partitions inherit `DISTRIBUTED BY (call_id)` from parent

---

## SQL Function Test

The `generate_cdr_batch_partitioned()` function correctly generates `call_date` based on hour:

```sql
-- Function logic (validated)
call_date := DATE '2024-01-01' + p_hour

-- Examples:
p_hour = 0  → call_date = '2024-01-01'
p_hour = 5  → call_date = '2024-01-06'
p_hour = 12 → call_date = '2024-01-13'
p_hour = 23 → call_date = '2024-01-24'
```

This ensures each batch of streaming INSERTs routes to the correct partition.

---

## Next Steps

### Immediate

1. ✅ **Partition routing validated** - Core mechanism works
2. ⚠️ **Proceed with Phase 1 test** - Run `sql/06b_streaming_inserts_noindex_PARTITIONED.sql`
3. ⚠️ **Create metrics/validation scripts** - Required for benchmark analysis

### Phase 1 Test Plan

```bash
# Expected runtime: 15-20 minutes
# Expected data: ~42M rows distributed across 96 partitions (~437K rows/partition)

cd benchmarks/timeseries_iot_streaming
psql -f sql/06b_streaming_inserts_noindex_PARTITIONED.sql
```

**Success Criteria**:
- ✅ All 500 batches complete without errors
- ✅ Data distributed across 24 partitions per variant
- ✅ Each partition contains ~1.74M rows
- ✅ INSERT throughput similar to monolithic (~260-310K rows/sec)

---

## Technical Notes

### PostgreSQL Partitioning Behavior

**Automatic Partition Selection**:
- PostgreSQL automatically routes INSERTs to the correct partition based on partition constraints
- No explicit partition name needed in INSERT statement
- Parent table acts as a router

**Example**:
```sql
-- User code (no partition logic)
INSERT INTO cdr.cdr_pax_partitioned (...) VALUES (..., '2024-01-08', ...);

-- PostgreSQL internally routes to:
INSERT INTO cdr.cdr_pax_part_day07 (...) VALUES (...);
```

**Query Behavior**:
```sql
-- Query parent table
SELECT * FROM cdr.cdr_pax_partitioned WHERE call_date = '2024-01-08';

-- PostgreSQL performs partition pruning:
-- - Scans only cdr_pax_part_day07
-- - Skips other 23 partitions
-- - Result: 24x smaller scan for date-filtered queries
```

---

## Warnings/Notices

**ANALYZE Notices**:
```
NOTICE:  One or more columns in the following table(s) do not have statistics
HINT:  For partitioned tables, run analyze rootpartition <table_name>
```

**Resolution**: This is expected for new tables. ANALYZE will be run:
- During streaming INSERT checkpoint (every 100 batches)
- After final data load completion

**Impact**: None for partition routing test (small dataset)

---

## Conclusion

**Status**: ✅ **VALIDATION SUCCESSFUL**

All partition routing tests passed:
- 96 partitions created correctly
- Data routes to correct partitions based on `call_date`
- Both AO and PAX variants work correctly
- Parent tables aggregate child partition data

**Ready for**: Phase 1 full streaming INSERT test with partitioned tables

---

## Cleanup (If Needed)

To remove test data:
```sql
TRUNCATE TABLE cdr.cdr_ao_partitioned;
TRUNCATE TABLE cdr.cdr_pax_partitioned;
```

To remove all partitioned tables:
```sql
DROP TABLE IF EXISTS cdr.cdr_ao_partitioned CASCADE;
DROP TABLE IF EXISTS cdr.cdr_aoco_partitioned CASCADE;
DROP TABLE IF EXISTS cdr.cdr_pax_partitioned CASCADE;
DROP TABLE IF EXISTS cdr.cdr_pax_nocluster_partitioned CASCADE;
```

---

**Test Completed**: 2025-11-03
**Tester**: Claude Code
**Result**: ✅ PASS - Ready for Phase 1 full test
