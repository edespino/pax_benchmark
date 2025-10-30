# Known Limitations - Streaming INSERT Benchmark

This document tracks limitations discovered during benchmark development and execution.

---

## 1. TIMESTAMP Type Not Supported for Z-Order Clustering

**Discovered**: October 30, 2025
**Cloudberry Version**: 3.0.0-devel+dev.2154.gda0b9d4fe08
**Error**: `the type of column call_timestamp does not support zorder cluster (pax_access_handle.cc:1093)`

### Issue

PAX's Z-order clustering does not support TIMESTAMP columns in the current Cloudberry version. Attempting to use a TIMESTAMP column in `cluster_columns` results in table creation failure.

### Original Configuration (Failed)
```sql
CREATE TABLE cdr.cdr_pax (...) USING pax WITH (
    cluster_type='zorder',
    cluster_columns='call_timestamp,cell_tower_id',  -- ❌ TIMESTAMP not supported
    ...
);
```

### Workaround Applied
```sql
CREATE TABLE cdr.cdr_pax (...) USING pax WITH (
    cluster_type='zorder',
    cluster_columns='call_date,cell_tower_id',  -- ✅ DATE type works
    ...
);
```

### Impact

**Clustering Granularity**:
- **Original intent**: Cluster by timestamp (second-level precision) + cell_tower_id
- **Actual implementation**: Cluster by date (day-level precision) + cell_tower_id
- **Effect**: Coarser clustering than intended, but still provides multi-dimensional benefits

**Query Performance**:
- Queries filtering by exact timestamp: May scan entire day's data
- Queries filtering by date range: Should see full Z-order benefits
- Recommendation: Add `call_hour` to `minmax_columns` for finer-grained pruning within dates

**Storage Efficiency**:
- Clustering overhead may be slightly lower (fewer unique combinations)
- Data locality within day + tower still provides compression benefits

### Supported Types for Z-Order (Observed)

**Confirmed Working**:
- INTEGER
- BIGINT
- DATE
- TEXT/VARCHAR

**Confirmed NOT Working**:
- TIMESTAMP
- TIMESTAMPTZ

**Not Yet Tested**:
- NUMERIC
- FLOAT/REAL
- SMALLINT

### Recommendations

1. **For time-series data**: Use DATE + separate hour/minute columns
   ```sql
   cluster_columns='event_date,event_hour,location_id'
   minmax_columns='event_date,event_hour,event_minute,...'
   ```

2. **For high-precision timestamps**: Convert to BIGINT (epoch milliseconds)
   ```sql
   -- Add derived column
   timestamp_ms BIGINT GENERATED ALWAYS AS
       (EXTRACT(EPOCH FROM event_timestamp) * 1000) STORED

   -- Use in clustering
   cluster_columns='timestamp_ms,location_id'
   ```

3. **For this benchmark**: Current DATE-based approach is acceptable
   - Still tests Z-order clustering fundamentals
   - Still validates multi-dimensional performance
   - Documents real limitation for production users

### Future Work

- Test workaround #2 (BIGINT epoch timestamps) in separate benchmark
- File issue with Cloudberry team to add TIMESTAMP support
- Update PAX documentation to clarify supported types

---

## 2. Other Limitations (To Be Documented)

### Placeholder for Future Discoveries

As the benchmark executes and is tested in different environments, additional limitations may be discovered and documented here.

---

**Last Updated**: October 30, 2025
**Benchmark Version**: Phase 1 (PL/pgSQL implementation)
