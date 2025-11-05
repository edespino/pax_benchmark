Timing is on.
====================================================
Streaming Benchmark - Phase 3: Generate PAX Config
====================================================

Creating temporary sample for config generation...
psql:/home/cbadmin/bom-parts/pax_benchmark/benchmarks/timeseries_iot_streaming/sql/03_generate_config.sql:36: NOTICE:  Table doesn't have 'DISTRIBUTED BY' clause. Creating a NULL policy entry.
SELECT 100000
Time: 91.153 ms
ANALYZE
Time: 59.774 ms
  ✓ Sample created

Generating safe PAX configuration...

====================================================
                        generate_pax_config                        
-------------------------------------------------------------------
 --                                                               +
 -- Auto-Generated PAX Configuration                              +
 -- Generated: 2025-11-03 13:25:08.02342-08                       +
 -- Target rows: 50000000                                         +
 -- Bloom filter columns: NONE (no high-cardinality columns found)+
 -- MinMax columns: NONE                                          +
 -- Required memory: 12000MB                                      +
 --                                                               +
                                                                  +
 CREATE TABLE cdr.your_table_name (...) USING pax WITH (          +
     -- Core compression                                          +
     compresstype='zstd',                                         +
     compresslevel=5,                                             +
                                                                  +
     -- Bloom filters: NONE (no columns met cardinality threshold)+
     -- bloomfilter_columns='',  -- Intentionally empty           +
                                                                  +
     -- Z-order clustering                                        +
     cluster_type='zorder',                                       +
     cluster_columns='call_timestamp,cell_tower_id',              +
                                                                  +
     -- Storage format                                            +
     storage_format='porc'                                        +
 );                                                               +
                                                                  +
 -- CRITICAL: Set maintenance_work_mem BEFORE clustering          +
 SET maintenance_work_mem = '12000MB';                            +
 CLUSTER your_table_name USING your_zorder_index;                 +
 
(1 row)

Time: 33.331 ms
====================================================

DROP TABLE
Time: 9.838 ms
Configuration generation complete!

Copy the configuration above to 04_create_variants.sql

Next: Phase 4 - Create table variants (AO/AOCO/PAX/PAX-no-cluster)
