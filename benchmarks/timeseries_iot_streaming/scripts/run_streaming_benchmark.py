#!/usr/bin/env python3
"""
Streaming INSERT Benchmark - PAX vs AO/AOCO

Tests INSERT throughput for continuous batch loading scenarios.
Simulates realistic telecom/IoT traffic patterns with real-time progress monitoring.

Phases:
  Phase 1 (No indexes): Pure INSERT speed (~15-20 minutes)
  Phase 2 (With indexes): Realistic production scenario (~25-35 minutes)

Usage:
  ./run_streaming_benchmark.py                    # Run both phases
  ./run_streaming_benchmark.py --phase 1          # Phase 1 only
  ./run_streaming_benchmark.py --no-interactive   # Skip prompts
"""

import argparse
import logging
import re
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, Tuple

from rich.console import Console
from rich.logging import RichHandler
from rich.panel import Panel
from rich.progress import (
    BarColumn,
    Progress,
    SpinnerColumn,
    TextColumn,
    TimeElapsedColumn,
    TimeRemainingColumn,
)
from rich.table import Table

# Initialize rich console
console = Console()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    handlers=[RichHandler(console=console, show_time=True, show_path=False)],
)
log = logging.getLogger(__name__)


class PhaseTimer:
    """Track timing for benchmark phases"""

    def __init__(self):
        self.phase_times: Dict[str, float] = {}
        self.benchmark_start = time.time()

    def record(self, phase_id: str, duration: float):
        """Record phase duration"""
        self.phase_times[phase_id] = duration

    def total_elapsed(self) -> float:
        """Get total benchmark elapsed time"""
        return time.time() - self.benchmark_start

    def format_duration(self, seconds: float) -> str:
        """Format duration as MM:SS"""
        mins = int(seconds // 60)
        secs = int(seconds % 60)
        return f"{mins}m {secs}s"


class StreamingBenchmark:
    """Main benchmark orchestrator"""

    def __init__(
        self,
        psql_cmd: str,
        results_dir: Path,
        phase: str,
        no_interactive: bool,
        verbose: bool,
    ):
        self.psql_cmd = psql_cmd
        self.results_dir = results_dir
        self.phase = phase
        self.no_interactive = no_interactive
        self.verbose = verbose
        self.timer = PhaseTimer()
        self.sql_dir = Path(__file__).parent.parent / "sql"

        # Create results directory
        self.results_dir.mkdir(parents=True, exist_ok=True)
        self.log_file = self.results_dir / "benchmark.log"
        self.timing_file = self.results_dir / "timing.txt"

        # Setup file logging
        file_handler = logging.FileHandler(self.log_file)
        file_handler.setFormatter(logging.Formatter("%(asctime)s - %(message)s"))
        logging.getLogger().addHandler(file_handler)

    def run_sql_phase(
        self,
        phase_num: str,
        phase_name: str,
        sql_file: Path,
        log_file: Path,
        show_progress: bool = False,
        progress_callback=None,
    ) -> bool:
        """
        Execute a SQL phase using psql subprocess

        Args:
            phase_num: Phase identifier (e.g., "1", "6a", "11b")
            phase_name: Human-readable phase description
            sql_file: Path to SQL file
            log_file: Path to output log file
            show_progress: Enable real-time progress monitoring
            progress_callback: Function to call with progress updates

        Returns:
            True if successful, False otherwise
        """
        log.info(f"Phase {phase_num}: {phase_name}...")

        if not sql_file.exists():
            log.error(f"SQL file not found: {sql_file}")
            return False

        start = time.time()

        # Prepare psql command
        cmd = f"{self.psql_cmd} -f {sql_file}"

        # Execute with progress monitoring if requested
        if show_progress and progress_callback:
            # Start log monitoring thread
            monitor_thread = threading.Thread(
                target=self._monitor_log_file,
                args=(log_file, progress_callback),
                daemon=True,
            )
            monitor_thread.start()

        # Run psql command
        with open(log_file, "w") as f:
            result = subprocess.run(
                cmd, shell=True, stdout=f, stderr=subprocess.STDOUT, text=True
            )

        duration = time.time() - start
        self.timer.record(f"phase_{phase_num}", duration)

        # Wait for monitor thread to finish
        if show_progress and progress_callback:
            time.sleep(0.5)  # Allow final log entries to be processed

        # Check result
        if result.returncode == 0:
            console.print(
                f"[green]✅ {phase_name} completed in {self.timer.format_duration(duration)}[/green]"
            )
            with open(self.timing_file, "a") as f:
                f.write(f"Phase {phase_num} ({phase_name}): {duration:.1f}s\n")
            return True
        else:
            log.error(
                f"❌ {phase_name} failed (exit code {result.returncode}). See: {log_file}"
            )
            return False

    def _monitor_log_file(self, log_file: Path, callback):
        """
        Monitor a log file in real-time and call callback with progress updates

        Parses RAISE NOTICE lines like:
          NOTICE:  [Batch 10/500] Hour: 2, Size: 10000 rows, Total rows so far: 0.1M
        """
        # Wait for log file to be created
        max_wait = 10
        waited = 0
        while not log_file.exists() and waited < max_wait:
            time.sleep(0.1)
            waited += 0.1

        if not log_file.exists():
            return

        with open(log_file, "r") as f:
            # Jump to end
            f.seek(0, 2)

            while True:
                line = f.readline()
                if not line:
                    time.sleep(0.1)
                    continue

                # Parse batch progress
                # Phase 1: NOTICE:  [Batch 10/500] Hour: 2, Size: 10000 rows, Total rows so far: 0.1M
                # Phase 2: NOTICE:  [Batch 10/500] Hour: 2, Size: 10000 rows, Total: 0.1M
                match = re.search(
                    r"\[Batch (\d+)/500\].*Hour: (\d+).*Size: (\d+) rows.*Total(?:\s+rows\s+so\s+far)?: ([\d.]+)M",
                    line,
                )
                if match:
                    batch_num = int(match.group(1))
                    hour = int(match.group(2))
                    batch_size = int(match.group(3))
                    total_rows = float(match.group(4))
                    callback(
                        "batch_progress",
                        batch_num=batch_num,
                        hour=hour,
                        batch_size=batch_size,
                        total_rows=total_rows,
                    )

                # Check for completion markers
                if "Streaming complete!" in line or "simulation complete!" in line:
                    callback("complete")
                    break

                # Check for checkpoint markers
                if "CHECKPOINT" in line:
                    checkpoint_match = re.search(
                        r"CHECKPOINT: (\d+) batches complete, ([\d.]+)M rows", line
                    )
                    if checkpoint_match:
                        batches = int(checkpoint_match.group(1))
                        rows = float(checkpoint_match.group(2))
                        callback("checkpoint", batches=batches, rows=rows)

    def check_validation(self, log_file: Path, pattern: str) -> Tuple[bool, int]:
        """
        Check validation results in log file

        Args:
            log_file: Path to log file
            pattern: Pattern to search for (e.g., "❌ FAILED", "✅ PASS")

        Returns:
            Tuple of (has_failures, count)
        """
        if not log_file.exists():
            return False, 0

        count = 0
        with open(log_file, "r") as f:
            for line in f:
                if pattern in line:
                    count += 1

        return count > 0, count

    def ask_continue(self, message: str) -> bool:
        """Ask user for confirmation"""
        if self.no_interactive:
            return True

        console.print(f"\n[yellow]{message}[/yellow]")
        response = console.input("[yellow]Continue? [Y/n]: [/yellow]")
        return response.strip().lower() in ("", "y", "yes")

    def print_header(self):
        """Print benchmark header"""
        console.print()
        console.print(
            Panel(
                "[bold]Test Scenario:[/bold]\n"
                "  Dataset: 50M rows (500 batches)\n"
                "  Traffic: Realistic 24-hour telecom pattern\n"
                "  Batch sizes: 10K (small), 100K (medium), 500K (large bursts)\n"
                f"  Runtime: ~40-55 minutes (Phase 1 + Phase 2)\n\n"
                "[bold]Key Features:[/bold]\n"
                "  • Two-phase testing (with/without indexes)\n"
                "  • Validation-first design (prevents misconfiguration)\n"
                "  • Per-batch metrics (500 measurements per variant)\n"
                "  • Storage growth tracking",
                title="[bold cyan]Streaming INSERT Benchmark - PAX vs AO/AOCO[/bold cyan]",
                border_style="cyan",
            )
        )
        console.print()
        console.print(f"Results: [cyan]{self.results_dir}[/cyan]")
        console.print()

    def run_phase_0_to_4(self) -> bool:
        """Setup and validation phases"""
        console.print("[bold]Phase 0-4: Setup & Validation[/bold]\n")

        # Phase 0: Validation Framework
        if not self.run_sql_phase(
            "0",
            "Validation Framework Setup",
            self.sql_dir / "00_validation_framework.sql",
            self.results_dir / "00_validation_framework.log",
        ):
            return False

        # Phase 1: Schema Setup
        if not self.run_sql_phase(
            "1",
            "CDR Schema Setup (10K cell towers)",
            self.sql_dir / "01_setup_schema.sql",
            self.results_dir / "01_setup_schema.log",
        ):
            return False

        # Phase 2: Cardinality Analysis (CRITICAL)
        log.info("Phase 2: 🔍 CRITICAL - Cardinality Analysis (1M sample)...")
        if not self.run_sql_phase(
            "2",
            "Cardinality Analysis",
            self.sql_dir / "02_analyze_cardinality.sql",
            self.results_dir / "02_cardinality_analysis.txt",
        ):
            return False

        # Check for unsafe bloom filter candidates
        has_unsafe, unsafe_count = self.check_validation(
            self.results_dir / "02_cardinality_analysis.txt", "❌ UNSAFE"
        )
        if has_unsafe:
            log.warning(
                f"Found {unsafe_count} columns marked UNSAFE for bloom filters"
            )
            log.warning("These columns will be EXCLUDED from bloom filter configuration")
        else:
            console.print(
                "[green]✅ All proposed bloom filter columns passed validation[/green]"
            )

        console.print()

        # Phase 3: Generate Safe Configuration
        if not self.run_sql_phase(
            "3",
            "Auto-Generate Safe Configuration",
            self.sql_dir / "03_generate_config.sql",
            self.results_dir / "03_generated_config.sql",
        ):
            return False

        # Phase 4: Create Table Variants
        if not self.run_sql_phase(
            "4",
            "Create Storage Variants (AO/AOCO/PAX/PAX-no-cluster)",
            self.sql_dir / "04_create_variants.sql",
            self.results_dir / "04_create_variants.log",
        ):
            return False

        return True

    def run_phase_1(self) -> bool:
        """Phase 1: Streaming INSERTs without indexes"""
        console.print()
        console.print(
            Panel.fit(
                "[bold]PHASE 1: Streaming INSERTs WITHOUT Indexes[/bold]\n\n"
                "[white]This tests pure INSERT throughput without index maintenance[/white]\n"
                "[white]Expected runtime: 15-20 minutes[/white]",
                border_style="blue",
            )
        )
        console.print()

        # Phase 6a: Streaming INSERTs with progress monitoring
        log_file = self.results_dir / "06_streaming_phase1.log"

        # Create progress bar
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
            TimeElapsedColumn(),
            TimeRemainingColumn(),
            console=console,
        ) as progress:
            task = progress.add_task(
                "[cyan]Streaming INSERTs (Phase 1)", total=500, start=True
            )

            # Progress callback
            def update_progress(event_type, **kwargs):
                if event_type == "batch_progress":
                    batch_num = kwargs["batch_num"]
                    batch_size = kwargs["batch_size"]
                    total_rows = kwargs["total_rows"]
                    progress.update(
                        task,
                        completed=batch_num,
                        description=f"[cyan]Batch {batch_num}/500 ({batch_size:,} rows, {total_rows}M total)",
                    )
                elif event_type == "checkpoint":
                    batches = kwargs["batches"]
                    rows = kwargs["rows"]
                    progress.console.print(
                        f"[green]✓[/green] Checkpoint: {batches} batches, {rows}M rows"
                    )

            # Run phase with progress monitoring
            success = self.run_sql_phase(
                "6a",
                "Streaming INSERTs - Phase 1 (NO INDEXES)",
                self.sql_dir / "06_streaming_inserts_noindex.sql",
                log_file,
                show_progress=True,
                progress_callback=update_progress,
            )

            if not success:
                return False

            # Mark as complete
            progress.update(task, completed=500)

        # Phase 8: Optimize PAX (Z-order Clustering)
        log.info("Applying Z-order clustering to PAX tables...")
        if not self.run_sql_phase(
            "8",
            "PAX Z-order Clustering",
            self.sql_dir / "08_optimize_pax.sql",
            self.results_dir / "08_optimize_pax.log",
        ):
            return False

        # Check clustering overhead
        has_bloat, bloat_count = self.check_validation(
            self.results_dir / "08_optimize_pax.log", "❌ CRITICAL"
        )
        if has_bloat:
            log.error("CRITICAL STORAGE BLOAT DETECTED after clustering!")
            log.error(f"Review: {self.results_dir / '08_optimize_pax.log'}")
            return False
        else:
            console.print("[green]✅ Clustering overhead is acceptable[/green]")

        console.print()

        # Phase 9: Query Performance Tests
        if not self.run_sql_phase(
            "9",
            "Query Performance Tests (after Phase 1)",
            self.sql_dir / "09_run_queries.sql",
            self.results_dir / "09_queries_phase1.log",
        ):
            return False

        # Phase 10a: Collect Metrics
        if not self.run_sql_phase(
            "10a",
            "Collect Metrics - Phase 1",
            self.sql_dir / "10_collect_metrics.sql",
            self.results_dir / "10_metrics_phase1.txt",
        ):
            return False

        # Phase 11a: Validate Results
        if not self.run_sql_phase(
            "11a",
            "Validate Results - Phase 1",
            self.sql_dir / "11_validate_results.sql",
            self.results_dir / "11_validation_phase1.txt",
        ):
            return False

        # Check validation results
        has_failures, failure_count = self.check_validation(
            self.results_dir / "11_validation_phase1.txt", "❌ FAILED"
        )
        if has_failures:
            log.error(
                f"Validation failed! Review: {self.results_dir / '11_validation_phase1.txt'}"
            )
            return False
        else:
            console.print(
                "[green]✅ All validation gates passed for Phase 1[/green]"
            )

        console.print()
        console.print(
            Panel.fit(
                "[bold green]PHASE 1 COMPLETE![/bold green]",
                border_style="green",
            )
        )
        console.print()

        return True

    def run_phase_2(self) -> bool:
        """Phase 2: Streaming INSERTs with indexes"""
        # Ask user if they want to continue
        log.info("Phase 1 (no indexes) complete!")
        log.info(
            "Phase 2 will test INSERT performance WITH indexes (realistic production)"
        )
        log.info("Phase 2 runtime: ~25-35 minutes")

        if not self.ask_continue("Continue with Phase 2 (with indexes)?"):
            log.warning("Skipping Phase 2")
            log.warning("To run Phase 2 later, use: ./scripts/run_phase2_withindex.sh")
            return True

        console.print()
        console.print(
            Panel.fit(
                "[bold]PHASE 2: Streaming INSERTs WITH Indexes[/bold]\n\n"
                "[white]This tests INSERT throughput with index maintenance overhead[/white]\n"
                "[white]Expected runtime: 25-35 minutes (slower than Phase 1)[/white]",
                border_style="blue",
            )
        )
        console.print()

        # Drop and recreate tables with indexes
        log.warning("Dropping existing tables to recreate with indexes...")
        if not self.run_sql_phase(
            "4b",
            "Recreate Tables for Phase 2",
            self.sql_dir / "04_create_variants.sql",
            self.results_dir / "04b_create_variants_phase2.log",
        ):
            return False

        # Phase 5: Create Indexes
        if not self.run_sql_phase(
            "5",
            "Create Indexes (5 per variant, 20 total)",
            self.sql_dir / "05_create_indexes.sql",
            self.results_dir / "05_create_indexes.log",
        ):
            return False

        # Phase 6b: Streaming INSERTs with indexes (with progress)
        log_file = self.results_dir / "07_streaming_phase2.log"

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
            TimeElapsedColumn(),
            TimeRemainingColumn(),
            console=console,
        ) as progress:
            task = progress.add_task(
                "[cyan]Streaming INSERTs (Phase 2 - WITH INDEXES)", total=500
            )

            def update_progress(event_type, **kwargs):
                if event_type == "batch_progress":
                    batch_num = kwargs["batch_num"]
                    batch_size = kwargs["batch_size"]
                    total_rows = kwargs["total_rows"]
                    progress.update(
                        task,
                        completed=batch_num,
                        description=f"[cyan]Batch {batch_num}/500 ({batch_size:,} rows, {total_rows}M total) [WITH INDEXES]",
                    )
                elif event_type == "checkpoint":
                    batches = kwargs["batches"]
                    rows = kwargs["rows"]
                    progress.console.print(
                        f"[green]✓[/green] Checkpoint: {batches} batches, {rows}M rows"
                    )

            success = self.run_sql_phase(
                "6b",
                "Streaming INSERTs - Phase 2 (WITH INDEXES)",
                self.sql_dir / "07_streaming_inserts_withindex.sql",
                log_file,
                show_progress=True,
                progress_callback=update_progress,
            )

            if not success:
                return False

            progress.update(task, completed=500)

        # Re-cluster PAX after Phase 2
        log.info("Re-applying Z-order clustering to PAX tables...")
        if not self.run_sql_phase(
            "8b",
            "PAX Z-order Clustering (Phase 2)",
            self.sql_dir / "08_optimize_pax.sql",
            self.results_dir / "08b_optimize_pax_phase2.log",
        ):
            return False

        # Phase 9b: Query Performance
        if not self.run_sql_phase(
            "9b",
            "Query Performance Tests (after Phase 2)",
            self.sql_dir / "09_run_queries.sql",
            self.results_dir / "09b_queries_phase2.log",
        ):
            return False

        # Phase 10b: Collect Metrics (includes comparison)
        if not self.run_sql_phase(
            "10b",
            "Collect Metrics - Phase 2 (includes comparison)",
            self.sql_dir / "10_collect_metrics.sql",
            self.results_dir / "10_metrics_phase2.txt",
        ):
            return False

        # Phase 11b: Validate Phase 2
        if not self.run_sql_phase(
            "11b",
            "Validate Results - Phase 2",
            self.sql_dir / "11_validate_results.sql",
            self.results_dir / "11_validation_phase2.txt",
        ):
            return False

        # Check validation
        has_failures, failure_count = self.check_validation(
            self.results_dir / "11_validation_phase2.txt", "❌ FAILED"
        )
        if has_failures:
            log.error(
                f"Phase 2 validation failed! Review: {self.results_dir / '11_validation_phase2.txt'}"
            )
            return False
        else:
            console.print(
                "[green]✅ All validation gates passed for Phase 2[/green]"
            )

        return True

    def print_summary(self, phase_1_completed: bool, phase_2_completed: bool):
        """Print final summary"""
        total_duration = self.timer.total_elapsed()

        console.print()
        console.print(
            Panel.fit(
                f"[bold green]BENCHMARK COMPLETE![/bold green]\n\n"
                f"[white]Total runtime: {self.timer.format_duration(total_duration)}[/white]\n\n"
                f"[white]Phase 1 (no indexes): {'✅ Complete' if phase_1_completed else '❌ Failed/Skipped'}[/white]\n"
                f"[white]Phase 2 (with indexes): {'✅ Complete' if phase_2_completed else '❌ Failed/Skipped'}[/white]",
                title="Results Summary",
                border_style="green",
            )
        )
        console.print()

        # Show key files
        console.print("[bold]Results saved to:[/bold]", style="cyan")
        console.print(f"  📂 {self.results_dir}")
        console.print()
        console.print("[bold]Key files:[/bold]")

        if phase_1_completed:
            console.print(
                f"  • {self.results_dir / '10_metrics_phase1.txt'} - Phase 1 metrics"
            )
            console.print(
                f"  • {self.results_dir / '11_validation_phase1.txt'} - Phase 1 validation"
            )

        if phase_2_completed:
            console.print(
                f"  • {self.results_dir / '10_metrics_phase2.txt'} - Phase 2 metrics (includes comparison)"
            )
            console.print(
                f"  • {self.results_dir / '11_validation_phase2.txt'} - Phase 2 validation"
            )

        console.print(f"  • {self.timing_file} - Phase timings")
        console.print()

        if phase_1_completed and phase_2_completed:
            console.print("[bold green]SUCCESS![/bold green] Benchmark completed without errors.")
        else:
            console.print("[yellow]⚠️  Benchmark completed with some phases skipped/failed[/yellow]")
        console.print()

    def run(self) -> bool:
        """Main execution flow"""
        self.print_header()

        # Phase 0-4: Setup and validation
        if not self.run_phase_0_to_4():
            log.error("Setup and validation failed")
            return False

        # Phase 1: No indexes
        phase_1_completed = False
        if self.phase in ("1", "both"):
            if not self.run_phase_1():
                log.error("Phase 1 failed")
                return False
            phase_1_completed = True

            # If only Phase 1 requested, print summary and exit
            if self.phase == "1":
                self.print_summary(phase_1_completed, False)
                return True

        # Phase 2: With indexes
        phase_2_completed = False
        if self.phase in ("2", "both"):
            if not self.run_phase_2():
                log.error("Phase 2 failed")
                # Don't return False if user skipped Phase 2
                if phase_1_completed:
                    self.print_summary(phase_1_completed, False)
                    return True
                return False
            phase_2_completed = True

        # Print final summary
        self.print_summary(phase_1_completed, phase_2_completed)
        return True


def main():
    """Entry point"""
    parser = argparse.ArgumentParser(
        description="Streaming INSERT Benchmark - PAX vs AO/AOCO",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                           # Run both phases (interactive)
  %(prog)s --phase 1                 # Run Phase 1 only
  %(prog)s --phase 2                 # Run Phase 2 only (requires Phase 1 completed)
  %(prog)s --no-interactive          # Run both phases without prompts
  %(prog)s --verbose                 # Enable verbose logging
        """,
    )

    parser.add_argument(
        "--psql",
        default="psql postgres",
        help="PostgreSQL connection command (default: psql postgres)",
    )

    parser.add_argument(
        "--results-dir",
        type=Path,
        default=None,
        help="Results directory (default: results/run_YYYYMMDD_HHMMSS)",
    )

    parser.add_argument(
        "--phase",
        choices=["1", "2", "both"],
        default="both",
        help="Phase to run: 1 (no indexes), 2 (with indexes), or both (default: both)",
    )

    parser.add_argument(
        "--no-interactive",
        action="store_true",
        help="Skip interactive prompts (auto-continue to Phase 2)",
    )

    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Enable verbose output"
    )

    args = parser.parse_args()

    # Set logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Create results directory with timestamp
    if args.results_dir is None:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        results_dir = Path(__file__).parent.parent / "results" / f"run_{timestamp}"
    else:
        results_dir = args.results_dir

    # Create benchmark instance
    benchmark = StreamingBenchmark(
        psql_cmd=args.psql,
        results_dir=results_dir,
        phase=args.phase,
        no_interactive=args.no_interactive,
        verbose=args.verbose,
    )

    # Run benchmark
    try:
        success = benchmark.run()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        console.print("\n[yellow]Benchmark interrupted by user[/yellow]")
        sys.exit(130)
    except Exception as e:
        log.exception(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
