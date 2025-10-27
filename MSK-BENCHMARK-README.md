# AWS MSK Benchmarking Guide

This guide covers the custom scripts and workflows added for benchmarking AWS MSK (Managed Streaming for Apache Kafka) and Kong Event Gateway.

## Table of Contents
- [Setup](#setup)
- [Configuration](#configuration)
- [Running Benchmarks](#running-benchmarks)
- [Merging Results](#merging-results)

## Setup

### Prerequisites

1. **Java 11+** and **Maven 3.6+**
   ```bash
   java -version
   mvn -version
   ```

2. **Python 3.7+** with required packages for visualization:
   ```bash
   pip3 install pandas matplotlib pygal jinja2
   ```

3. **Build the project:**
   ```bash
   mvn clean verify -DskipTests -Djacoco.skip -Dcheckstyle.skip -Dspotless.check.skip -Denforcer.skip -DskipChecks -Dspotbugs.skip -Dlicense.skip
   ```

### Creating Payload Files

The benchmark requires payload files for different message sizes:

```bash
mkdir -p payload

# Generate payload files
dd if=/dev/urandom of=payload/payload-1Kb.data bs=1024 count=1
dd if=/dev/urandom of=payload/payload-3Kb.data bs=1024 count=3
dd if=/dev/urandom of=payload/payload-10Kb.data bs=1024 count=10
dd if=/dev/urandom of=payload/payload-25Kb.data bs=1024 count=25
dd if=/dev/urandom of=payload/payload-50Kb.data bs=1024 count=50
```

## Configuration

### Driver Configuration

1. **Copy template files and configure:**
   ```bash
   cp driver-msk/msk-config.yaml.template driver-msk/msk-config.yaml
   cp driver-msk/msk-via-kong.yaml.template driver-msk/msk-via-kong.yaml
   ```

2. **Edit `driver-msk/msk-config.yaml`** with your MSK cluster details:
   - Replace `<REPLACE_WITH_YOUR_MSK_BROKERS>` with your MSK broker endpoints
   - Replace `<REPLACE_WITH_USERNAME>` with your SCRAM username
   - Replace `<REPLACE_WITH_PASSWORD>` with your SCRAM password

3. **Edit `driver-msk/msk-via-kong.yaml`** with your Kong Gateway details:
   - Replace `<REPLACE_WITH_KONG_GATEWAY_ENDPOINT>` with Kong's load balancer endpoint
   - Replace username and password accordingly

**Example MSK broker format:**
```yaml
bootstrap.servers=b-1.cluster.kafka.region.amazonaws.com:9096,b-2.cluster.kafka.region.amazonaws.com:9096
```

### Workload Configuration

Workload files are located in `workloads/` directory. Example files included:
- `msk-test-1kb.yaml` - 1KB message size
- `msk-test-3kb.yaml` - 3KB message size
- `msk-test-10kb.yaml` - 10KB message size
- `msk-test-25kb.yaml` - 25KB message size
- `msk-test-50kb.yaml` - 50KB message size

Each workload defines:
- Message size
- Number of topics and partitions
- Producer and consumer counts
- Test duration
- Producer rate

## Running Benchmarks

### Single Message Size Test

```bash
bin/benchmark -d driver-msk/msk-config.yaml workloads/msk-test-1kb.yaml
```

### Multiple Message Sizes (Automated)

Use the `run-msk-message-size-tests.sh` script to run benchmarks for all message sizes:

```bash
# Run MSK direct tests
./run-msk-message-size-tests.sh driver-msk/msk-config.yaml msk

# Run Kong Event Gateway tests
./run-msk-message-size-tests.sh driver-msk/msk-via-kong.yaml keg
```

**What it does:**
1. Runs benchmarks for 1kb, 3kb, 10kb, 25kb, and 50kb message sizes
2. Terminates each test automatically after results are written
3. Creates chart-optimized JSON files with clean labels
4. Generates summary statistics
5. Creates interactive HTML charts (if pygal is installed)
6. Outputs everything to `results-message-size-<timestamp>/` directory

**Output files:**
- `results-message-size-<timestamp>/`
  - `msk-test-*.json` - Original benchmark results
  - `chart-*.json` - Chart-optimized results with clean labels
  - `summary.txt` - Text summary of results
  - `index.html` - Interactive charts

## Merging Results

Use `merge-results.sh` to combine results from two different test runs (e.g., MSK vs Kong) into comparison charts:

```bash
./merge-results.sh <dir1> <version1> <dir2> <version2> <output_dir>
```

**Example:**
```bash
./merge-results.sh \
  results-message-size-20251023-021952 msk \
  results-message-size-20251023-004052 keg \
  results-combined
```

**What it does:**
1. Merges JSON results from two directories
2. Generates individual comparison HTML files for each message size
   - `compare-1kb.html` - MSK vs KEG for 1KB messages
   - `compare-3kb.html` - MSK vs KEG for 3KB messages
   - etc.
3. Generates a combined HTML file with all results: `all-results.html`
4. Creates corresponding CSV files for data analysis
   - `compare-1kb.csv`
   - `compare-3kb.csv`
   - `all-results.csv`

**Output structure:**
```
results-combined/
├── compare-1kb.html       # Individual comparison charts
├── compare-1kb.csv
├── compare-3kb.html
├── compare-3kb.csv
├── ...
├── all-results.html       # Combined view of all sizes
├── all-results.csv
├── for-individual/        # Intermediate files
└── for-combined/          # Intermediate files
```

