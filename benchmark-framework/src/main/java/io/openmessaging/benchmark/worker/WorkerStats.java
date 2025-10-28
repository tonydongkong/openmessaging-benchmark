/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package io.openmessaging.benchmark.worker;


import io.openmessaging.benchmark.worker.commands.CountersStats;
import io.openmessaging.benchmark.worker.commands.CumulativeLatencies;
import io.openmessaging.benchmark.worker.commands.PeriodStats;
import java.io.IOException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.LongAdder;
import org.HdrHistogram.Recorder;
import org.apache.bookkeeper.stats.Counter;
import org.apache.bookkeeper.stats.OpStatsLogger;
import org.apache.bookkeeper.stats.StatsLogger;

public class WorkerStats {

    private final StatsLogger statsLogger;

    private final OpStatsLogger publishDelayLatencyStats;

    private final Recorder endToEndLatencyRecorder = new Recorder(TimeUnit.HOURS.toMicros(12), 5);
    private final Recorder endToEndCumulativeLatencyRecorder =
            new Recorder(TimeUnit.HOURS.toMicros(12), 5);
    private final OpStatsLogger endToEndLatencyStats;

    private final LongAdder messagesSent = new LongAdder();
    private final LongAdder messageSendErrors = new LongAdder();
    private final LongAdder bytesSent = new LongAdder();
    private final Counter messageSendErrorCounter;
    private final Counter messagesSentCounter;
    private final Counter bytesSentCounter;

    private final LongAdder messagesReceived = new LongAdder();
    private final LongAdder bytesReceived = new LongAdder();
    private final Counter messagesReceivedCounter;
    private final Counter bytesReceivedCounter;

    private final LongAdder totalMessagesSent = new LongAdder();
    private final LongAdder totalMessageSendErrors = new LongAdder();
    private final LongAdder totalMessagesReceived = new LongAdder();

    private static final long highestTrackableValue = TimeUnit.SECONDS.toMicros(60);
    private final Recorder publishLatencyRecorder = new Recorder(highestTrackableValue, 5);
    private final Recorder cumulativePublishLatencyRecorder = new Recorder(highestTrackableValue, 5);
    private final OpStatsLogger publishLatencyStats;

    private final Recorder publishDelayLatencyRecorder = new Recorder(highestTrackableValue, 5);
    private final Recorder cumulativePublishDelayLatencyRecorder =
            new Recorder(highestTrackableValue, 5);

    WorkerStats(StatsLogger statsLogger) {
        this.statsLogger = statsLogger;

        StatsLogger producerStatsLogger = statsLogger.scope("producer");
        this.messagesSentCounter = producerStatsLogger.getCounter("messages_sent");
        this.messageSendErrorCounter = producerStatsLogger.getCounter("message_send_errors");
        this.bytesSentCounter = producerStatsLogger.getCounter("bytes_sent");
        this.publishDelayLatencyStats = producerStatsLogger.getOpStatsLogger("producer_delay_latency");
        this.publishLatencyStats = producerStatsLogger.getOpStatsLogger("produce_latency");

        StatsLogger consumerStatsLogger = statsLogger.scope("consumer");
        this.messagesReceivedCounter = consumerStatsLogger.getCounter("messages_recv");
        this.bytesReceivedCounter = consumerStatsLogger.getCounter("bytes_recv");
        this.endToEndLatencyStats = consumerStatsLogger.getOpStatsLogger("e2e_latency");
    }

    public StatsLogger getStatsLogger() {
        return statsLogger;
    }

    public void recordMessageSent() {
        totalMessagesSent.increment();
    }

    public void recordMessageReceived(long payloadLength, long endToEndLatencyMicros) {
        messagesReceived.increment();
        totalMessagesReceived.increment();
        messagesReceivedCounter.inc();
        bytesReceived.add(payloadLength);
        bytesReceivedCounter.add(payloadLength);

        if (endToEndLatencyMicros > 0) {
            endToEndCumulativeLatencyRecorder.recordValue(endToEndLatencyMicros);
            endToEndLatencyRecorder.recordValue(endToEndLatencyMicros);
            endToEndLatencyStats.registerSuccessfulEvent(endToEndLatencyMicros, TimeUnit.MICROSECONDS);
        }
    }

    public void recordMessageSendError() {
        messageSendErrors.increment();
        totalMessageSendErrors.increment();
        messageSendErrorCounter.inc();
    }

    public void recordProducerSuccess(
            long payloadLength, long intendedSendTime, long sendTime, long nowNs) {
        messagesSent.increment();
        totalMessagesSent.increment();
        messagesSentCounter.inc();
        bytesSent.add(payloadLength);
        bytesSentCounter.add(payloadLength);

        long latencyMicros = TimeUnit.NANOSECONDS.toMicros(nowNs - sendTime);
        publishLatencyRecorder.recordValue(latencyMicros);
        cumulativePublishLatencyRecorder.recordValue(latencyMicros);
        publishLatencyStats.registerSuccessfulEvent(latencyMicros, TimeUnit.MICROSECONDS);

        final long sendDelayMicros = TimeUnit.NANOSECONDS.toMicros(sendTime - intendedSendTime);
        publishDelayLatencyRecorder.recordValue(sendDelayMicros);
        cumulativePublishDelayLatencyRecorder.recordValue(sendDelayMicros);
        publishDelayLatencyStats.registerSuccessfulEvent(sendDelayMicros, TimeUnit.MICROSECONDS);
    }

    public void recordProducerFailure() {
        recordMessageSendError();
    }

    public PeriodStats toPeriodStats() {
        PeriodStats stats = new PeriodStats();

        stats.messagesSent = messagesSent.sumThenReset();
        stats.bytesSent = bytesSent.sumThenReset();
        stats.errors = messageSendErrors.sumThenReset();

        stats.messagesReceived = messagesReceived.sumThenReset();
        stats.bytesReceived = bytesReceived.sumThenReset();

        stats.totalMessagesSent = totalMessagesSent.sum();
        stats.totalErrors = totalMessageSendErrors.sum();
        stats.totalMessagesReceived = totalMessagesReceived.sum();

        stats.publishLatency = publishLatencyRecorder.getIntervalHistogram();
        stats.publishDelayLatency = publishDelayLatencyRecorder.getIntervalHistogram();
        stats.endToEndLatency = endToEndLatencyRecorder.getIntervalHistogram();

        return stats;
    }

    public CountersStats toCountersStats() throws IOException {
        CountersStats stats = new CountersStats();
        stats.messagesSent = totalMessagesSent.sum();
        stats.messagesReceived = totalMessagesReceived.sum();
        return stats;
    }

    public CumulativeLatencies toCumulativeLatencies() {
        CumulativeLatencies agg = new CumulativeLatencies();
        agg.publishLatency = cumulativePublishLatencyRecorder.getIntervalHistogram();
        agg.publishDelayLatency = cumulativePublishDelayLatencyRecorder.getIntervalHistogram();
        agg.endToEndLatency = endToEndCumulativeLatencyRecorder.getIntervalHistogram();
        return agg;
    }

    public void resetStats() {
        messagesSent.reset();
        bytesSent.reset();
        messageSendErrors.reset();

        messagesReceived.reset();
        bytesReceived.reset();

        publishLatencyRecorder.reset();
        publishDelayLatencyRecorder.reset();
        endToEndLatencyRecorder.reset();
    }
}
