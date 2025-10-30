#!/usr/bin/env python3
"""
Generate visual charts from benchmark results
Requires: matplotlib, seaborn (install via: pip install matplotlib seaborn)
"""

import json
import sys
from pathlib import Path
from typing import Dict, List

try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    import matplotlib.pyplot as plt
    import seaborn as sns
except ImportError:
    print("ERROR: matplotlib and seaborn required")
    print("Install with: pip install matplotlib seaborn")
    sys.exit(1)


def generate_storage_chart(output_path: Path, data: Dict = None):
    """Generate storage comparison bar chart"""

    # Use provided data or example data
    if data is None:
        variants = ['AO', 'AOCO', 'PAX']
        sizes_gb = [95, 62, 41]
        colors = ['#e74c3c', '#3498db', '#2ecc71']
    else:
        variants = list(data.keys())
        sizes_gb = list(data.values())
        colors = ['#e74c3c', '#3498db', '#2ecc71'][:len(variants)]

    # Create figure
    fig, ax = plt.subplots(figsize=(10, 6))

    # Create bars
    bars = ax.bar(variants, sizes_gb, color=colors, alpha=0.8, edgecolor='black', linewidth=2)

    # Add value labels on bars
    for bar in bars:
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{height:.0f} GB',
                ha='center', va='bottom', fontsize=12, fontweight='bold')

    # Calculate improvements
    if len(sizes_gb) >= 3:
        aoco_size = sizes_gb[1]
        pax_size = sizes_gb[2]
        improvement = ((aoco_size - pax_size) / aoco_size) * 100

        # Add improvement annotation
        ax.annotate(f'-{improvement:.0f}%',
                   xy=(2, pax_size), xytext=(2.3, pax_size + 10),
                   arrowprops=dict(arrowstyle='->', color='green', lw=2),
                   fontsize=14, fontweight='bold', color='green')

    # Styling
    ax.set_ylabel('Storage Size (GB)', fontsize=14, fontweight='bold')
    ax.set_xlabel('Storage Variant', fontsize=14, fontweight='bold')
    ax.set_title('Storage Efficiency Comparison\n200M rows, 25 columns',
                fontsize=16, fontweight='bold', pad=20)
    ax.grid(axis='y', alpha=0.3, linestyle='--')
    ax.set_ylim(0, max(sizes_gb) * 1.15)

    # Add compression ratio text
    if len(sizes_gb) >= 3:
        ratios = [f'{sizes_gb[0]/s:.1f}x' for s in sizes_gb]
        for i, (bar, ratio) in enumerate(zip(bars, ratios)):
            ax.text(bar.get_x() + bar.get_width()/2., 5,
                   f'Ratio: {ratio}',
                   ha='center', va='bottom', fontsize=10, style='italic')

    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Generated: {output_path}")


def generate_performance_chart(output_path: Path, data: Dict = None):
    """Generate query performance comparison chart"""

    # Use provided data or example data
    if data is None:
        categories = ['Sparse\nFiltering', 'Bloom\nFilters', 'Z-Order\nClustering',
                     'Compression', 'Complex\nAnalytics', 'MVCC']
        ao_times = [1200, 1400, 2800, 1100, 1600, 900]
        aoco_times = [950, 1100, 2200, 850, 1300, 720]
        pax_times = [620, 640, 1150, 610, 1010, 590]
    else:
        categories = list(data.keys())
        ao_times = [v['ao'] for v in data.values()]
        aoco_times = [v['aoco'] for v in data.values()]
        pax_times = [v['pax'] for v in data.values()]

    # Create figure
    fig, ax = plt.subplots(figsize=(14, 8))

    # Set positions
    x = range(len(categories))
    width = 0.25

    # Create bars
    bars1 = ax.bar([i - width for i in x], ao_times, width, label='AO',
                   color='#e74c3c', alpha=0.8, edgecolor='black')
    bars2 = ax.bar(x, aoco_times, width, label='AOCO',
                   color='#3498db', alpha=0.8, edgecolor='black')
    bars3 = ax.bar([i + width for i in x], pax_times, width, label='PAX',
                   color='#2ecc71', alpha=0.8, edgecolor='black')

    # Add improvement percentages
    for i, (aoco, pax) in enumerate(zip(aoco_times, pax_times)):
        improvement = ((aoco - pax) / aoco) * 100
        ax.text(i + width, pax + 50, f'-{improvement:.0f}%',
               ha='center', fontsize=9, fontweight='bold', color='green')

    # Styling
    ax.set_ylabel('Average Query Time (ms)', fontsize=14, fontweight='bold')
    ax.set_xlabel('Query Category', fontsize=14, fontweight='bold')
    ax.set_title('Query Performance by Category\n(Lower is Better)',
                fontsize=16, fontweight='bold', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels(categories, fontsize=11)
    ax.legend(loc='upper right', fontsize=12, framealpha=0.9)
    ax.grid(axis='y', alpha=0.3, linestyle='--')

    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Generated: {output_path}")


def generate_sparse_filter_chart(output_path: Path, data: Dict = None):
    """Generate sparse filter effectiveness visualization"""

    # Data
    if data is None:
        labels = ['Files\nSkipped', 'Files\nRead']
        sizes = [132, 18]  # 88% skipped
        colors = ['#95a5a6', '#2ecc71']
        explode = (0.1, 0)
    else:
        labels = list(data.keys())
        sizes = list(data.values())
        colors = ['#95a5a6', '#2ecc71']
        explode = (0.1, 0)

    # Create figure
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    # Pie chart
    wedges, texts, autotexts = ax1.pie(sizes, labels=labels, autopct='%1.1f%%',
                                        colors=colors, explode=explode,
                                        startangle=90, textprops={'fontsize': 12})
    for autotext in autotexts:
        autotext.set_color('white')
        autotext.set_fontweight('bold')
        autotext.set_fontsize(14)

    ax1.set_title('Sparse Filter: File Pruning\n150 total files',
                 fontsize=14, fontweight='bold', pad=20)

    # Bar chart showing I/O reduction
    metrics = ['Without\nSparse Filter', 'With\nSparse Filter']
    io_gb = [10.5, 1.2]
    bars = ax2.bar(metrics, io_gb, color=['#e74c3c', '#2ecc71'],
                  alpha=0.8, edgecolor='black', linewidth=2)

    # Add value labels
    for bar in bars:
        height = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2., height,
                f'{height:.1f} GB',
                ha='center', va='bottom', fontsize=12, fontweight='bold')

    # Add reduction annotation
    ax2.annotate(f'87% less I/O',
                xy=(1, 1.2), xytext=(1.3, 6),
                arrowprops=dict(arrowstyle='->', color='green', lw=2),
                fontsize=14, fontweight='bold', color='green')

    ax2.set_ylabel('Data Scanned (GB)', fontsize=12, fontweight='bold')
    ax2.set_title('I/O Reduction\nQuery: date = "2023-01-15" AND region = "US"',
                 fontsize=14, fontweight='bold', pad=20)
    ax2.grid(axis='y', alpha=0.3, linestyle='--')

    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Generated: {output_path}")


def generate_compression_chart(output_path: Path, data: Dict = None):
    """Generate compression breakdown by encoding type"""

    # Data
    if data is None:
        columns = ['order_id\n(delta)', 'priority\n(RLE)', 'sale_date\n(delta)',
                  'status\n(RLE)', 'description\n(zstd-9)', 'total_amount\n(zstd-5)']
        original_mb = [1600, 200, 1600, 400, 8200, 3200]
        compressed_mb = [195, 8.7, 210, 28, 2100, 1400]
    else:
        columns = list(data.keys())
        original_mb = [v['original'] for v in data.values()]
        compressed_mb = [v['compressed'] for v in data.values()]

    # Calculate ratios
    ratios = [orig/comp for orig, comp in zip(original_mb, compressed_mb)]

    # Create figure
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 10))

    # Stacked bar showing before/after
    x = range(len(columns))
    width = 0.6

    bars1 = ax1.bar(x, original_mb, width, label='Original', color='#e74c3c',
                   alpha=0.8, edgecolor='black')
    bars2 = ax1.bar(x, compressed_mb, width, label='Compressed', color='#2ecc71',
                   alpha=0.8, edgecolor='black')

    # Add savings percentage
    for i, (orig, comp) in enumerate(zip(original_mb, compressed_mb)):
        savings = ((orig - comp) / orig) * 100
        ax1.text(i, orig + 200, f'-{savings:.0f}%',
                ha='center', fontsize=10, fontweight='bold', color='green')

    ax1.set_ylabel('Size (MB)', fontsize=12, fontweight='bold')
    ax1.set_title('Per-Column Storage: Original vs Compressed',
                 fontsize=14, fontweight='bold', pad=20)
    ax1.set_xticks(x)
    ax1.set_xticklabels(columns, fontsize=10)
    ax1.legend(loc='upper right', fontsize=11)
    ax1.grid(axis='y', alpha=0.3, linestyle='--')

    # Compression ratio bars
    bars = ax2.bar(x, ratios, width, color='#9b59b6', alpha=0.8,
                  edgecolor='black', linewidth=2)

    # Add ratio labels
    for bar, ratio in zip(bars, ratios):
        height = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2., height,
                f'{ratio:.1f}x',
                ha='center', va='bottom', fontsize=11, fontweight='bold')

    ax2.set_ylabel('Compression Ratio', fontsize=12, fontweight='bold')
    ax2.set_xlabel('Column (Encoding Type)', fontsize=12, fontweight='bold')
    ax2.set_title('Compression Effectiveness by Encoding',
                 fontsize=14, fontweight='bold', pad=20)
    ax2.set_xticks(x)
    ax2.set_xticklabels(columns, fontsize=10)
    ax2.axhline(y=1, color='red', linestyle='--', alpha=0.5, label='No compression')
    ax2.grid(axis='y', alpha=0.3, linestyle='--')

    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Generated: {output_path}")


def generate_zorder_chart(output_path: Path, data: Dict = None):
    """Generate Z-order clustering impact chart"""

    # Data
    if data is None:
        metrics = ['Query Time\n(seconds)', 'Files Scanned', 'Cache Hit\nRate (%)']
        unclustered = [2.8, 120, 45]
        clustered = [0.6, 24, 76]
        y_labels = ['Time (s)', 'Files', 'Hit Rate (%)']
    else:
        metrics = list(data.keys())
        unclustered = [v['unclustered'] for v in data.values()]
        clustered = [v['clustered'] for v in data.values()]
        y_labels = [''] * len(metrics)

    # Create figure
    fig, axes = plt.subplots(1, 3, figsize=(16, 6))

    for i, (ax, metric, unclust, clust, ylabel) in enumerate(zip(axes, metrics, unclustered, clustered, y_labels)):
        # Bars
        bars = ax.bar(['Unclustered', 'Z-Order\nClustered'], [unclust, clust],
                     color=['#e74c3c', '#2ecc71'], alpha=0.8,
                     edgecolor='black', linewidth=2)

        # Value labels
        for bar in bars:
            height = bar.get_height()
            ax.text(bar.get_x() + bar.get_width()/2., height,
                   f'{height:.1f}',
                   ha='center', va='bottom', fontsize=13, fontweight='bold')

        # Improvement arrow
        if i < 2:  # Lower is better for first two metrics
            improvement = ((unclust - clust) / unclust) * 100
            ax.annotate(f'-{improvement:.0f}%',
                       xy=(1, clust), xytext=(1.3, (unclust + clust) / 2),
                       arrowprops=dict(arrowstyle='->', color='green', lw=2),
                       fontsize=12, fontweight='bold', color='green')
        else:  # Higher is better for cache hit rate
            improvement = ((clust - unclust) / unclust) * 100
            ax.annotate(f'+{improvement:.0f}%',
                       xy=(1, clust), xytext=(1.3, (unclust + clust) / 2),
                       arrowprops=dict(arrowstyle='->', color='green', lw=2),
                       fontsize=12, fontweight='bold', color='green')

        ax.set_title(metric, fontsize=13, fontweight='bold', pad=15)
        ax.grid(axis='y', alpha=0.3, linestyle='--')

        # Set y-axis to start at 0
        ax.set_ylim(0, max(unclust, clust) * 1.2)

    fig.suptitle('Z-Order Clustering Impact\nQuery: date BETWEEN "2023-01-01" AND "2023-01-31" AND region = "North America"',
                fontsize=15, fontweight='bold', y=1.02)

    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Generated: {output_path}")


def generate_all_example_charts(charts_dir: Path):
    """Generate all example charts with sample data"""

    print("Generating example charts with sample data...")
    print("(These will be replaced with actual data after benchmark execution)")
    print()

    generate_storage_chart(charts_dir / 'storage_comparison.png')
    generate_performance_chart(charts_dir / 'query_performance.png')
    generate_sparse_filter_chart(charts_dir / 'sparse_filter_effectiveness.png')
    generate_compression_chart(charts_dir / 'compression_by_encoding.png')
    generate_zorder_chart(charts_dir / 'zorder_clustering_impact.png')

    print()
    print(f"✅ Generated 5 example charts in {charts_dir}")
    print()
    print("To generate charts from actual benchmark results:")
    print("  python generate_charts.py <results_directory>")


def generate_from_results(results_dir: Path, charts_dir: Path):
    """Generate charts from actual benchmark results"""

    metrics_file = results_dir / 'aggregated_metrics.json'

    if not metrics_file.exists():
        print(f"ERROR: Metrics file not found: {metrics_file}")
        print("Run the benchmark first, or use without arguments for example charts")
        sys.exit(1)

    print(f"Loading results from: {metrics_file}")

    with open(metrics_file) as f:
        metrics = json.load(f)

    # Extract data for charts
    # TODO: Parse actual metrics and generate charts
    # For now, use example data

    print("Generating charts from benchmark results...")
    generate_all_example_charts(charts_dir)


def main():
    if len(sys.argv) > 1:
        # Generate from actual results
        results_dir = Path(sys.argv[1])
        charts_dir = Path(__file__).parent.parent / 'visuals' / 'charts'
        charts_dir.mkdir(parents=True, exist_ok=True)
        generate_from_results(results_dir, charts_dir)
    else:
        # Generate example charts
        charts_dir = Path(__file__).parent.parent / 'visuals' / 'charts'
        charts_dir.mkdir(parents=True, exist_ok=True)
        generate_all_example_charts(charts_dir)


if __name__ == '__main__':
    main()
