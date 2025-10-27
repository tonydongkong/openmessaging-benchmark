#!/bin/bash

# Script to run MSK benchmarks with different message sizes and generate charts
# Usage: ./run-msk-message-size-tests.sh [driver-config] [version-label]

DRIVER_CONFIG="${1:-driver-msk/msk-config.yaml}"
VERSION_LABEL="${2:-test}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR="results-message-size-${TIMESTAMP}"

# Extract a cleaner driver name for labeling
DRIVER_NAME=$(basename ${DRIVER_CONFIG} .yaml)

mkdir -p "${RESULTS_DIR}"

MESSAGE_SIZES=("1kb" "3kb" "10kb" "25kb" "50kb")

echo "=========================================="
echo "MSK Message Size Benchmark Test Suite"
echo "Driver: ${DRIVER_CONFIG}"
echo "Results Directory: ${RESULTS_DIR}"
echo "Version Label: ${VERSION_LABEL}"
echo "Start Time: $(date)"
echo "=========================================="
echo ""

for size in "${MESSAGE_SIZES[@]}"; do
    echo "=========================================="
    echo "Testing message size: ${size}"
    echo "Time: $(date)"
    echo "=========================================="

    WORKLOAD="workloads/msk-test-${size}.yaml"

    if [ ! -f "${WORKLOAD}" ]; then
        echo "ERROR: Workload file not found: ${WORKLOAD}"
        continue
    fi

    echo "Running: bin/benchmark -d ${DRIVER_CONFIG} ${WORKLOAD}"
    echo ""

    # Run benchmark and watch for the "Writing test result" message
    bin/benchmark -d "${DRIVER_CONFIG}" "${WORKLOAD}" 2>&1 | while IFS= read -r line; do
        echo "$line"
        # Check if this line indicates the result file is being written
        if [[ "$line" == *"Writing test result into"* ]]; then
            echo ""
            echo "→ Detected result file being written, will terminate in 3 seconds..."
            sleep 3
            # Kill the parent benchmark process
            pkill -P $$ -f "bin/benchmark"
            pkill -f "bin/benchmark"
            break
        fi
    done

    echo ""
    echo "Benchmark process terminated"
    sleep 2

    # Copy result files to results directory and fix metadata for cleaner chart labels
    FOUND_RESULTS=false
    for result_file in msk-test-${size}-*.json; do
        if [ -f "${result_file}" ]; then
            FOUND_RESULTS=true
            echo "Processing result file: ${result_file}"

            # Keep original in results dir
            cp "${result_file}" "${RESULTS_DIR}/"

            # Create a modified version with clean labels for charting
            # Use format: version-size (e.g., "msk-1kb") by putting it all in version field
            # and setting driver and workload to empty to get clean labels
            jq --arg version "${VERSION_LABEL}" --arg size "${size}" \
                '. + {version: ($version + "-" + $size), driver: "", workload: ""}' \
                "${result_file}" > "${RESULTS_DIR}/chart-${result_file}"

            # Remove the benchmark output file from current directory
            rm "${result_file}"
        fi
    done

    if [ "$FOUND_RESULTS" = false ]; then
        echo "⚠️  WARNING: No result file found for ${size}"
    fi

    echo ""
    echo "Completed ${size} test at $(date)"
    echo ""

    # Wait a bit between tests to let the cluster settle
    sleep 10
done

echo "=========================================="
echo "All tests completed!"
echo "End Time: $(date)"
echo "=========================================="
echo ""
echo "Results stored in: ${RESULTS_DIR}"
echo ""

# Create a summary report
echo "Creating summary report..."
cat > "${RESULTS_DIR}/summary.txt" << 'SUMMARY'
Message Size Benchmark Results
================================

SUMMARY

for size in "${MESSAGE_SIZES[@]}"; do
    result_file=$(ls "${RESULTS_DIR}"/msk-test-${size}-*.json 2>/dev/null | head -1)

    if [ -f "${result_file}" ]; then
        echo "" >> "${RESULTS_DIR}/summary.txt"
        echo "=== ${size} ===" >> "${RESULTS_DIR}/summary.txt"

        # Parse the JSON and create summary
        cat "${result_file}" | jq -r '"Throughput: " + (.aggregatedPublishRate | floor | tostring) + " msg/s, " + ((.aggregatedPublishRate * .messageSize / 1024 / 1024) | floor | tostring) + " MB/s" + "\nPublish Latency - Avg: " + (.aggregatedPublishLatencyAvg | tostring) + "ms, P95: " + (.aggregatedPublishLatency95pct | tostring) + "ms, P99: " + (.aggregatedPublishLatency99pct | tostring) + "ms" + "\nE2E Latency - Avg: " + (.aggregatedEndToEndLatencyAvg | tostring) + "ms, P95: " + (.aggregatedEndToEndLatency95pct | tostring) + "ms, P99: " + (.aggregatedEndToEndLatency99pct | tostring) + "ms"' >> "${RESULTS_DIR}/summary.txt" 2>&1

        if [ $? -ne 0 ]; then
            echo "Failed to parse ${result_file}" >> "${RESULTS_DIR}/summary.txt"
        fi
    fi
done

cat "${RESULTS_DIR}/summary.txt"

# Generate charts using the built-in script
echo ""
echo "=========================================="
echo "Generating interactive charts..."
echo "=========================================="

if [ -f "bin/generate_charts.py" ]; then
    # Check if pygal is installed
    if python3 -c "import pygal" 2>/dev/null; then
        # Create a temporary directory with only the chart-optimized JSON files
        CHART_DIR="${RESULTS_DIR}/chart-data"
        mkdir -p "${CHART_DIR}"

        # Copy only the chart-* files (which have clean labels) and remove the chart-prefix
        for chart_file in "${RESULTS_DIR}"/chart-*.json; do
            if [ -f "${chart_file}" ]; then
                # Remove 'chart-' prefix for the chart directory
                basename_file=$(basename "${chart_file}" | sed 's/^chart-//')
                cp "${chart_file}" "${CHART_DIR}/${basename_file}"
                echo "Added to charts: ${basename_file}"
            fi
        done

        # Generate combined charts with all message sizes on one chart
        echo "Generating charts from: ${CHART_DIR}"
        python3 bin/generate_charts.py \
            --results "${CHART_DIR}" \
            --output "${RESULTS_DIR}/" \
            --image-format inline \
            --coalesce-workloads 2>&1 | grep -v "^{" || true

        # Clean up temporary chart data directory
        rm -rf "${CHART_DIR}"

        echo ""
        echo "Charts generated successfully!"
        echo "Open the chart report: ${RESULTS_DIR}/index.html"
        echo ""
        echo "To view charts, run:"
        echo "  open ${RESULTS_DIR}/index.html  # macOS"
        echo "  xdg-open ${RESULTS_DIR}/index.html  # Linux"
        echo "  Or copy the file to your local machine and open in browser"
    else
        echo "WARNING: pygal not installed. Charts will not be generated."
        echo "To install: pip3 install pygal jinja2"
    fi
else
    echo "WARNING: generate_charts.py not found"
fi

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Results directory: ${RESULTS_DIR}"
echo "Version label: ${VERSION_LABEL}"
echo "Original JSON files: ${RESULTS_DIR}/msk-test-*.json"
echo "Chart-optimized files: ${RESULTS_DIR}/chart-*.json"
echo "Summary report: ${RESULTS_DIR}/summary.txt"
echo "Interactive charts: ${RESULTS_DIR}/index.html"
echo "Chart labels: ${VERSION_LABEL}-1kb, ${VERSION_LABEL}-3kb, ${VERSION_LABEL}-10kb, ${VERSION_LABEL}-25kb, ${VERSION_LABEL}-50kb"
echo "=========================================="
