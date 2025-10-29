#!/usr/bin/env python3
"""
Parse EXPLAIN ANALYZE output from benchmark query logs
Extracts key metrics: execution time, planning time, rows, buffers, etc.
"""

import re
import sys
import json
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict


@dataclass
class QueryMetrics:
    """Metrics extracted from a single query execution"""
    query_num: int
    variant: str
    run_num: int
    execution_time_ms: Optional[float] = None
    planning_time_ms: Optional[float] = None
    total_time_ms: Optional[float] = None
    rows_returned: Optional[int] = None
    buffers_hit: Optional[int] = None
    buffers_read: Optional[int] = None
    blocks_scanned: Optional[int] = None
    sparse_filter_info: Optional[str] = None


def parse_explain_output(log_content: str, variant: str, run_num: int) -> List[QueryMetrics]:
    """Parse EXPLAIN ANALYZE output from log file"""
    metrics_list = []

    # Split into individual query sections
    query_sections = re.split(r'Q\d+:', log_content)

    for idx, section in enumerate(query_sections[1:], start=1):  # Skip first empty section
        metrics = QueryMetrics(query_num=idx, variant=variant, run_num=run_num)

        # Extract execution time
        exec_match = re.search(r'Execution Time:\s*([\d.]+)\s*ms', section)
        if exec_match:
            metrics.execution_time_ms = float(exec_match.group(1))

        # Extract planning time
        plan_match = re.search(r'Planning Time:\s*([\d.]+)\s*ms', section)
        if plan_match:
            metrics.planning_time_ms = float(plan_match.group(1))
            if metrics.execution_time_ms:
                metrics.total_time_ms = metrics.planning_time_ms + metrics.execution_time_ms

        # Extract rows
        rows_match = re.search(r'rows=(\d+)', section)
        if rows_match:
            metrics.rows_returned = int(rows_match.group(1))

        # Extract buffer stats
        buffers_match = re.search(r'Buffers: shared hit=(\d+).*?read=(\d+)', section)
        if buffers_match:
            metrics.buffers_hit = int(buffers_match.group(1))
            metrics.buffers_read = int(buffers_match.group(2))

        # Extract sparse filter info (PAX-specific)
        sparse_match = re.search(r'Sparse filter: skipped (\d+) files out of (\d+)', section, re.IGNORECASE)
        if sparse_match:
            skipped = int(sparse_match.group(1))
            total = int(sparse_match.group(2))
            pct = 100.0 * skipped / total if total > 0 else 0
            metrics.sparse_filter_info = f"{skipped}/{total} ({pct:.1f}%)"

        metrics_list.append(metrics)

    return metrics_list


def aggregate_runs(all_metrics: List[QueryMetrics]) -> Dict:
    """Aggregate metrics across multiple runs (take median)"""
    from statistics import median

    # Group by query_num and variant
    grouped = {}
    for m in all_metrics:
        key = (m.query_num, m.variant)
        if key not in grouped:
            grouped[key] = []
        grouped[key].append(m)

    # Calculate median for each group
    aggregated = {}
    for (query_num, variant), metrics_group in grouped.items():
        exec_times = [m.execution_time_ms for m in metrics_group if m.execution_time_ms]
        total_times = [m.total_time_ms for m in metrics_group if m.total_time_ms]

        agg_key = f"Q{query_num}_{variant}"
        aggregated[agg_key] = {
            'query_num': query_num,
            'variant': variant,
            'num_runs': len(metrics_group),
            'median_execution_ms': median(exec_times) if exec_times else None,
            'median_total_ms': median(total_times) if total_times else None,
            'min_execution_ms': min(exec_times) if exec_times else None,
            'max_execution_ms': max(exec_times) if exec_times else None,
            'sparse_filter': metrics_group[0].sparse_filter_info if metrics_group else None
        }

    return aggregated


def generate_comparison_table(aggregated: Dict) -> str:
    """Generate markdown comparison table"""
    # Get unique query numbers
    query_nums = sorted(set(m['query_num'] for m in aggregated.values()))

    # Build table
    lines = []
    lines.append("| Query | AO (ms) | AOCO (ms) | PAX (ms) | PAX vs AOCO | Sparse Filter |")
    lines.append("|-------|---------|-----------|----------|-------------|---------------|")

    for qnum in query_nums:
        ao_key = f"Q{qnum}_sales_fact_ao"
        aoco_key = f"Q{qnum}_sales_fact_aoco"
        pax_key = f"Q{qnum}_sales_fact_pax"

        ao_time = aggregated.get(ao_key, {}).get('median_execution_ms')
        aoco_time = aggregated.get(aoco_key, {}).get('median_execution_ms')
        pax_time = aggregated.get(pax_key, {}).get('median_execution_ms')
        sparse = aggregated.get(pax_key, {}).get('sparse_filter', '-')

        improvement = ""
        if aoco_time and pax_time:
            pct = 100.0 * (aoco_time - pax_time) / aoco_time
            improvement = f"{pct:+.1f}%"

        lines.append(f"| Q{qnum} | {ao_time:.1f} | {aoco_time:.1f} | {pax_time:.1f} | {improvement} | {sparse} |")

    # Add average row
    ao_times = [m['median_execution_ms'] for k, m in aggregated.items() if 'ao' in k and m['median_execution_ms']]
    aoco_times = [m['median_execution_ms'] for k, m in aggregated.items() if 'aoco' in k and m['median_execution_ms']]
    pax_times = [m['median_execution_ms'] for k, m in aggregated.items() if 'pax' in k and m['median_execution_ms']]

    if ao_times and aoco_times and pax_times:
        avg_ao = sum(ao_times) / len(ao_times)
        avg_aoco = sum(aoco_times) / len(aoco_times)
        avg_pax = sum(pax_times) / len(pax_times)
        avg_improvement = 100.0 * (avg_aoco - avg_pax) / avg_aoco

        lines.append(f"| **AVG** | **{avg_ao:.1f}** | **{avg_aoco:.1f}** | **{avg_pax:.1f}** | **{avg_improvement:+.1f}%** | - |")

    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: parse_explain_results.py <results_directory>")
        sys.exit(1)

    results_dir = Path(sys.argv[1])
    queries_dir = results_dir / "queries"

    if not queries_dir.exists():
        print(f"Error: Queries directory not found: {queries_dir}")
        sys.exit(1)

    print("Parsing query results...")

    # Parse all log files
    all_metrics = []
    for log_file in sorted(queries_dir.glob("sales_fact_*_run*.log")):
        # Extract variant and run number from filename
        match = re.match(r'sales_fact_(ao|aoco|pax)_run(\d+)\.log', log_file.name)
        if not match:
            continue

        variant = f"sales_fact_{match.group(1)}"
        run_num = int(match.group(2))

        print(f"  Processing: {log_file.name}")

        with open(log_file, 'r') as f:
            content = f.read()
            metrics = parse_explain_output(content, variant, run_num)
            all_metrics.extend(metrics)

    # Aggregate across runs
    print("\nAggregating results...")
    aggregated = aggregate_runs(all_metrics)

    # Save JSON
    json_file = results_dir / "aggregated_metrics.json"
    with open(json_file, 'w') as f:
        json.dump(aggregated, f, indent=2)
    print(f"  Saved: {json_file}")

    # Generate comparison table
    table = generate_comparison_table(aggregated)
    table_file = results_dir / "comparison_table.md"
    with open(table_file, 'w') as f:
        f.write("# Query Performance Comparison\n\n")
        f.write(table)
        f.write("\n")
    print(f"  Saved: {table_file}")

    print("\nDone! Results:")
    print(f"  - JSON metrics: {json_file}")
    print(f"  - Comparison table: {table_file}")


if __name__ == '__main__':
    main()
