#!/usr/bin/env python3
"""
Compare benchmark results with custom labels for chart generation and CSV export.

This script generates comparison charts and exports data from each chart to separate CSV files.

Usage:
  # Method 1: Using JSON mapping file
  bin/compare_with_labels.py --mapping labels.json --output charts/

  # Method 2: Using command-line arguments
  bin/compare_with_labels.py \
    --files file1.json:label1 file2.json:label2 file3.json:label3 \
    --output charts/

Example labels.json:
{
  "1.no_config_keg_50percent_3kb-AWS-MSK-KEG-2025-10-28-21-48-06.json": "no_config",
  "2.consumer_header_keg_50percent_3kb-AWS-MSK-KEG-2025-10-28-22-06-43.json": "consumer_header",
  "3.consumer_content_keg_50percent_3kb-AWS-MSK-KEG-2025-10-28-22-22-01.json": "consumer_content",
  "6.msk_direct_keg_50percent_3kb-AWS-MSK-Kafka-2025-10-28-23-55-49.json": "msk_direct"
}

Output:
  - index.html: Interactive comparison charts
  - chart_throughput.csv: Throughput comparison
  - chart_publish_latency_percentiles.csv: Publish latency quantiles
  - chart_e2e_latency_percentiles.csv: End-to-end latency quantiles
  - chart_publish_latency_p99.csv: Publish latency p99 time series
  - chart_e2e_latency_avg.csv: E2E latency average time series
  - chart_e2e_latency_p50.csv: E2E latency p50 time series
  - chart_publish_rate.csv: Publish rate time series
  - chart_consume_rate.csv: Consume rate time series
  - chart_backlog.csv: Backlog time series
  - chart_summary_metrics.csv: All aggregated metrics in one table
"""

import argparse
import json
import os
import sys
import shutil
import tempfile
import subprocess
import csv
from pathlib import Path
from collections import OrderedDict


def create_labeled_files(file_label_map, temp_dir):
    """
    Create copies of JSON files with modified 'version' field for custom labels.

    Args:
        file_label_map: dict mapping filename -> custom label
        temp_dir: temporary directory to store modified files

    Returns:
        list of created file paths
    """
    created_files = []

    for filename, label in file_label_map.items():
        filepath = Path(filename)

        if not filepath.exists():
            print(f"Warning: File not found: {filename}", file=sys.stderr)
            continue

        try:
            # Load original JSON
            with open(filepath, 'r') as f:
                data = json.load(f)

            # Modify fields to ensure proper grouping and labeling
            # generate_charts.py builds labels as: version-driver-workload
            # and filters out empty parts with "if part"
            # We want only our custom label to appear

            # Set version to custom label
            data['version'] = label

            # Set driver and workload to empty so they don't appear in label
            # All files will group together since they have the same (empty) workload
            data['driver'] = ''
            data['workload'] = ''

            # Write to temp directory with original filename
            temp_filepath = Path(temp_dir) / filepath.name
            with open(temp_filepath, 'w') as f:
                json.dump(data, f, indent=2)

            created_files.append(temp_filepath)
            print(f"✓ Prepared: {filepath.name} → label: '{label}'")

        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in {filename}: {e}", file=sys.stderr)
        except Exception as e:
            print(f"Error processing {filename}: {e}", file=sys.stderr)

    return created_files


def generate_comparison_charts(temp_dir, output_dir, extra_args):
    """
    Call generate_charts.py on the temporary directory with modified files.

    Args:
        temp_dir: directory containing modified JSON files
        output_dir: output directory for charts
        extra_args: additional arguments to pass to generate_charts.py
    """
    # Get path to generate_charts.py
    script_dir = Path(__file__).parent
    generate_charts = script_dir / 'generate_charts.py'

    if not generate_charts.exists():
        print(f"Error: generate_charts.py not found at {generate_charts}", file=sys.stderr)
        sys.exit(1)

    # Build command
    cmd = [
        'python3',
        str(generate_charts),
        '--results', temp_dir,
        '--output', output_dir
    ]

    # Add extra arguments
    if extra_args:
        cmd.extend(extra_args)

    print(f"\nGenerating charts with command:")
    print(f"  {' '.join(cmd)}\n")

    # Run generate_charts.py
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)

        # Check if index.html was created
        index_file = Path(output_dir) / 'index.html'
        if index_file.exists():
            print(f"\n✅ Success! Charts generated at: {index_file}")
            print(f"\nOpen in browser:")
            print(f"  file://{index_file.absolute()}")
        else:
            print("\n⚠️  Warning: index.html not found in output directory", file=sys.stderr)

    except subprocess.CalledProcessError as e:
        print(f"Error running generate_charts.py: {e}", file=sys.stderr)
        if e.stdout:
            print(f"stdout: {e.stdout}", file=sys.stderr)
        if e.stderr:
            print(f"stderr: {e.stderr}", file=sys.stderr)
        sys.exit(1)


def export_csv_files(temp_dir, output_dir):
    """
    Export data from each chart type to separate CSV files.

    Args:
        temp_dir: directory containing modified JSON files
        output_dir: output directory for CSV files
    """
    print("\n" + "="*60)
    print("Exporting chart data to CSV files...")
    print("="*60)

    # Load all JSON files
    json_files = list(Path(temp_dir).glob("*.json"))
    if not json_files:
        print("No JSON files found to export")
        return

    datasets = []
    for json_file in sorted(json_files):
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
                datasets.append(data)
        except Exception as e:
            print(f"Error loading {json_file}: {e}", file=sys.stderr)

    if not datasets:
        print("No valid datasets found")
        return

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # 1. Export Throughput (MB/s) - Aggregated metrics
    export_throughput_csv(datasets, output_path / "chart_throughput.csv")

    # 2. Export Publish Latency Percentiles - Quantiles
    export_quantile_csv(datasets, output_path / "chart_publish_latency_percentiles.csv",
                       'aggregatedPublishLatencyQuantiles', 'Publish Latency (ms)')

    # 3. Export End-to-End Latency Percentiles - Quantiles
    export_quantile_csv(datasets, output_path / "chart_e2e_latency_percentiles.csv",
                       'aggregatedEndToEndLatencyQuantiles', 'E2E Latency (ms)')

    # 4. Export Publish Latency p99 - Time Series
    export_timeseries_csv(datasets, output_path / "chart_publish_latency_p99.csv",
                         'publishLatency99pct', 'Publish Latency p99 (ms)')

    # 5. Export End-to-End Latency Average - Time Series
    export_timeseries_csv(datasets, output_path / "chart_e2e_latency_avg.csv",
                         'endToEndLatencyAvg', 'E2E Latency Avg (ms)')

    # 6. Export End-to-End Latency P50 - Time Series
    export_timeseries_csv(datasets, output_path / "chart_e2e_latency_p50.csv",
                         'endToEndLatency50pct', 'E2E Latency P50 (ms)')

    # 7. Export Publish Rate - Time Series
    export_timeseries_csv(datasets, output_path / "chart_publish_rate.csv",
                         'publishRate', 'Publish Rate (msg/s)')

    # 8. Export Consume Rate - Time Series
    export_timeseries_csv(datasets, output_path / "chart_consume_rate.csv",
                         'consumeRate', 'Consume Rate (msg/s)')

    # 9. Export Backlog - Time Series
    export_timeseries_csv(datasets, output_path / "chart_backlog.csv",
                         'backlog', 'Backlog (messages)')

    # 10. Export Aggregated Metrics Summary
    export_summary_csv(datasets, output_path / "chart_summary_metrics.csv")

    print("="*60)
    print("✅ CSV export complete!\n")


def export_throughput_csv(datasets, filepath):
    """Export throughput bar chart data to CSV."""
    try:
        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Label', 'Throughput (MB/s)', 'Message Size (bytes)', 'Avg Publish Rate (msg/s)'])

            for data in datasets:
                label = data.get('version', 'unknown')
                msg_size = data.get('messageSize', 0)
                publish_rate = data.get('publishRate', [])

                if publish_rate and len(publish_rate) > 0:
                    avg_rate = sum(publish_rate) / len(publish_rate)
                    throughput_mbps = (avg_rate * msg_size) / (1024.0 * 1024.0)
                else:
                    avg_rate = 0
                    throughput_mbps = 0

                writer.writerow([label, f'{throughput_mbps:.2f}', msg_size, f'{avg_rate:.0f}'])

        print(f"  ✓ {filepath.name}")
    except Exception as e:
        print(f"  ✗ Error exporting {filepath.name}: {e}", file=sys.stderr)


def export_quantile_csv(datasets, filepath, field_name, value_label):
    """Export quantile chart data to CSV."""
    try:
        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)

            # Header: Percentile, Label1, Label2, ...
            labels = [data.get('version', 'unknown') for data in datasets]
            writer.writerow(['Percentile'] + labels)

            # Collect all percentiles across all datasets
            all_percentiles = set()
            for data in datasets:
                quantiles = data.get(field_name, {})
                all_percentiles.update(float(p) for p in quantiles.keys())

            # Sort percentiles
            sorted_percentiles = sorted(all_percentiles)

            # Write data rows
            for percentile in sorted_percentiles:
                row = [f'{percentile:.5f}']
                for data in datasets:
                    quantiles = data.get(field_name, {})
                    value = quantiles.get(str(percentile), '')
                    row.append(value)
                writer.writerow(row)

        print(f"  ✓ {filepath.name}")
    except Exception as e:
        print(f"  ✗ Error exporting {filepath.name}: {e}", file=sys.stderr)


def export_timeseries_csv(datasets, filepath, field_name, value_label):
    """Export time series chart data to CSV."""
    try:
        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)

            # Header: Time (seconds), Label1, Label2, ...
            labels = [data.get('version', 'unknown') for data in datasets]
            writer.writerow(['Time (seconds)'] + labels)

            # Find max length of time series
            max_length = 0
            for data in datasets:
                series = data.get(field_name, [])
                if len(series) > max_length:
                    max_length = len(series)

            # Write data rows (10-second intervals)
            for i in range(max_length):
                row = [i * 10]  # Time in seconds
                for data in datasets:
                    series = data.get(field_name, [])
                    value = series[i] if i < len(series) else ''
                    row.append(value)
                writer.writerow(row)

        print(f"  ✓ {filepath.name}")
    except Exception as e:
        print(f"  ✗ Error exporting {filepath.name}: {e}", file=sys.stderr)


def export_summary_csv(datasets, filepath):
    """Export summary metrics table to CSV."""
    try:
        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)

            # Header
            writer.writerow([
                'Label',
                'Message Size (bytes)',
                'Begin Time',
                'End Time',
                'Throughput (MB/s)',
                'Avg Publish Rate (msg/s)',
                'Publish Latency Min (ms)',
                'Publish Latency Avg (ms)',
                'Publish Latency P50 (ms)',
                'Publish Latency P75 (ms)',
                'Publish Latency P95 (ms)',
                'Publish Latency P99 (ms)',
                'Publish Latency P999 (ms)',
                'Publish Latency Max (ms)',
                'E2E Latency Min (ms)',
                'E2E Latency Avg (ms)',
                'E2E Latency P50 (ms)',
                'E2E Latency P75 (ms)',
                'E2E Latency P95 (ms)',
                'E2E Latency P99 (ms)',
                'E2E Latency P9999 (ms)',
                'E2E Latency Max (ms)',
            ])

            # Data rows
            for data in datasets:
                label = data.get('version', 'unknown')
                msg_size = data.get('messageSize', 0)
                begin_time = data.get('beginTime', '')
                end_time = data.get('endTime', '')

                # Calculate throughput
                publish_rate = data.get('publishRate', [])
                if publish_rate and len(publish_rate) > 0:
                    avg_rate = sum(publish_rate) / len(publish_rate)
                    throughput_mbps = (avg_rate * msg_size) / (1024.0 * 1024.0)
                else:
                    avg_rate = 0
                    throughput_mbps = 0

                # Get publish latency min (handle array)
                pub_lat_min = data.get('publishLatencyMin', [])
                if isinstance(pub_lat_min, list) and pub_lat_min:
                    pub_lat_min = min(pub_lat_min)
                else:
                    pub_lat_min = 0

                # Get E2E latency min (handle array)
                e2e_lat_min = data.get('endToEndLatencyMin', [])
                if isinstance(e2e_lat_min, list) and e2e_lat_min:
                    e2e_lat_min = min(e2e_lat_min)
                else:
                    e2e_lat_min = 0

                writer.writerow([
                    label,
                    msg_size,
                    begin_time,
                    end_time,
                    f'{throughput_mbps:.2f}',
                    f'{avg_rate:.0f}',
                    pub_lat_min,
                    data.get('aggregatedPublishLatencyAvg', 0),
                    data.get('aggregatedPublishLatency50pct', 0),
                    data.get('aggregatedPublishLatency75pct', 0),
                    data.get('aggregatedPublishLatency95pct', 0),
                    data.get('aggregatedPublishLatency99pct', 0),
                    data.get('aggregatedPublishLatency999pct', 0),
                    data.get('aggregatedPublishLatencyMax', 0),
                    e2e_lat_min,
                    data.get('aggregatedEndToEndLatencyAvg', 0),
                    data.get('aggregatedEndToEndLatency50pct', 0),
                    data.get('aggregatedEndToEndLatency75pct', 0),
                    data.get('aggregatedEndToEndLatency95pct', 0),
                    data.get('aggregatedEndToEndLatency99pct', 0),
                    data.get('aggregatedEndToEndLatency9999pct', 0),
                    data.get('aggregatedEndToEndLatencyMax', 0),
                ])

        print(f"  ✓ {filepath.name}")
    except Exception as e:
        print(f"  ✗ Error exporting {filepath.name}: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Compare benchmark results with custom chart labels',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    # Input methods (mutually exclusive)
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument(
        '--mapping',
        type=str,
        help='JSON file mapping filenames to labels: {"file.json": "label", ...}'
    )
    input_group.add_argument(
        '--files',
        nargs='+',
        help='List of file:label pairs, e.g., file1.json:label1 file2.json:label2'
    )

    # Output
    parser.add_argument(
        '--output',
        type=str,
        required=True,
        help='Output directory for generated charts'
    )

    # Optional arguments to pass to generate_charts.py
    parser.add_argument(
        '--coalesce-workloads',
        action='store_true',
        help='Put all workloads on a single set of charts'
    )
    parser.add_argument(
        '--image-format',
        choices=['inline', 'svg', 'png'],
        default='inline',
        help='Image format for charts (default: inline)'
    )

    args = parser.parse_args()

    # Parse input into file_label_map
    file_label_map = {}

    if args.mapping:
        # Load from JSON file
        mapping_path = Path(args.mapping)
        if not mapping_path.exists():
            print(f"Error: Mapping file not found: {args.mapping}", file=sys.stderr)
            sys.exit(1)

        try:
            with open(mapping_path, 'r') as f:
                file_label_map = json.load(f)
            print(f"Loaded {len(file_label_map)} file mappings from {args.mapping}")
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in mapping file: {e}", file=sys.stderr)
            sys.exit(1)

    elif args.files:
        # Parse file:label pairs
        for pair in args.files:
            if ':' not in pair:
                print(f"Error: Invalid file:label pair: {pair}", file=sys.stderr)
                print("Expected format: filename.json:label", file=sys.stderr)
                sys.exit(1)

            filename, label = pair.split(':', 1)
            file_label_map[filename] = label

        print(f"Using {len(file_label_map)} file:label pairs from command line")

    if not file_label_map:
        print("Error: No files to process", file=sys.stderr)
        sys.exit(1)

    # Create output directory
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Create temporary directory for modified files
    with tempfile.TemporaryDirectory() as temp_dir:
        print(f"\nPreparing files with custom labels...")
        created_files = create_labeled_files(file_label_map, temp_dir)

        if not created_files:
            print("Error: No files were successfully processed", file=sys.stderr)
            sys.exit(1)

        # Build extra arguments for generate_charts.py
        extra_args = []
        if args.coalesce_workloads:
            extra_args.append('--coalesce-workloads')
        if args.image_format != 'inline':
            extra_args.extend(['--image-format', args.image_format])

        # Generate charts
        generate_comparison_charts(temp_dir, str(output_dir), extra_args)

        # Export CSV files for each chart
        export_csv_files(temp_dir, str(output_dir))


if __name__ == '__main__':
    main()
