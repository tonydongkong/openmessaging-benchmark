Built by running:

```
for i in 10 20 30 40 50 60 70 80 90; do
    for j in 1024 2048 3072 10240; do
        mise run generate-payloads --output-dir out/payloads_${i}percent_size${j} -f "customer_id=cust1:${i},cust2:$((100 - ${i}))" -h "customer_id=cust1:${i},cust2:$((100 - ${i}))" -s ${j}
    done
done
```

on https://github.com/kong-gateway/keg_demos_aws/pull/1

This contains data that has headers and values with `customer_id` with 70% of cust1 and 30% of cust2.

Note to make this more compatible with https://github.com/deviceinsight/kafkactl/pull/304/files we will most likely change `data` to `value` at some point in the future.

