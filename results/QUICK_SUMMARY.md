# Quick Summary: 4-Variant Benchmark Results

**Date**: October 29, 2025 | **Dataset**: 10M rows | **Cluster**: 3 segments | **Duration**: ~2.5 minutes

## TL;DR

✅ **Use AOCO** - Best storage + performance + production-ready
❌ **Avoid PAX clustered** - 2.66x storage bloat, 110x memory overhead
⚠️ **PAX no-cluster** - Shows promise but still 3-4x slower than AOCO

## The Smoking Gun

**Clustering is broken:**
```
PAX (no-cluster):   752 MB → 752 MB (no change) ✅
PAX (clustered):    752 MB → 2,000 MB (+166% bloat!) ❌
```

## Results at a Glance

| Variant | Storage | Query Speed | Memory | Production Ready |
|---------|---------|-------------|--------|------------------|
| **AOCO** | 710 MB ✅ | 187-387 ms ✅ | 538 KB ✅ | **YES** ✅ |
| **PAX (no-cluster)** | 752 MB ✅ | 736-847 ms 🟠 | 149 KB ✅ | Experimental ⚠️ |
| **PAX (clustered)** | 2,000 MB ❌ | 492-711 ms 🟠 | 16,390 KB ❌ | **NO** ❌ |
| **AO** | 1,128 MB 🟠 | 1,355-1,482 ms ❌ | 345 KB ✅ | For OLTP only |

## Key Findings

### Storage
- **AOCO**: 8.65x compression (best)
- **PAX no-cluster**: 8.17x compression (competitive!)
- **PAX clustered**: 3.07x compression (worst - destroyed by clustering)

### Performance
- **AOCO**: Fastest (187-387 ms baseline)
- **PAX variants**: 3-4x slower (file-level pruning not working)
- **Z-order clustering**: Does help multi-dimensional queries but costs too much

### Memory
- **PAX no-cluster**: 149 KB (most efficient!)
- **AOCO**: 538 KB (reasonable)
- **PAX clustered**: 16,390 KB (30x worse than AOCO!)

## What This Means

**For Production:**
- Deploy AOCO for all analytical workloads
- Avoid PAX until clustering is fixed

**For PAX Development:**
1. Fix clustering storage bloat (CRITICAL)
2. Fix clustering memory overhead (CRITICAL)
3. Enable proper file-level pruning (HIGH)
4. Add per-column encoding support (MEDIUM)

**For Future Testing:**
- Test at 50M-100M rows when PAX is fixed
- Retest with stable Cloudberry release (not -devel)

## Full Details

See: `results/4-variant-test-10M-rows.md` (comprehensive 15-page report)
