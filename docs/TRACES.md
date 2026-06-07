# Trace Archive Notes

The artifact includes two frozen trace archives.

## 4K/8K/16K Text Matrix

```text
traces/kiloware_longctx_text_tracegen_20260603.tar.gz
```

This archive contains the 4K, 8K, and 16K text long-context descriptor traces.

## 32K Stress Matrix

```text
traces/kiloware_longctx32_text_tracegen_20260604.tar.gz
```

This archive contains the 32K stress descriptor traces generated after the
main 4K/8K/16K matrix.

## What Is Not Included

The archives do not include model weights, tokenizer caches, or GPU runtime
caches. They contain the replay descriptors and metadata used downstream by the
KCMU trace-driven replay pipeline.

