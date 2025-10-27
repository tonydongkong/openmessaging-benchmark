#!/bin/bash

# Script to merge two test result directories into a combined chart
# Usage: ./merge-results.sh <dir1> <version1> <dir2> <version2> <output_dir>

set -e

if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <dir1> <version1> <dir2> <version2> <output_dir>"
    echo "Example: $0 results-message-size-20251022-190402 msk results-message-size-20251022-203843 keg results-combined"
    exit 1
fi

DIR1="$1"
VERSION1="$2"
DIR2="$3"
VERSION2="$4"
OUTPUT_DIR="$5"

# Validate input directories exist
if [ ! -d "$DIR1" ]; then
    echo "Error: Directory $DIR1 does not exist"
    exit 1
fi

if [ ! -d "$DIR2" ]; then
    echo "Error: Directory $DIR2 does not exist"
    exit 1
fi

# Create output directory and subdirectories
mkdir -p "$OUTPUT_DIR/for-individual"
mkdir -p "$OUTPUT_DIR/for-combined"

echo "Merging test results from:"
echo "  $DIR1 (version: $VERSION1)"
echo "  $DIR2 (version: $VERSION2)"
echo "Into: $OUTPUT_DIR"
echo ""

# Process files from first directory
echo "Processing files from $DIR1..."
for file in "$DIR1"/chart-*.json; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "  Processing $filename with version $VERSION1"

        # For individual comparisons: use existing version field (already has format "msk-1kb")
        # Just copy the file as-is since version field already contains the full label
        cp "$file" "$OUTPUT_DIR/for-individual/$filename"

        # For combined view: same as individual
        cp "$file" "$OUTPUT_DIR/for-combined/$filename"
    fi
done

# Process files from second directory
echo "Processing files from $DIR2..."
for file in "$DIR2"/chart-*.json; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        new_filename="${VERSION2}-${filename}"
        echo "  Processing $filename with version $VERSION2 -> $new_filename"

        # For individual comparisons: use existing version field (already has format "keg-1kb")
        # Just copy the file as-is since version field already contains the full label
        cp "$file" "$OUTPUT_DIR/for-individual/$new_filename"

        # For combined view: same as individual
        cp "$file" "$OUTPUT_DIR/for-combined/$new_filename"
    fi
done

# Generate individual comparison charts for each message size
echo ""
echo "Generating individual comparison charts for each message size..."

for size in 1kb 3kb 10kb 25kb 50kb; do
    COMPARE_DIR="$OUTPUT_DIR/compare-${size}"
    mkdir -p "$COMPARE_DIR"

    # Copy files for this specific message size from for-individual directory
    file_count=0
    for file in "$OUTPUT_DIR/for-individual"/chart-*-${size}-*.json "$OUTPUT_DIR/for-individual"/${VERSION2}-chart-*-${size}-*.json; do
        if [ -f "$file" ]; then
            cp "$file" "$COMPARE_DIR/"
            file_count=$((file_count + 1))
        fi
    done

    if [ $file_count -gt 0 ]; then
        echo "  Generating comparison chart for ${size}..."
        bin/generate_charts.py --results "$COMPARE_DIR" --output "$COMPARE_DIR/"

        if [ -f "$COMPARE_DIR/index.html" ]; then
            # Move to parent directory with descriptive name
            mv "$COMPARE_DIR/index.html" "$OUTPUT_DIR/compare-${size}.html"
            echo "    ✅ Created: $OUTPUT_DIR/compare-${size}.html (${VERSION1}--${size} vs ${VERSION2}--${size})"
        fi
    else
        echo "    ⚠️  No files found for ${size}"
    fi
done

# Generate combined chart with all results
echo ""
echo "Generating combined chart with all results..."
bin/generate_charts.py --results "$OUTPUT_DIR/for-combined" --output "$OUTPUT_DIR/"

if [ -f "$OUTPUT_DIR/index.html" ]; then
    # Rename to all-results.html for clarity
    mv "$OUTPUT_DIR/index.html" "$OUTPUT_DIR/all-results.html"
    echo "✅ Created: $OUTPUT_DIR/all-results.html (all message sizes combined)"
else
    echo "❌ Error: Failed to generate combined chart"
    exit 1
fi

# Generate CSV files
echo ""
echo "Generating CSV files..."

# CSV header
CSV_HEADER="Label,Version,Message Size,Begin Time,End Time,Avg Throughput (msg/s),Throughput (MB/s),Publish Latency Min (ms),Publish Latency Avg (ms),Publish Latency P50 (ms),Publish Latency P75 (ms),Publish Latency P95 (ms),Publish Latency P99 (ms),Publish Latency P999 (ms),Publish Latency Max (ms),E2E Latency Min (ms),E2E Latency Avg (ms),E2E Latency P50 (ms),E2E Latency P75 (ms),E2E Latency P95 (ms),E2E Latency P99 (ms),E2E Latency P999 (ms),E2E Latency P9999 (ms),E2E Latency Max (ms)"

# Generate individual comparison CSVs
for size in 1kb 3kb 10kb 25kb 50kb; do
    CSV_FILE="$OUTPUT_DIR/compare-${size}.csv"
    echo "$CSV_HEADER" > "$CSV_FILE"

    # Find files for this size
    for file in "$OUTPUT_DIR/for-individual"/chart-*-${size}-*.json "$OUTPUT_DIR/for-individual"/*-chart-*-${size}-*.json; do
        if [ -f "$file" ]; then
            label=$(jq -r '.version' "$file")
            jq -r --arg label "$label" '
                (if .publishRate and (.publishRate | type == "array") then (.publishRate | add / length | floor) else 0 end) as $avgThroughput |
                (if .endToEndLatencyMin and (.endToEndLatencyMin | type == "array") then (.endToEndLatencyMin | min) else (.endToEndLatencyMin // 0) end) as $e2eMin |
                (if .publishLatencyMin and (.publishLatencyMin | type == "array") then (.publishLatencyMin | min) else (.publishLatencyMin // 0) end) as $pubMin |
                [
                    $label,
                    (.version // ""),
                    (.workload // ""),
                    (.beginTime // ""),
                    (.endTime // ""),
                    $avgThroughput,
                    (.throughputMBps // 0),
                    $pubMin,
                    (.aggregatedPublishLatencyAvg // 0),
                    (.aggregatedPublishLatency50pct // 0),
                    (.aggregatedPublishLatency75pct // 0),
                    (.aggregatedPublishLatency95pct // 0),
                    (.aggregatedPublishLatency99pct // 0),
                    (.aggregatedPublishLatency999pct // 0),
                    (.aggregatedPublishLatencyMax // 0),
                    $e2eMin,
                    (.aggregatedEndToEndLatencyAvg // 0),
                    (.aggregatedEndToEndLatency50pct // 0),
                    (.aggregatedEndToEndLatency75pct // 0),
                    (.aggregatedEndToEndLatency95pct // 0),
                    (.aggregatedEndToEndLatency99pct // 0),
                    (.aggregatedEndToEndLatency9999pct // 0),
                    (.aggregatedEndToEndLatency9999pct // 0),
                    (.aggregatedEndToEndLatencyMax // 0)
                ] | @csv
            ' "$file" >> "$CSV_FILE"
        fi
    done

    if [ -f "$CSV_FILE" ]; then
        line_count=$(wc -l < "$CSV_FILE")
        if [ "$line_count" -gt 1 ]; then
            echo "  ✅ Created: $OUTPUT_DIR/compare-${size}.csv"
        else
            rm "$CSV_FILE"
        fi
    fi
done

# Generate combined CSV
COMBINED_CSV="$OUTPUT_DIR/all-results.csv"
echo "$CSV_HEADER" > "$COMBINED_CSV"

for file in "$OUTPUT_DIR/for-combined"/*.json; do
    if [ -f "$file" ]; then
        label=$(jq -r '.version' "$file")
        jq -r --arg label "$label" '
            (if .publishRate and (.publishRate | type == "array") then (.publishRate | add / length | floor) else 0 end) as $avgThroughput |
            (if .endToEndLatencyMin and (.endToEndLatencyMin | type == "array") then (.endToEndLatencyMin | min) else (.endToEndLatencyMin // 0) end) as $e2eMin |
            (if .publishLatencyMin and (.publishLatencyMin | type == "array") then (.publishLatencyMin | min) else (.publishLatencyMin // 0) end) as $pubMin |
            [
                $label,
                (.version // ""),
                (.workload // ""),
                (.beginTime // ""),
                (.endTime // ""),
                $avgThroughput,
                (.throughputMBps // 0),
                $pubMin,
                (.aggregatedPublishLatencyAvg // 0),
                (.aggregatedPublishLatency50pct // 0),
                (.aggregatedPublishLatency75pct // 0),
                (.aggregatedPublishLatency95pct // 0),
                (.aggregatedPublishLatency99pct // 0),
                (.aggregatedPublishLatency999pct // 0),
                (.aggregatedPublishLatencyMax // 0),
                $e2eMin,
                (.aggregatedEndToEndLatencyAvg // 0),
                (.aggregatedEndToEndLatency50pct // 0),
                (.aggregatedEndToEndLatency75pct // 0),
                (.aggregatedEndToEndLatency95pct // 0),
                (.aggregatedEndToEndLatency99pct // 0),
                (.aggregatedEndToEndLatency9999pct // 0),
                (.aggregatedEndToEndLatency9999pct // 0),
                (.aggregatedEndToEndLatencyMax // 0)
            ] | @csv
        ' "$file" >> "$COMBINED_CSV"
    fi
done
echo "  ✅ Created: $OUTPUT_DIR/all-results.csv"

echo ""
echo "=========================================="
echo "✅ Success! Generated 6 HTML files and 6 CSV files:"
echo "=========================================="
echo "Individual comparisons:"
echo "  HTML: $OUTPUT_DIR/compare-1kb.html   CSV: $OUTPUT_DIR/compare-1kb.csv"
echo "  HTML: $OUTPUT_DIR/compare-3kb.html   CSV: $OUTPUT_DIR/compare-3kb.csv"
echo "  HTML: $OUTPUT_DIR/compare-10kb.html  CSV: $OUTPUT_DIR/compare-10kb.csv"
echo "  HTML: $OUTPUT_DIR/compare-25kb.html  CSV: $OUTPUT_DIR/compare-25kb.csv"
echo "  HTML: $OUTPUT_DIR/compare-50kb.html  CSV: $OUTPUT_DIR/compare-50kb.csv"
echo ""
echo "Combined view:"
echo "  HTML: $OUTPUT_DIR/all-results.html   CSV: $OUTPUT_DIR/all-results.csv"
echo "=========================================="
