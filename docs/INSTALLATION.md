# PAX Benchmark - Installation Guide

Complete setup instructions for running the PAX storage benchmark suite.

---

## Prerequisites

### System Requirements
- **OS**: Linux (tested on RHEL/CentOS, Ubuntu)
- **Disk**: 300GB+ free space
- **Memory**: 8GB+ per segment (24GB+ for 3-segment cluster)
- **CPU**: 4+ cores recommended

### Required Software
- **GCC/G++**: 8.0+
- **CMake**: 3.11+
- **Protobuf**: 3.5.0+
- **ZSTD**: 1.4.0+
- **PostgreSQL**: 14+ (via Cloudberry)

### Optional Software
- **Python 3**: For result analysis and charts
  - matplotlib
  - seaborn

---

## Installation Steps

### 1. Clone Apache Cloudberry

```bash
# Clone repository
git clone https://github.com/apache/cloudberry.git
cd cloudberry

# Initialize submodules (required for PAX)
git submodule update --init --recursive
```

### 2. Configure with PAX Enabled

```bash
# Configure with PAX and recommended options
./configure \
    --enable-pax \
    --with-perl \
    --with-python \
    --with-libxml \
    --with-gssapi \
    --prefix=/usr/local/cloudberry

# For faster builds (optional, disables extra components):
# --disable-orca --disable-pxf
```

**Important**: The `--enable-pax` flag is mandatory. Without it, PAX will not be available.

### 3. Build and Install

```bash
# Build (use -j for parallel compilation)
make -j8
make -j8 install

# Add to PATH
echo 'source /usr/local/cloudberry/greenplum_path.sh' >> ~/.bashrc
source ~/.bashrc
```

**Build time**: 15-30 minutes depending on system

### 4. Create Demo Cluster

```bash
# Create 3-segment demo cluster
make create-demo-cluster

# Source environment
source gpAux/gpdemo/gpdemo-env.sh

# Verify cluster is running
psql -c "SELECT version();"
```

**Demo cluster specs**:
- 1 coordinator
- 3 segments
- Ports: 7000 (coordinator), 7002-7004 (segments)

### 5. Verify PAX Installation

```bash
# Check PAX access method is available
psql -c "SELECT amname FROM pg_am WHERE amname = 'pax';"

# Expected output:
#  amname
# --------
#  pax
# (1 row)

# If empty, rebuild with --enable-pax
```

### 6. Install Python Dependencies (Optional)

```bash
# For chart generation
pip3 install matplotlib seaborn

# Verify installation
python3 -c "import matplotlib, seaborn; print('Charts enabled')"
```

---

## Environment Configuration

### Connection Settings

```bash
# Default settings (usually work with demo cluster)
export PGHOST=localhost
export PGPORT=7000
export PGDATABASE=postgres
export PGUSER=$USER

# Test connection
psql -c "SELECT current_database();"
```

### Resource Limits

```bash
# Increase file descriptor limits (for large datasets)
ulimit -n 65536

# Check current limits
ulimit -a
```

---

## Benchmark Setup

### 1. Clone/Copy Benchmark Suite

```bash
# If standalone repository
git clone <your-pax-benchmark-repo-url>
cd pax_benchmark

# Or copy from development location
cp -r /path/to/pax_benchmark ~/
cd ~/pax_benchmark
```

### 2. Verify File Structure

```bash
# Check all required files exist
ls -la sql/
ls -la scripts/
ls -la docs/

# Ensure scripts are executable
chmod +x scripts/*.sh scripts/*.py
```

### 3. Test Connectivity

```bash
# Test psql access
psql -f sql/01_setup_schema.sql --dry-run 2>/dev/null && echo "OK" || echo "FAILED"

# Check disk space
df -h .
# Ensure 300GB+ available
```

---

## Quick Validation

Run a minimal test before full benchmark:

```bash
# Create test table
psql -c "CREATE TABLE pax_test (id int, data text) USING pax DISTRIBUTED BY (id);"

# Insert data
psql -c "INSERT INTO pax_test SELECT i, 'test' FROM generate_series(1,1000) i;"

# Query
psql -c "SELECT COUNT(*) FROM pax_test;"

# Check auxiliary table
psql -c "SELECT * FROM get_pax_aux_table('pax_test');"

# Cleanup
psql -c "DROP TABLE pax_test;"
```

Expected: No errors, query returns 1000 rows

---

## Troubleshooting

### PAX Not Found

**Symptom**: `ERROR: access method "pax" does not exist`

**Solution**:
```bash
cd /path/to/cloudberry
./configure --enable-pax --with-perl --with-python --with-libxml
git submodule update --init --recursive
make clean && make -j8 && make install

# Restart cluster
pg_ctl stop -D gpAux/gpdemo/datadirs/qddir/demoDataDir-1
make create-demo-cluster
source gpAux/gpdemo/gpdemo-env.sh
```

### Build Failures

**Symptom**: Compilation errors

**Common causes**:
1. Missing dependencies: `sudo yum install -y gcc-c++ cmake protobuf-devel libzstd-devel`
2. Submodules not initialized: `git submodule update --init --recursive`
3. Old compiler: Requires GCC 8+

### Cluster Won't Start

**Symptom**: `pg_ctl: could not start server`

**Solution**:
```bash
# Check logs
tail -100 gpAux/gpdemo/datadirs/qddir/demoDataDir-1/log/*.csv

# Common fixes:
# 1. Port already in use
lsof -i :7000  # Kill process or change port

# 2. Previous cluster not cleaned
make distclean
make create-demo-cluster

# 3. Shared memory issues
sudo sysctl -w kernel.shmmax=17179869184
sudo sysctl -w kernel.shmall=4194304
```

### Insufficient Disk Space

**Symptom**: Errors during data generation

**Solution**:
```bash
# Check space
df -h

# Option 1: Free up space
# Option 2: Reduce dataset size in sql/03_generate_data.sql
# Change: FROM generate_series(1, 50000000) gs  -- 50M instead of 200M

# Option 3: Use different mount point
export PGDATA=/mnt/large-disk/gpdemo
```

### Python Charts Fail

**Symptom**: `ModuleNotFoundError: No module named 'matplotlib'`

**Solution**:
```bash
# Install dependencies
pip3 install matplotlib seaborn

# Or use system package manager
sudo yum install python3-matplotlib python3-seaborn  # RHEL/CentOS
sudo apt install python3-matplotlib python3-seaborn  # Ubuntu

# Verify
python3 -c "import matplotlib; print(matplotlib.__version__)"
```

---

## Configuration Tuning (Optional)

### For Larger Datasets

Edit `postgresql.conf` (or via ALTER SYSTEM):

```sql
-- Memory
ALTER SYSTEM SET shared_buffers = '8GB';
ALTER SYSTEM SET work_mem = '256MB';
ALTER SYSTEM SET maintenance_work_mem = '2GB';

-- Checkpoints
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET max_wal_size = '4GB';

-- Query execution
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;

-- Restart required
pg_ctl restart -D $PGDATA
```

### For Faster Benchmarks (Development)

```sql
-- Disable fsync (UNSAFE - development only!)
ALTER SYSTEM SET fsync = off;
ALTER SYSTEM SET synchronous_commit = off;
ALTER SYSTEM SET full_page_writes = off;

-- Restart required
pg_ctl restart -D $PGDATA
```

**Warning**: Never use fsync=off in production!

---

## Verification Checklist

Before running the full benchmark:

- [ ] Cloudberry compiled with `--enable-pax`
- [ ] Demo cluster running (psql connects)
- [ ] PAX access method available (`SELECT ... FROM pg_am`)
- [ ] 300GB+ disk space free
- [ ] Benchmark scripts executable
- [ ] Test PAX table created successfully
- [ ] Python dependencies installed (if using charts)

---

## Next Steps

Once installation is complete:

1. **Run Quick Test**: See "Quick Validation" section above
2. **Review Benchmark**: Read `README.md` and `QUICK_REFERENCE.md`
3. **Execute Benchmark**: Run `./scripts/run_full_benchmark.sh`
4. **Analyze Results**: See `docs/REPORTING.md`

---

## Additional Resources

- **Cloudberry Documentation**: https://cloudberry.apache.org/docs
- **PAX Source Code**: `cloudberry/contrib/pax_storage/`
- **PAX Documentation**: `cloudberry/contrib/pax_storage/doc/`
- **Build Issues**: https://github.com/apache/cloudberry/issues

---

**Installation complete? Time to benchmark PAX performance!**
