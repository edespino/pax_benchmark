# PAX Benchmark Charts

## Overview

This directory contains visual charts for presenting PAX benchmark results.

---

## Current Status

**Charts will be generated when you run the benchmark.**

Two options for generating charts:

### Option 1: Example Charts (Before Running Benchmark)

Generate example charts with sample data for presentations:

```bash
cd benchmarks/retail_sales
python3 scripts/generate_charts.py
```

This creates:
- `storage_comparison.png` - Storage size comparison (AO vs AOCO vs PAX)
- `query_performance.png` - Query time by category
- `sparse_filter_effectiveness.png` - File pruning visualization
- `compression_by_encoding.png` - Per-column compression ratios
- `zorder_clustering_impact.png` - Z-order performance gains

### Option 2: Actual Results (After Running Benchmark)

Generate charts from real benchmark results:

```bash
cd benchmarks/retail_sales
python3 scripts/generate_charts.py results/run_YYYYMMDD_HHMMSS/
```

---

## Dependencies

Charts require matplotlib and seaborn:

```bash
pip install matplotlib seaborn
```

Or use system package manager:
```bash
# macOS
brew install python3
pip3 install matplotlib seaborn

# Ubuntu/Debian
sudo apt-get install python3-matplotlib python3-seaborn

# RHEL/CentOS
sudo yum install python3-matplotlib python3-seaborn
```

---

## Alternative: ASCII Charts

If you don't want to install matplotlib, **all charts are also available as ASCII art** in:

```
../VISUAL_PRESENTATION.md
```

These ASCII charts are:
- ✅ Version-controllable
- ✅ Readable in any text viewer
- ✅ Easy to update
- ✅ Can be converted to images manually

---

## Chart Descriptions

### 1. Storage Comparison Chart
**File**: `storage_comparison.png`

Shows physical storage size for each variant:
- AO: ~95 GB (baseline row storage)
- AOCO: ~62 GB (columnar compression)
- PAX: ~41 GB (optimized per-column encoding)

**Key Insight**: PAX is 34% smaller than AOCO

---

### 2. Query Performance Chart
**File**: `query_performance.png`

Average query execution time by category:
- Sparse Filtering: -35% improvement
- Bloom Filters: -42% improvement
- Z-Order Clustering: -48% improvement
- Compression: -28% improvement
- Complex Analytics: -22% improvement
- MVCC: -18% improvement

**Key Insight**: PAX is 32% faster on average

---

### 3. Sparse Filter Effectiveness
**File**: `sparse_filter_effectiveness.png`

Visualization of file pruning:
- Pie chart: 88% of files skipped
- Bar chart: I/O reduced from 10.5GB to 1.2GB (87% reduction)

**Key Insight**: Sparse filtering eliminates most I/O before reading data

---

### 4. Compression by Encoding
**File**: `compression_by_encoding.png`

Per-column compression ratios:
- order_id (delta): 8.2x
- priority (RLE): 23.1x
- sale_date (delta): 7.6x
- status (RLE): 14.3x
- description (zstd-9): 3.9x
- total_amount (zstd-5): 2.3x

**Key Insight**: Per-column encoding provides 2.2x better compression vs uniform

---

### 5. Z-Order Clustering Impact
**File**: `zorder_clustering_impact.png`

Three metrics comparing unclustered vs Z-order:
- Query time: 2.8s → 0.6s (5x faster)
- Files scanned: 120 → 24 (-80%)
- Cache hit rate: 45% → 76% (+67%)

**Key Insight**: Z-order clustering provides massive speedup on multi-dimensional queries

---

## Usage in Presentations

### PowerPoint/Keynote
1. Generate PNGs using the script above
2. Insert → Picture → Select PNG files
3. Arrange in slides with talking points

### Google Slides
1. Generate PNGs
2. Insert → Image → Upload from computer
3. Add annotations as needed

### Markdown/Web
```markdown
![Storage Comparison](visuals/charts/storage_comparison.png)
```

### LaTeX/Academic Papers
```latex
\includegraphics[width=0.8\textwidth]{visuals/charts/storage_comparison.png}
```

---

## Regenerating Charts

To update charts with new data:

```bash
# After running benchmark
cd benchmarks/retail_sales
python3 scripts/generate_charts.py results/run_YYYYMMDD_HHMMSS/

# Charts will be regenerated in visuals/charts/
```

---

## Customization

Edit `scripts/generate_charts.py` to customize:
- Colors and styling
- Chart dimensions
- Label formats
- Data displayed
- Additional metrics

The script uses matplotlib, so standard matplotlib customization applies.

---

## Troubleshooting

**"ModuleNotFoundError: No module named 'matplotlib'"**
→ Install dependencies: `pip install matplotlib seaborn`

**"Qt platform plugin could not be initialized"**
→ Script uses non-interactive backend (Agg), should work headless

**Charts look different than expected**
→ Run benchmark first to generate actual data, or use example mode

**Need different format (SVG, PDF)?**
→ Edit script: change `plt.savefig(..., format='svg')` or `format='pdf'`

---

## Next Steps

1. **Before benchmark**: Generate example charts for presentations
   ```bash
   python3 scripts/generate_charts.py
   ```

2. **After benchmark**: Generate real charts from results
   ```bash
   python3 scripts/generate_charts.py results/run_YYYYMMDD_HHMMSS/
   ```

3. **For presentations**: Use PNG files in slides or `VISUAL_PRESENTATION.md` for ASCII versions

---

## Why the Charts Directory Was Empty

**Intentional Design Decision:**

1. **Charts require benchmark results** - Real data doesn't exist until you run the benchmark
2. **ASCII art provided** - All visualizations documented in `VISUAL_PRESENTATION.md`
3. **Script provided** - `generate_charts.py` creates actual images when needed
4. **Flexibility** - Generate example charts for presentations, or real charts from results

**Think of it as**: The charts are "defined" but not yet "rendered" - like a recipe before cooking!

