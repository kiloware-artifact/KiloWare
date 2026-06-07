#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

try:
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    HF_AVAILABLE = True
except Exception:
    torch = None
    AutoModelForCausalLM = None
    AutoTokenizer = None
    HF_AVAILABLE = False


KCMU_OP_RD = 1
KCMU_OP_WR = 2
PHASE_PREFILL = 0
PHASE_DECODE = 1
KV_KIND_K = 0
KV_KIND_V = 1


@dataclass
class HFWorkloadMeta:
    name: str
    prefetch_enable: int
    description: str
    tags: list[str]
    trace_file: str
    op_count: int
    trace_mode: str = "legacy"
    runtime_meta_file: str | None = None
    expect_file: str | None = None
    payload_file: str | None = None


@dataclass
class HFWorkloadSpec:
    name: str
    prompts: list[str]
    max_new_tokens: int
    top_k_per_head: int
    trace_mode: str
    prefetch_enable: int
    description: str
    tags: list[str]
    metadata: dict[str, Any] | None = None


QUERY_SUMMARY_PROFILES = (
    "stable",
    "haqu_s4_tuned",
    "v2_consensus",
    "v2_usefulness",
    "v3_temporal",
    "v4_evidence_temporal",
    "v5_crossdoc",
    "v6_usefulness_cost",
    "v7_cost_v2",
    "rpau_v1",
    "rpau_reuse_v2",
    "qsr_v1",
    "qrc_v1",
    "autopareto_v1",
    "cas_u_lite",
    "temporal_aware",
    "temporal_aware_v2",
    "temporal_query_hybrid",
    "query_structure_aware",
    "query_structure_decoupled",
    "scheduler_temporal_v1",
    "structured_query_v2",
    "scheduler_temporal_query_hybrid_v1",
    "sched_master_temporal",
    "sched_master_structured",
    "sched_master_hybrid",
    "kspu_epoch_selector_v220",
)
SERVICE_CRITICALITY_PROFILES = ("current", "v2_hard", "v2_soft", "v3_rescue_soft", "v4_issue_soft")

QUERY_SUMMARY_PROFILE_ALIASES = {
    "sched_master_temporal": "scheduler_temporal_v1",
    "sched_master_structured": "structured_query_v2",
    "sched_master_hybrid": "scheduler_temporal_query_hybrid_v1",
}


def fail_missing_deps() -> None:
    print(
        "ERROR: hf_runtime_tracegen.py requires both 'torch' and 'transformers'. "
        "Use the project ML venv or install them first.",
        file=sys.stderr,
    )
    sys.exit(2)


def emit_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def normalize_query_summary_profile(profile: str) -> str:
    return QUERY_SUMMARY_PROFILE_ALIASES.get(profile, profile)


def emit_payload(path: Path, payload_words: list[int]) -> None:
    lines = [
        "# descriptor write payload words",
        "# format=one 32-bit hex word per line",
    ]
    lines.extend(f"{word & 0xFFFFFFFF:08X}" for word in payload_words)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def emit_trace(path: Path, name: str, description: str, commands: list[dict[str, int]], trace_mode: str) -> None:
    if trace_mode == "descriptor":
        lines = [
            f"# workload={name}",
            f"# description={description}",
            "# mode=descriptor",
            "# format=op base_addr_hex len_dec score_hex seq_id phase kv_kind attn_valid attn_score_hex recent_rank_dec token_block_id_hex attn_epoch_dec head_budget_class_dec query_relevance_hex compression_risk_dec spill_cost_dec service_criticality_hex policy_select_s5_dec temporal_persist_class_dec reuse_distance_class_dec query_structure_class_dec sched_urgency_hint_dec sig_valid_dec query_sig_hex key_sig_hex prefix_class_dec router_class_dec",
        ]
        for c in commands:
            lines.append(
                f"{c['op']:d} {c['base_addr']:02X} {c['len']:d} {c['score']:02X} "
                f"{c['seq_id']:d} {c['phase']:d} {c['kv_kind']:d} "
                f"{c['attn_valid']:d} {c['attn_score']:02X} {c['recent_rank']:d} "
                f"{c['token_block_id']:04X} {c['attn_epoch']:d} "
                f"{c['head_budget_class']:d} {c['query_relevance']:02X} "
                f"{c['compression_risk']:d} {c['spill_cost']:d} "
                f"{c['service_criticality']:02X} {c.get('policy_select_s5', 1):d} "
                f"{c.get('temporal_persist_class', 0):d} {c.get('reuse_distance_class', 0):d} "
                f"{c.get('query_structure_class', 0):d} {c.get('sched_urgency_hint', 0):d} "
                f"{c.get('sig_valid', 0):d} {c.get('query_sig', 0):02X} {c.get('key_sig', 0):02X} "
                f"{c.get('prefix_class', 0):d} {c.get('router_class', 0):d}"
            )
    else:
        lines = [
            f"# workload={name}",
            f"# description={description}",
            "# mode=legacy",
            "# format=op addr_hex wdata_hex meta_valid seq_id phase kv_kind layer head token_hex prio",
        ]
        for c in commands:
            lines.append(
                f"{c['op']:d} {c['addr']:02X} {c['wdata']:08X} {c['meta_valid']:d} "
                f"{c['seq_id']:d} {c['phase']:d} {c['kv_kind']:d} {c['layer']:d} "
                f"{c['head']:d} {c['token']:03X} {c['prio']:d}"
            )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd(
    op: int,
    addr: int,
    wdata: int,
    seq_id: int,
    phase: int,
    kv_kind: int,
    layer: int,
    head: int,
    token: int,
    prio: int,
) -> dict[str, int]:
    return {
        "op": op & 0x3,
        "addr": addr & 0xFF,
        "wdata": wdata & 0xFFFFFFFF,
        "meta_valid": 1,
        "seq_id": seq_id & 0xFF,
        "phase": phase & 0x1,
        "kv_kind": kv_kind & 0x1,
        "layer": layer & 0x7,
        "head": head & 0x3,
        "token": token & 0xFFF,
        "prio": prio & 0x7,
    }


def desc(
    op: int,
    base_addr: int,
    length: int,
    score: int,
    seq_id: int,
    phase: int,
    kv_kind: int,
    attn_valid: int = 0,
    attn_score: int = 0,
    recent_rank: int = 0,
    token_block_id: int = 0,
    attn_epoch: int = 0,
    head_budget_class: int = 0,
    query_relevance: int = 0,
    compression_risk: int = 0,
    spill_cost: int = 0,
    service_criticality: int = 0,
    policy_select_s5: int = 1,
    temporal_persist_class: int = 0,
    reuse_distance_class: int = 0,
    query_structure_class: int = 0,
    sched_urgency_hint: int = 0,
    sig_valid: int = 0,
    query_sig: int = 0,
    key_sig: int = 0,
    prefix_class: int = 0,
    router_class: int = 0,
) -> dict[str, int]:
    return {
        "op": op & 0x3,
        "base_addr": base_addr & 0xFF,
        "len": length & 0xFF,
        "score": score & 0xFF,
        "seq_id": seq_id & 0xFF,
        "phase": phase & 0x1,
        "kv_kind": kv_kind & 0x1,
        "attn_valid": attn_valid & 0x1,
        "attn_score": attn_score & 0xFF,
        "recent_rank": recent_rank & 0xF,
        "token_block_id": token_block_id & 0xFFFF,
        "attn_epoch": attn_epoch & 0xFF,
        "head_budget_class": head_budget_class & 0x3,
        "query_relevance": query_relevance & 0xFF,
        "compression_risk": compression_risk & 0xF,
        "spill_cost": spill_cost & 0xF,
        "service_criticality": service_criticality & 0xFF,
        "policy_select_s5": policy_select_s5 & 0x1,
        "temporal_persist_class": temporal_persist_class & 0x3,
        "reuse_distance_class": reuse_distance_class & 0x3,
        "query_structure_class": query_structure_class & 0x3,
        "sched_urgency_hint": sched_urgency_hint & 0x3,
        "sig_valid": sig_valid & 0x1,
        "query_sig": query_sig & 0x3F,
        "key_sig": key_sig & 0x3F,
        "prefix_class": prefix_class & 0x3,
        "router_class": router_class & 0x3,
    }


def class2_from_norm(value: float) -> int:
    clamped = max(0.0, min(1.0, float(value)))
    if clamped >= 0.78:
        return 3
    if clamped >= 0.56:
        return 2
    if clamped >= 0.32:
        return 1
    return 0


def descriptor_role_class(seg_type: str) -> int:
    role = str(seg_type).lower()
    if role == "doc":
        return 3
    if role in ("preamble", "question"):
        return 2
    if role in ("context", "history", "user", "assistant", "decode"):
        return 1
    return 0


def descriptor_prefix_class(seg_type: str, blk: int, segment_focus_norm: float, crossdoc_support_norm: float) -> int:
    role = str(seg_type).lower()
    if int(blk) <= 8 or role in ("preamble", "question"):
        return 3
    if role == "doc" and (segment_focus_norm >= 0.55 or crossdoc_support_norm >= 0.55):
        return 2
    if role in ("context", "history", "assistant") and segment_focus_norm >= 0.50:
        return 1
    return 0


def descriptor_router_class(seg_type: str, crossdoc_support_norm: float, segment_focus_norm: float) -> int:
    role = str(seg_type).lower()
    if role == "doc":
        return 3 if crossdoc_support_norm >= 0.50 else 2
    if role in ("preamble", "question"):
        return 2
    if role in ("context", "history", "assistant", "user", "decode"):
        return 1 if segment_focus_norm >= 0.45 else 0
    return 0


def descriptor_v2_signatures(
    *,
    dominant_seg_type: str,
    blk: int,
    query_norm: float,
    norm_weight: float,
    segment_focus_norm: float,
    segment_mass_norm: float,
    crossdoc_support_norm: float,
    recall_dependency_norm: float,
    temporal_persist_norm: float,
    temporal_evidence_norm: float,
    recentness_norm: float,
    distance_norm: float,
    head_budget_class: int,
) -> tuple[int, int, int, int, int]:
    """Build low-bit descriptor-v2 signatures from current-step runtime metadata.

    The signatures intentionally use only information already available while
    emitting the current access descriptor: attention/segment summaries, recency
    and compact head-budget bins. They do not use future hits or oracle reuse.
    """
    role = descriptor_role_class(dominant_seg_type)
    prefix = descriptor_prefix_class(dominant_seg_type, blk, segment_focus_norm, crossdoc_support_norm)
    router = descriptor_router_class(dominant_seg_type, crossdoc_support_norm, segment_focus_norm)
    query_strength = class2_from_norm(
        (query_norm * 0.46)
        + (crossdoc_support_norm * 0.18)
        + (recall_dependency_norm * 0.18)
        + (temporal_evidence_norm * 0.10)
        + ((float(head_budget_class) / 3.0) * 0.08)
    )
    query_temporal = class2_from_norm(
        (recall_dependency_norm * 0.36)
        + (temporal_persist_norm * 0.24)
        + ((1.0 - recentness_norm) * 0.22)
        + (distance_norm * 0.18)
    )
    key_strength = class2_from_norm(
        (norm_weight * 0.30)
        + (segment_focus_norm * 0.28)
        + (segment_mass_norm * 0.18)
        + ((float(head_budget_class) / 3.0) * 0.14)
        + (crossdoc_support_norm * 0.10)
    )
    key_temporal = class2_from_norm(
        (temporal_persist_norm * 0.30)
        + (recall_dependency_norm * 0.30)
        + (distance_norm * 0.20)
        + ((1.0 - recentness_norm) * 0.20)
    )
    query_sig = ((role & 0x3) << 4) | ((query_strength & 0x3) << 2) | (query_temporal & 0x3)
    key_sig = ((role & 0x3) << 4) | ((key_strength & 0x3) << 2) | (key_temporal & 0x3)
    return 1, query_sig & 0x3F, key_sig & 0x3F, prefix & 0x3, router & 0x3


def casu_block_policy_select(
    *,
    op: int,
    attn_valid: int,
    attn_score: int,
    recent_rank: int,
    head_budget_class: int,
    query_relevance: int,
    compression_risk: int,
    spill_cost: int,
    service_criticality: int,
) -> int:
    """Select blocks where CAS-U should add marginal control beyond HAQU.

    The selector is intentionally fixed-threshold and descriptor-local: it keeps
    the hardware path simple while avoiding a workload-wide "all blocks active"
    policy that pollutes L2 replacement metadata.
    """
    if op != KCMU_OP_RD or not attn_valid:
        return 0

    marginal_query_cost = (
        (query_relevance >= 0x90)
        and (spill_cost >= 4)
        and (attn_score >= 0x80)
    )
    pressure_residual = (
        (service_criticality >= 0xA8)
        and (attn_score >= 0x88)
        and (recent_rank >= 2)
    )
    compression_guard_need = (
        (compression_risk >= 7)
        and (query_relevance >= 0x88)
        and (attn_score >= 0x78)
    )

    already_strongly_covered = (
        (recent_rank <= 1)
        and (head_budget_class >= 2)
        and (attn_score >= 0xD0)
        and (service_criticality < 0xC0)
    )
    low_utility_pollution = (
        (attn_score < 0x70)
        and (query_relevance < 0x80)
        and (service_criticality < 0x98)
    )

    return int(
        (marginal_query_cost or pressure_residual or compression_guard_need)
        and not already_strongly_covered
        and not low_utility_pollution
    )


def casu_lite_block_policy_select(
    *,
    op: int,
    attn_valid: int,
    attn_score: int,
    recent_rank: int,
    head_budget_class: int,
    query_relevance: int,
    compression_risk: int,
    spill_cost: int,
    service_criticality: int,
) -> int:
    """A narrower CAS-U selector used only for candidate screening.

    The lite path intentionally avoids broad activation. It only marks blocks that
    are not already strongly protected by HAQU-like signals and that show
    simultaneous utility pressure on query relevance, spill cost, or backend
    pressure. This keeps the candidate fair against the stable HAQU path.
    """
    if op != KCMU_OP_RD or not attn_valid:
        return 0

    guarded_query_cost = (
        (query_relevance >= 0x88)
        and (spill_cost >= 5)
        and (attn_score >= 0x84)
    )
    residual_pressure = (
        (service_criticality >= 0xAC)
        and (recent_rank >= 2)
        and (attn_score >= 0x84)
    )
    guarded_compression = (
        (compression_risk >= 8)
        and (query_relevance >= 0x86)
        and (attn_score >= 0x7C)
    )

    already_covered = (
        (recent_rank <= 1)
        and (head_budget_class >= 2)
        and (attn_score >= 0xC8)
        and (query_relevance >= 0x90)
    )
    low_utility_pollution = (
        (attn_score < 0x78)
        and (query_relevance < 0x84)
        and (service_criticality < 0xA0)
        and (spill_cost < 6)
    )

    return int(
        (guarded_query_cost or residual_pressure or guarded_compression)
        and not already_covered
        and not low_utility_pollution
    )


def selector_v1_full_policy(attention_records: list[dict[str, Any]]) -> tuple[float, int]:
    total_blocks = 0
    question_blocks = 0
    for record in attention_records:
        for seq in record.get("seqs", []):
            for block in seq.get("blocks", []):
                total_blocks += 1
                if str(block.get("segment_type", "")).strip().lower() == "question":
                    question_blocks += 1
    if total_blocks <= 0:
        return 0.0, 1
    question_ratio = float(question_blocks) / float(total_blocks)
    return question_ratio, (1 if question_ratio < 0.285714 else 0)


def kspu_v220_block_key(command: dict[str, int]) -> int:
    return int(command.get("base_addr", command.get("addr", 0))) & 0x7F


def kspu_epoch_selector_v220_policy(commands: list[dict[str, int]]) -> tuple[dict[str, float], int]:
    """Workload-level selector for KSPU v220.

    This is a host/runtime descriptor contract, not a per-access oracle. It uses
    only read count, top-block mass, and short-distance locality counters, which
    can be produced from an early replay/profile pass or a CSR-programmed mode.
    """
    read_blocks = [kspu_v220_block_key(c) for c in commands if int(c.get("op", 0)) == KCMU_OP_RD]
    reads = len(read_blocks)
    if reads <= 0:
        return {
            "total_reads": 0.0,
            "top10_block_mass_pct": 0.0,
            "sliding_window_ratio_pct": 0.0,
        }, 0
    counts: dict[int, int] = {}
    local_hits = 0
    prev_block: int | None = None
    for block in read_blocks:
        counts[block] = counts.get(block, 0) + 1
        if prev_block is not None and abs(block - prev_block) <= 2:
            local_hits += 1
        prev_block = block
    top10_mass = sum(sorted(counts.values(), reverse=True)[:10]) * 100.0 / reads
    sliding = local_hits * 100.0 / reads
    enabled = reads >= 128 and 62.0 <= top10_mass <= 78.0
    return {
        "total_reads": float(reads),
        "top10_block_mass_pct": round(top10_mass, 3),
        "sliding_window_ratio_pct": round(sliding, 3),
    }, int(enabled)


def data_word(seq_id: int, layer: int, head: int, token: int, kv_kind: int) -> int:
    return (
        0xC3000000
        ^ ((seq_id & 0xFF) << 16)
        ^ ((layer & 0x7) << 13)
        ^ ((head & 0x3) << 11)
        ^ ((kv_kind & 0x1) << 10)
        ^ ((token * 0x45D9F3B) & 0x3FF)
    ) & 0xFFFFFFFF


def legacy_addr_region(
    seq_slot: int,
    seq_count: int,
    layers: int,
    heads: int,
    layer: int,
    head: int,
    token: int,
    kv_kind: int,
) -> int:
    region_size = 256 // max(seq_count, 1)
    seq_base = seq_slot * region_size
    per_token_span = max(1, layers * heads * 2)
    token_index = token // 4
    offset = (token_index * per_token_span) + (layer * heads * 2) + (head * 2) + kv_kind
    return (seq_base + (offset % region_size)) & 0xFF


def descriptor_base(seq_id: int, token_start: int, kv_kind: int) -> int:
    return ((seq_id * 41) + (kv_kind * 17) + ((token_start // 4) * 4)) & 0xFF


def token_block_id(seq_id: int, token_start: int, kv_kind: int) -> int:
    return (((seq_id & 0xFF) << 8) | ((kv_kind & 0x1) << 7) | ((token_start // 4) & 0x7F)) & 0xFFFF


def bucket_prio(weight: float) -> int:
    if weight >= 0.20:
        return 7
    if weight >= 0.12:
        return 6
    if weight >= 0.08:
        return 5
    if weight >= 0.05:
        return 4
    if weight >= 0.03:
        return 3
    if weight >= 0.02:
        return 2
    return 1


def score_from_weight(weight: float) -> int:
    scaled = int(round(max(0.0, min(1.0, weight)) * 255.0))
    return max(0x10, min(0xFF, scaled))


def cost_class_from_weight(weight: float) -> int:
    scaled = int(round(max(0.0, min(1.0, weight)) * 15.0))
    return max(0, min(15, scaled))


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def infer_prompt_segments(prompt: str, task_type: str | None = None) -> list[dict[str, int | str]]:
    task = (task_type or "").strip().lower()
    segments: list[dict[str, int | str]] = []

    def build_from_markers(markers: list[tuple[int, str]]) -> list[dict[str, int | str]]:
        items = sorted(markers, key=lambda item: item[0])
        built: list[dict[str, int | str]] = []
        if not items:
            return built
        if items[0][0] > 0:
            built.append({"id": 0, "type": "preamble", "start": 0, "end": items[0][0]})
        seg_id = len(built)
        for idx, (start, seg_type) in enumerate(items):
            end = items[idx + 1][0] if (idx + 1) < len(items) else len(prompt)
            built.append({"id": seg_id, "type": seg_type, "start": start, "end": end})
            seg_id += 1
        return built

    doc_markers = [(m.start(), "doc") for m in re.finditer(r"Document\s+[A-Z]:", prompt)]
    question_markers = [(m.start(), "question") for m in re.finditer(r"Question:", prompt)]
    turn_markers = [(m.start(), "user" if m.group(0).startswith("User") else "assistant") for m in re.finditer(r"User:|Assistant:", prompt)]

    if doc_markers:
        segments = build_from_markers(doc_markers + question_markers)
    elif turn_markers:
        segments = build_from_markers(turn_markers)
    elif question_markers:
        q_start = question_markers[0][0]
        if q_start > 0:
            segments.append({"id": 0, "type": "context", "start": 0, "end": q_start})
            segments.append({"id": 1, "type": "question", "start": q_start, "end": len(prompt)})
        else:
            segments.append({"id": 0, "type": "question", "start": 0, "end": len(prompt)})
    elif task == "conversation_memory_qa":
        segments = build_from_markers(turn_markers) if turn_markers else [{"id": 0, "type": "history", "start": 0, "end": len(prompt)}]
    else:
        segments = [{"id": 0, "type": "context", "start": 0, "end": len(prompt)}]

    if not segments:
        segments = [{"id": 0, "type": "context", "start": 0, "end": len(prompt)}]
    return segments


def build_prompt_segment_maps(tokenizer, prompts: list[str], task_type: str | None = None) -> tuple[list[list[int]], list[dict[int, str]]]:
    try:
        enc = tokenizer(prompts, padding=True, return_offsets_mapping=True)
        offset_maps = enc.get("offset_mapping")
    except Exception:
        offset_maps = None
    if not offset_maps:
        fallback_maps: list[list[int]] = []
        fallback_meta: list[dict[int, str]] = []
        for prompt in prompts:
            fallback_maps.append([0] * max(1, len(tokenizer(prompt)["input_ids"])))
            fallback_meta.append({0: "context"})
        return fallback_maps, fallback_meta

    all_maps: list[list[int]] = []
    all_meta: list[dict[int, str]] = []
    for prompt, offsets in zip(prompts, offset_maps):
        segments = infer_prompt_segments(prompt, task_type)
        seg_meta = {int(seg["id"]): str(seg["type"]) for seg in segments}
        pos_map: list[int] = []
        for start, end in offsets:
            if int(end) <= int(start):
                pos_map.append(-1)
                continue
            mid = (int(start) + int(end)) // 2
            matched = int(segments[-1]["id"])
            for seg in segments:
                if int(seg["start"]) <= mid < int(seg["end"]):
                    matched = int(seg["id"])
                    break
            pos_map.append(matched)
        all_maps.append(pos_map)
        all_meta.append(seg_meta)
    return all_maps, all_meta


def segment_role_weight(seg_type: str) -> float:
    role = seg_type.lower()
    if role == "doc":
        return 1.0
    if role in ("context", "history", "user"):
        return 0.9
    if role == "assistant":
        return 0.72
    if role == "preamble":
        return 0.55
    if role in ("question", "decode"):
        return 0.32
    return 0.65


def resolve_segment_for_position(
    pos: int,
    prompt_segment_map: list[int],
    segment_meta: dict[int, str],
    decode_segment_id: int,
) -> tuple[int, str]:
    if 0 <= int(pos) < len(prompt_segment_map):
        seg_id = int(prompt_segment_map[int(pos)])
        if seg_id >= 0:
            return seg_id, segment_meta.get(seg_id, "context")
    return decode_segment_id, segment_meta.get(decode_segment_id, "decode")


def head_budget_class_from_coverage(head_hits: int, total_observers: int) -> int:
    coverage = float(head_hits) / float(max(total_observers, 1))
    if coverage >= 0.45:
        return 3
    if coverage >= 0.25:
        return 2
    if coverage >= 0.10:
        return 1
    return 0


def block_start(token_index: int) -> int:
    return (int(token_index) // 4) * 4


def default_workload_specs(model_name: str = "sshleifer/tiny-gpt2") -> list[HFWorkloadSpec]:
    safe_for_legacy = model_name.strip().lower() in {
        "sshleifer/tiny-gpt2",
        "tiny-gpt2",
    }
    short_mode = "legacy" if safe_for_legacy else "descriptor"
    mid_mode = "legacy" if safe_for_legacy else "descriptor"
    batch4_mode = "legacy" if safe_for_legacy else "descriptor"
    long_prompt = " ".join(
        [
            "KiloWare builds a hierarchical KV-cache controller for transformer inference."
            " It prioritizes recent tokens, semantic hotness, and backend pressure."
        ]
        * 18
    )
    return [
        HFWorkloadSpec(
            name="hf_batch1_short",
            prompts=[
                "KiloWare reduces KV-cache pressure during short decode loops by prioritizing hot recent tokens."
            ],
            max_new_tokens=12,
            top_k_per_head=2,
            trace_mode=short_mode,
            prefetch_enable=1,
            description="Real HuggingFace decode trace, batch=1, short prompt.",
            tags=["runtime", "hf", "batch1", "short"],
        ),
        HFWorkloadSpec(
            name="hf_batch1_mid",
            prompts=[
                "KiloWare is designed for long-context transformer inference. "
                "The controller tries SRAM first, then the backend tier, and keeps track of hot reuse semantics. "
                "The runtime exports attention-driven traces for the hardware cache manager."
            ],
            max_new_tokens=16,
            top_k_per_head=3,
            trace_mode=mid_mode,
            prefetch_enable=1,
            description="Real HuggingFace decode trace, batch=1, medium prompt with deeper reuse.",
            tags=["runtime", "hf", "batch1", "mid", "reuse"],
        ),
        HFWorkloadSpec(
            name="hf_batch4_interleave",
            prompts=[
                "KiloWare accelerates long-context decode.",
                "Hot KV blocks should stay on-chip.",
                "Cold tails may spill or compress.",
                "Prefetch must avoid harming demand traffic.",
            ],
            max_new_tokens=10,
            top_k_per_head=2,
            trace_mode=batch4_mode,
            prefetch_enable=1,
            description="Real HuggingFace decode trace, batch=4 interleaved stream.",
            tags=["runtime", "hf", "batch4", "interleave", "pressure"],
        ),
        HFWorkloadSpec(
            name="hf_longctx_descriptor",
            prompts=[long_prompt],
            max_new_tokens=12,
            top_k_per_head=3,
            trace_mode="descriptor",
            prefetch_enable=1,
            description="Real HuggingFace long-context trace exported as descriptor reads and writes.",
            tags=["runtime", "hf", "descriptor", "long-context"],
        ),
        HFWorkloadSpec(
            name="hf_h2o_recent_mix",
            prompts=[
                "Recent tokens dominate local decode attention, but anchor tokens still occasionally matter for retrieval and reasoning."
            ],
            max_new_tokens=14,
            top_k_per_head=4,
            trace_mode="descriptor",
            prefetch_enable=1,
            description="Real HuggingFace descriptor trace emphasizing recent-window protection versus occasional anchors.",
            tags=["runtime", "hf", "true-h2o", "recent-mix"],
        ),
        HFWorkloadSpec(
            name="hf_h2o_heavy_tail",
            prompts=[long_prompt + " Heavy-hitter anchors should remain visible even after many decode steps."],
            max_new_tokens=18,
            top_k_per_head=4,
            trace_mode="descriptor",
            prefetch_enable=1,
            description="Real HuggingFace descriptor trace emphasizing long-tail heavy-hitter retention.",
            tags=["runtime", "hf", "true-h2o", "heavy-tail"],
        ),
        HFWorkloadSpec(
            name="hf_h2o_interleave",
            prompts=[
                "Sequence one prefers recent local reuse.",
                "Sequence two revisits a few old anchor tokens.",
                "Sequence three mixes recent and distant references.",
                "Sequence four stresses multi-sequence decode overlap.",
            ],
            max_new_tokens=12,
            top_k_per_head=3,
            trace_mode="descriptor",
            prefetch_enable=1,
            description="Real HuggingFace descriptor trace with batch-4 interleave and true-H2O attention metadata.",
            tags=["runtime", "hf", "true-h2o", "interleave"],
        ),
        HFWorkloadSpec(
            name="hf_h2o_descriptor_longctx",
            prompts=[long_prompt + " Descriptor-attention export should preserve recent and heavy-hitter budgets."],
            max_new_tokens=20,
            top_k_per_head=4,
            trace_mode="descriptor",
            prefetch_enable=1,
            description="Real HuggingFace descriptor long-context trace used as the primary true-H2O acceptance workload.",
            tags=["runtime", "hf", "true-h2o", "descriptor-longctx"],
        ),
    ]


def spec_from_payload(payload: dict[str, Any]) -> HFWorkloadSpec:
    prompts = [str(p) for p in payload.get("prompts", []) if str(p).strip()]
    if not prompts:
        prompts = ["KiloWare manages KV-cache traffic using attention-derived descriptors."]
    return HFWorkloadSpec(
        name=str(payload["name"]),
        prompts=prompts,
        max_new_tokens=int(payload.get("max_new_tokens", 8)),
        top_k_per_head=int(payload.get("top_k_per_head", 2)),
        trace_mode=str(payload.get("trace_mode", "legacy")),
        prefetch_enable=int(payload.get("prefetch_enable", 1)),
        description=str(payload.get("description", "Benchmark-driven HuggingFace workload.")),
        tags=[str(tag) for tag in payload.get("tags", [])],
        metadata=dict(payload.get("metadata", {})) if payload.get("metadata") else None,
    )


def load_workload_specs_from_manifest(manifest_path: Path) -> tuple[list[HFWorkloadSpec], dict[str, Any]]:
    payload = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    workloads = payload.get("workloads", [])
    if not workloads:
        raise ValueError(f"Benchmark/spec manifest has no workloads: {manifest_path}")
    specs = [spec_from_payload(item) for item in workloads]
    meta = {
        "schema": payload.get("schema", "kiloware_external_workload_manifest_v1"),
        "benchmark": payload.get("benchmark"),
        "description": payload.get("description"),
        "source_manifest": str(manifest_path),
    }
    if "model" in payload:
        meta["recommended_model"] = payload["model"]
    return specs, meta


def resolve_local_model_name(model_name: str) -> tuple[str, bool]:
    model_path = Path(model_name)
    if model_path.exists():
        return str(model_path), True

    project_root = Path(__file__).resolve().parents[2]
    registry_path = project_root / "software" / "model_registry" / "hf_generalization_models.json"
    if not registry_path.exists():
        return model_name, False

    try:
        registry = json.loads(registry_path.read_text(encoding="utf-8"))
    except Exception:
        return model_name, False

    for item in registry.get("models", []):
        if item.get("status") != "PASS":
            continue
        alias = str(item.get("alias", ""))
        repo_id = str(item.get("repo_id", ""))
        aliases = {alias, repo_id}
        if model_name in aliases:
            env_key = "KILOWARE_HF_MODEL_" + re.sub(r"[^A-Za-z0-9]+", "_", alias).upper().strip("_")
            explicit_dir = os.environ.get(env_key, "").strip()
            if explicit_dir:
                explicit_path = Path(explicit_dir).expanduser()
                if explicit_path.exists():
                    return str(explicit_path), True

            model_root = os.environ.get("KILOWARE_HF_MODEL_ROOT", "").strip()
            if model_root:
                root = Path(model_root).expanduser()
                root_candidates = [
                    root / alias,
                    root / repo_id.replace("/", "__"),
                    root / repo_id.split("/")[-1],
                ]
                for candidate in root_candidates:
                    if candidate.exists():
                        return str(candidate), True

            local_dir = Path(str(item.get("local_dir", "")))
            if local_dir.exists():
                return str(local_dir), True
            if repo_id:
                return repo_id, False
    return model_name, False


def set_model_attention_implementation(model, implementation: str) -> None:
    if hasattr(model, "set_attn_implementation"):
        try:
            model.set_attn_implementation(implementation)
        except Exception:
            pass
    for obj in (model, getattr(model, "model", None)):
        cfg = getattr(obj, "config", None)
        if cfg is None:
            continue
        if hasattr(cfg, "_attn_implementation"):
            setattr(cfg, "_attn_implementation", implementation)
        if hasattr(cfg, "attn_implementation"):
            setattr(cfg, "attn_implementation", implementation)


def load_model_bundle(
    model_name: str,
    torch_threads: int = 1,
    device: str = "cpu",
    attention_capture: str = "prefill_and_decode",
):
    if device == "auto":
        device = "cuda" if torch.cuda.is_available() else "cpu"
    if device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("Requested --device cuda, but torch.cuda.is_available() is false.")
    torch.set_num_threads(max(1, int(torch_threads)))
    resolved_model, local_only = resolve_local_model_name(model_name)
    attn_impl = "sdpa" if attention_capture == "decode_only" else "eager"
    print(
        "HF_TRACEGEN_MODEL_RESOLVED "
        f"name={model_name} resolved={resolved_model} local_only={local_only} "
        f"device={device} attention_capture={attention_capture} attn_implementation={attn_impl}",
        flush=True,
    )
    tokenizer = AutoTokenizer.from_pretrained(
        resolved_model,
        local_files_only=local_only,
        trust_remote_code=True,
    )
    model = AutoModelForCausalLM.from_pretrained(
        resolved_model,
        attn_implementation=attn_impl,
        torch_dtype="auto",
        local_files_only=local_only,
        trust_remote_code=True,
    )
    model.to(device)
    model.eval()
    if hasattr(model.config, "output_attentions"):
        model.config.output_attentions = attention_capture == "prefill_and_decode"
    if tokenizer.pad_token_id is None:
        tokenizer.pad_token = tokenizer.eos_token
    return model, tokenizer, device


def run_decode(
    model,
    tokenizer,
    device: str,
    spec: HFWorkloadSpec,
    query_summary_profile: str = "stable",
    service_criticality_profile: str = "current",
    attention_capture: str = "prefill_and_decode",
    dump_query_usefulness: bool = False,
    query_usefulness_dump: list[dict[str, float | int | str]] | None = None,
) -> tuple[list[dict[str, int]], list[int], dict[str, Any], dict[str, Any]]:
    if attention_capture not in {"prefill_and_decode", "decode_only"}:
        raise ValueError(f"Unsupported attention_capture mode: {attention_capture}")
    if attention_capture == "decode_only":
        set_model_attention_implementation(model, "sdpa")
        if hasattr(model.config, "output_attentions"):
            model.config.output_attentions = False
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        print(
            "HF_TRACEGEN_ATTENTION_SWITCH phase=prefill attn_implementation=sdpa output_attentions=False",
            flush=True,
        )
    enc = tokenizer(spec.prompts, return_tensors="pt", padding=True)
    input_ids = enc["input_ids"].to(device)
    attention_mask = enc["attention_mask"].to(device)
    batch_size = int(input_ids.shape[0])
    n_layers = int(getattr(model.config, "n_layer", getattr(model.config, "num_hidden_layers", 1)))
    n_heads = int(getattr(model.config, "n_head", getattr(model.config, "num_attention_heads", 1)))
    n_layers = min(n_layers, 8)
    n_heads = min(n_heads, 4)
    total_observers = max(1, n_layers * n_heads)

    commands: list[dict[str, int]] = []
    payload_words: list[int] = []
    if dump_query_usefulness and query_usefulness_dump is None:
        query_usefulness_dump = []
    seq_prompt_lens = [int(attention_mask[seq_slot].sum().item()) for seq_slot in range(batch_size)]
    task_type = str((spec.metadata or {}).get("task_type", "")).strip() or None
    prompt_segment_maps, prompt_segment_meta = build_prompt_segment_maps(
        tokenizer,
        spec.prompts,
        task_type=task_type,
    )
    decode_segment_ids: list[int] = []
    for seg_meta in prompt_segment_meta:
        decode_seg_id = (max(seg_meta.keys()) + 1) if seg_meta else 0
        seg_meta[decode_seg_id] = "decode"
        decode_segment_ids.append(decode_seg_id)

    # Prefill writes
    for seq_slot in range(batch_size):
        seq_id = seq_slot + 1
        seq_len = seq_prompt_lens[seq_slot]
        if spec.trace_mode == "descriptor":
            for tok in range(0, seq_len, 4):
                for kv_kind in (KV_KIND_K, KV_KIND_V):
                    commands.append(
                        desc(
                            KCMU_OP_WR,
                            descriptor_base(seq_id, tok, kv_kind),
                            4,
                            0x40,
                            seq_id=seq_id,
                            phase=PHASE_PREFILL,
                            kv_kind=kv_kind,
                            attn_valid=0,
                            attn_score=0,
                            recent_rank=0,
                            token_block_id=token_block_id(seq_id, tok, kv_kind),
                            attn_epoch=0,
                            head_budget_class=0,
                            query_relevance=0,
                            compression_risk=0,
                            spill_cost=0,
                        )
                    )
                    for beat in range(4):
                        payload_words.append(data_word(seq_id, 0, 0, tok + beat, kv_kind))
        else:
            for tok in range(0, seq_len, 4):
                for layer in range(n_layers):
                    for head in range(n_heads):
                        for kv_kind in (KV_KIND_K, KV_KIND_V):
                            commands.append(
                                cmd(
                                    KCMU_OP_WR,
                                    legacy_addr_region(seq_slot, batch_size, n_layers, n_heads, layer, head, tok, kv_kind),
                                    data_word(seq_id, layer, head, tok, kv_kind),
                                    seq_id,
                                    PHASE_PREFILL,
                                    kv_kind,
                                    layer,
                                    head,
                                    tok,
                                    2,
                                )
                            )

    generated: list[list[int]] = [[] for _ in range(batch_size)]
    attention_records: list[dict[str, Any]] = []
    query_history: list[dict[tuple[int, int], dict[str, float | int]]] = [{} for _ in range(batch_size)]

    with torch.no_grad():
        outputs = model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            use_cache=True,
            output_attentions=(attention_capture == "prefill_and_decode"),
            return_dict=True,
        )

    past = outputs.past_key_values
    cur_mask = attention_mask

    if attention_capture == "decode_only":
        set_model_attention_implementation(model, "eager")
        if hasattr(model.config, "output_attentions"):
            model.config.output_attentions = True
        print(
            "HF_TRACEGEN_ATTENTION_SWITCH phase=decode attn_implementation=eager output_attentions=True",
            flush=True,
        )

    def append_decode_time_writes(write_step: int) -> None:
        # Keep the existing stream shape: descriptor KV growth is emitted once
        # per 4 generated tokens, while legacy mode emits per observer.
        for seq_slot in range(batch_size):
            seq_id = seq_slot + 1
            tok = block_start(int(cur_mask[seq_slot].sum().item()) - 1)
            if spec.trace_mode == "descriptor":
                if (write_step % 4) == 3:
                    for kv_kind in (KV_KIND_K, KV_KIND_V):
                        commands.append(
                            desc(
                                KCMU_OP_WR,
                                descriptor_base(seq_id, tok, kv_kind),
                                4,
                                0x30,
                                seq_id=seq_id,
                                phase=PHASE_PREFILL,
                                kv_kind=kv_kind,
                                attn_valid=0,
                                attn_score=0,
                                recent_rank=0,
                                token_block_id=token_block_id(seq_id, tok, kv_kind),
                                attn_epoch=0,
                                head_budget_class=0,
                                query_relevance=0,
                                compression_risk=0,
                                spill_cost=0,
                                service_criticality=0,
                            )
                        )
                        for beat in range(4):
                            payload_words.append(data_word(seq_id, 0, 0, tok + beat, kv_kind))
            else:
                for layer in range(n_layers):
                    for head in range(n_heads):
                        for kv_kind in (KV_KIND_K, KV_KIND_V):
                            commands.append(
                                cmd(
                                    KCMU_OP_WR,
                                    legacy_addr_region(seq_slot, batch_size, n_layers, n_heads, layer, head, tok, kv_kind),
                                    data_word(seq_id, layer, head, tok, kv_kind),
                                    seq_id,
                                    PHASE_PREFILL,
                                    kv_kind,
                                    layer,
                                    head,
                                    tok,
                                    2,
                                )
                            )

    if attention_capture == "decode_only" and spec.max_new_tokens > 0:
        logits = outputs.logits[:, -1, :]
        next_ids = torch.argmax(logits, dim=-1, keepdim=True)
        next_mask = torch.ones_like(next_ids, device=device)
        for seq_slot in range(batch_size):
            generated[seq_slot].append(int(next_ids[seq_slot, 0].item()))
        with torch.no_grad():
            outputs = model(
                input_ids=next_ids,
                attention_mask=torch.cat([cur_mask, next_mask], dim=1),
                past_key_values=past,
                use_cache=True,
                output_attentions=True,
                return_dict=True,
            )
        past = outputs.past_key_values
        cur_mask = torch.cat([cur_mask, next_mask], dim=1)
        append_decode_time_writes(0)

    for step in range(spec.max_new_tokens):
        attns = outputs.attentions
        if not attns:
            raise RuntimeError(
                f"HuggingFace model '{type(model).__name__}' did not return attentions at decode step {step}. "
                "Trace export requires attentions to derive descriptor score and runtime prio."
            )
        step_record: dict[str, Any] = {"step": step, "seqs": []}
        for seq_slot in range(batch_size):
            seq_id = seq_slot + 1
            seq_total_len = int(cur_mask[seq_slot].sum().item())
            seq_entry = {"seq_id": seq_id, "blocks": []}
            if spec.trace_mode == "descriptor":
                seq_history_prev = query_history[seq_slot]
                seq_history_next: dict[tuple[int, int], dict[str, float | int]] = {}
                block_scores: dict[tuple[int, int], float] = {}
                block_peaks: dict[tuple[int, int], float] = {}
                block_head_hits: dict[tuple[int, int], int] = {}
                block_query_scores: dict[tuple[int, int], float] = {}
                block_segment_scores: dict[tuple[int, int, int], float] = {}
                segment_scores: dict[int, float] = {}
                segment_head_hits: dict[int, int] = {}
                segment_types: dict[int, str] = {}
                seq_segment_map = prompt_segment_maps[seq_slot] if seq_slot < len(prompt_segment_maps) else []
                seq_segment_meta = prompt_segment_meta[seq_slot] if seq_slot < len(prompt_segment_meta) else {}
                decode_segment_id = decode_segment_ids[seq_slot] if seq_slot < len(decode_segment_ids) else 0
                for layer_idx, attn in enumerate(attns[:n_layers]):
                    seq_attn = attn[seq_slot]
                    for head_idx in range(min(int(seq_attn.shape[0]), n_heads)):
                        vec = seq_attn[head_idx, -1, :seq_total_len]
                        top_k = min(spec.top_k_per_head, int(vec.shape[0]))
                        if top_k <= 0:
                            continue
                        vals, idxs = torch.topk(vec, k=top_k)
                        observer_block_sums: dict[int, float] = {}
                        observer_block_peaks: dict[int, float] = {}
                        observer_block_segment_sums: dict[tuple[int, int], float] = {}
                        observer_segment_sums: dict[int, float] = {}
                        for pos, weight in zip(idxs.tolist(), vals.tolist()):
                            blk = block_start(int(pos))
                            weight_f = float(weight)
                            seg_id, seg_type = resolve_segment_for_position(
                                int(pos),
                                seq_segment_map,
                                seq_segment_meta,
                                decode_segment_id,
                            )
                            segment_types[seg_id] = seg_type
                            observer_block_sums[blk] = observer_block_sums.get(blk, 0.0) + weight_f
                            observer_block_peaks[blk] = max(observer_block_peaks.get(blk, 0.0), weight_f)
                            observer_block_segment_sums[(blk, seg_id)] = observer_block_segment_sums.get((blk, seg_id), 0.0) + weight_f
                            observer_segment_sums[seg_id] = observer_segment_sums.get(seg_id, 0.0) + weight_f
                        for seg_id, seg_weight in observer_segment_sums.items():
                            segment_scores[seg_id] = segment_scores.get(seg_id, 0.0) + seg_weight
                            segment_head_hits[seg_id] = segment_head_hits.get(seg_id, 0) + 1
                        for (blk, seg_id), seg_weight in observer_block_segment_sums.items():
                            for kv_kind in (KV_KIND_K, KV_KIND_V):
                                block_segment_scores[(blk, kv_kind, seg_id)] = (
                                    block_segment_scores.get((blk, kv_kind, seg_id), 0.0) + seg_weight
                                )
                        for blk, observer_weight in observer_block_sums.items():
                            observer_peak = observer_block_peaks[blk]
                            for kv_kind in (KV_KIND_K, KV_KIND_V):
                                key = (blk, kv_kind)
                                block_scores[key] = block_scores.get(key, 0.0) + observer_weight
                                block_peaks[key] = max(block_peaks.get(key, 0.0), observer_peak)
                                block_head_hits[key] = block_head_hits.get(key, 0) + 1
                                block_query_scores[key] = (
                                    block_query_scores.get(key, 0.0)
                                    + (observer_weight * 0.70)
                                    + (observer_peak * 0.30)
                                )
                ranked = sorted(block_scores.items(), key=lambda item: (-item[1], item[0][0], item[0][1]))
                top_weight = ranked[0][1] if ranked else 0.0
                top_peak = max(block_peaks.values()) if block_peaks else 0.0
                top_query_weight = max(block_query_scores.values()) if block_query_scores else 0.0
                top_segment_weight = max(segment_scores.values()) if segment_scores else 0.0
                active_doc_segments = {
                    seg_id: seg_weight
                    for seg_id, seg_weight in segment_scores.items()
                    if segment_types.get(seg_id, "") == "doc"
                }
                top_doc_segment_weight = max(active_doc_segments.values()) if active_doc_segments else 0.0
                doc_support_threshold = top_doc_segment_weight * 0.25 if top_doc_segment_weight > 0.0 else 0.0
                doc_segment_count = (
                    sum(1 for seg_weight in active_doc_segments.values() if seg_weight >= doc_support_threshold)
                    if doc_support_threshold > 0.0
                    else 0
                )
                for recent_idx, ((blk, kv_kind), weight) in enumerate(ranked[: min(12, len(ranked))]):
                    norm_weight = clamp01((weight / top_weight) if top_weight > 0.0 else 0.0)
                    attn_score = score_from_weight(norm_weight)
                    peak_norm = clamp01((block_peaks.get((blk, kv_kind), 0.0) / top_peak) if top_peak > 0.0 else norm_weight)
                    coverage_norm = clamp01(float(block_head_hits.get((blk, kv_kind), 0)) / float(total_observers))
                    recentness_norm = clamp01(1.0 - (float(recent_idx) / 11.0))
                    distance_norm = clamp01(1.0 - (float(blk) / max(1.0, float(max(seq_total_len - 4, 1)))))
                    next_weight = ranked[recent_idx + 1][1] if (recent_idx + 1) < len(ranked) else 0.0
                    separation_norm = clamp01(((weight - next_weight) / top_weight) if top_weight > 0.0 else 0.0)
                    # Specificity rewards blocks that attract sharp per-query focus from a subset
                    # of heads, instead of simply mirroring globally popular attention mass.
                    specificity_norm = clamp01(1.0 - coverage_norm)
                    # Focus captures whether the current query sharply concentrates on a block.
                    # Peak response and separation dominate here, while specificity keeps the
                    # signal from collapsing into plain attn_score.
                    query_mass_norm = clamp01(
                        (block_query_scores.get((blk, kv_kind), 0.0) / top_query_weight)
                        if top_query_weight > 0.0
                        else norm_weight
                    )
                    candidate_segments = [
                        (seg_id, seg_weight)
                        for (seg_blk, seg_kv_kind, seg_id), seg_weight in block_segment_scores.items()
                        if seg_blk == blk and seg_kv_kind == kv_kind
                    ]
                    if candidate_segments:
                        dominant_seg_id, dominant_seg_weight = max(candidate_segments, key=lambda item: item[1])
                    else:
                        dominant_seg_id, dominant_seg_weight = decode_segment_id, 0.0
                    dominant_seg_type = segment_types.get(dominant_seg_id, seq_segment_meta.get(dominant_seg_id, "decode"))
                    dominant_seg_total = segment_scores.get(dominant_seg_id, dominant_seg_weight)
                    segment_mass_norm = clamp01((dominant_seg_total / top_segment_weight) if top_segment_weight > 0.0 else 0.0)
                    segment_focus_norm = clamp01((dominant_seg_weight / dominant_seg_total) if dominant_seg_total > 0.0 else 0.0)
                    segment_role_norm = clamp01(segment_role_weight(dominant_seg_type))
                    segment_coverage_norm = clamp01(float(segment_head_hits.get(dominant_seg_id, 0)) / float(total_observers))
                    doc_diversity_norm = clamp01(float(max(doc_segment_count - 1, 0)) / 2.0)
                    if dominant_seg_type == "doc" and top_doc_segment_weight > 0.0:
                        doc_mass_norm = clamp01(dominant_seg_total / top_doc_segment_weight)
                        crossdoc_support_norm = clamp01(
                            (doc_mass_norm * 0.50)
                            + (segment_focus_norm * 0.25)
                            + (doc_diversity_norm * 0.25)
                        )
                    else:
                        doc_mass_norm = 0.0
                        crossdoc_support_norm = clamp01(
                            (segment_mass_norm * 0.40)
                            + (segment_focus_norm * 0.30)
                            + (segment_role_norm * 0.20)
                            + (segment_coverage_norm * 0.10)
                        )
                    recall_dependency_norm = clamp01(
                        (distance_norm * 0.30)
                        + (segment_role_norm * 0.22)
                        + (segment_focus_norm * 0.20)
                        + (segment_mass_norm * 0.14)
                        + ((1.0 - recentness_norm) * 0.14)
                    )
                    if dominant_seg_type in ("question", "decode"):
                        segment_penalty = 0.12
                    elif dominant_seg_type == "assistant":
                        segment_penalty = 0.05
                    else:
                        segment_penalty = 0.0
                    head_budget_class = head_budget_class_from_coverage(block_head_hits.get((blk, kv_kind), 0), total_observers)
                    head_budget_norm = float(head_budget_class) / 3.0
                    focus_norm = clamp01(
                        (peak_norm * 0.45)
                        + (separation_norm * 0.35)
                        + (specificity_norm * 0.20)
                    )
                    consensus_norm = clamp01(
                        (coverage_norm * 0.42)
                        + (query_mass_norm * 0.28)
                        + (peak_norm * 0.18)
                        + (separation_norm * 0.12)
                    )
                    recall_guard_norm = clamp01(
                        (distance_norm * 0.35)
                        + (specificity_norm * 0.25)
                        + ((1.0 - recentness_norm) * 0.15)
                        + (query_mass_norm * 0.25)
                    )
                    evidence_role_norm = clamp01(
                        (query_mass_norm * 0.30)
                        + (focus_norm * 0.24)
                        + (separation_norm * 0.18)
                        + (specificity_norm * 0.16)
                        + (coverage_norm * 0.12)
                    )
                    recall_risk_norm = clamp01(
                        (distance_norm * 0.28)
                        + (query_mass_norm * 0.22)
                        + (head_budget_norm * 0.18)
                        + (specificity_norm * 0.16)
                        + ((1.0 - recentness_norm) * 0.16)
                    )
                    anchor_rel_norm = clamp01(
                        (peak_norm * 0.26)
                        + (coverage_norm * 0.24)
                        + (separation_norm * 0.18)
                        + (query_mass_norm * 0.18)
                        + (focus_norm * 0.14)
                    )
                    history_key = (blk, kv_kind)
                    prev_hist = seq_history_prev.get(history_key, {})
                    prev_ema = float(prev_hist.get("ema_query", 0.0))
                    prev_consensus = float(prev_hist.get("ema_consensus", 0.0))
                    prev_evidence = float(prev_hist.get("ema_evidence", 0.0))
                    prev_recall = float(prev_hist.get("ema_recall", 0.0))
                    last_seen_step = int(prev_hist.get("last_seen_step", -99))
                    prev_streak = int(prev_hist.get("streak", 0))
                    if last_seen_step == (step - 1):
                        continuity_norm = 1.0
                        streak = min(prev_streak + 1, 4)
                    elif last_seen_step == (step - 2):
                        continuity_norm = 0.55
                        streak = 1
                    else:
                        continuity_norm = 0.0
                        streak = 1
                    streak_norm = clamp01(float(streak) / 4.0)
                    temporal_persist_norm = clamp01(
                        (prev_ema * 0.48)
                        + (prev_consensus * 0.18)
                        + (prev_evidence * 0.12)
                        + (continuity_norm * 0.12)
                        + (streak_norm * 0.10)
                    )
                    temporal_evidence_norm = clamp01(
                        (prev_evidence * 0.30)
                        + (prev_consensus * 0.22)
                        + (prev_recall * 0.18)
                        + (continuity_norm * 0.16)
                        + (streak_norm * 0.14)
                    )
                    stable_query_core = clamp01(
                        (query_mass_norm * 0.26)
                        + (focus_norm * 0.24)
                        + (coverage_norm * 0.18)
                        + (recentness_norm * 0.16)
                        + (distance_norm * 0.16)
                    )
                    utility_query_base = clamp01(
                        (evidence_role_norm * 0.18)
                        + (recall_risk_norm * 0.16)
                        + (crossdoc_support_norm * 0.14)
                        + (temporal_persist_norm * 0.12)
                        + (segment_focus_norm * 0.12)
                        + (segment_mass_norm * 0.10)
                        + (segment_role_norm * 0.08)
                        + (specificity_norm * 0.06)
                        + (query_mass_norm * 0.04)
                    )
                    stable_query_blend = clamp01(
                        (crossdoc_support_norm * 0.30)
                        + (recall_dependency_norm * 0.22)
                        + (temporal_persist_norm * 0.18)
                        + (segment_focus_norm * 0.14)
                        + (specificity_norm * 0.08)
                        + (segment_role_norm * 0.08)
                    )
                    # The stable path keeps a broad coverage lane, but now exposes an
                    # explicit utility residual lane so query relevance is not dominated
                    # by attention/recentness alone.
                    utility_residual_base = clamp01(
                        (recall_dependency_norm * 0.24)
                        + (crossdoc_support_norm * 0.20)
                        + (temporal_evidence_norm * 0.16)
                        + (temporal_persist_norm * 0.12)
                        + (segment_role_norm * 0.10)
                        + (segment_focus_norm * 0.08)
                        + (specificity_norm * 0.06)
                        + (separation_norm * 0.04)
                        + (head_budget_norm * 0.04)
                        - (query_mass_norm * 0.06)
                        - (recentness_norm * 0.06)
                        - (distance_norm * 0.04)
                        + 0.08
                    )
                    residual_gate = clamp01(
                        (recall_dependency_norm * 0.26)
                        + (crossdoc_support_norm * 0.22)
                        + (temporal_evidence_norm * 0.18)
                        + (segment_role_norm * 0.12)
                        + (specificity_norm * 0.12)
                        + (separation_norm * 0.10)
                    )
                    stable_query_residual = clamp01(
                        (utility_residual_base * (0.48 + (residual_gate * 0.28)))
                        + (utility_query_base * (0.08 + (residual_gate * 0.06)))
                    )
                    stable_core_weight = clamp01(0.78 - (residual_gate * 0.28))
                    stable_residual_weight = clamp01(1.0 - stable_core_weight)
                    stable_query_base = clamp01(
                        (stable_query_core * stable_core_weight)
                        + (stable_query_residual * stable_residual_weight)
                    )
                    utility_confidence_norm = clamp01(
                        (evidence_role_norm * 0.24)
                        + (recall_risk_norm * 0.22)
                        + (crossdoc_support_norm * 0.14)
                        + (temporal_evidence_norm * 0.12)
                        + (temporal_persist_norm * 0.10)
                        + (head_budget_norm * 0.08)
                        + (specificity_norm * 0.06)
                        + (separation_norm * 0.04)
                    )
                    backend_pressure_proxy = clamp01(
                        (distance_norm * 0.34)
                        + ((1.0 - recentness_norm) * 0.22)
                        + (head_budget_norm * 0.16)
                        + (norm_weight * 0.14)
                        + (query_mass_norm * 0.08)
                        + (0.06 if kv_kind == KV_KIND_V else 0.0)
                    )
                    service_criticality_base = clamp01(
                        (recall_dependency_norm * 0.22)
                        + (recall_risk_norm * 0.18)
                        + (temporal_evidence_norm * 0.16)
                        + (temporal_persist_norm * 0.12)
                        + (evidence_role_norm * 0.10)
                        + (head_budget_norm * 0.08)
                        + (backend_pressure_proxy * 0.08)
                        + (crossdoc_support_norm * 0.04)
                        + (continuity_norm * 0.02)
                    )
                    service_criticality_current_norm = clamp01((service_criticality_base - 0.05) / 0.88)
                    service_base_v2 = clamp01(
                        (
                            clamp01(
                                (distance_norm * 0.42)
                                + ((1.0 - recentness_norm) * 0.24)
                                + (backend_pressure_proxy * 0.20)
                                + (utility_confidence_norm * 0.14)
                            )
                            * 0.34
                        )
                        + (
                            clamp01(
                                (recall_dependency_norm * 0.34)
                                + (recall_risk_norm * 0.24)
                                + (temporal_evidence_norm * 0.18)
                                + (temporal_persist_norm * 0.12)
                                + (evidence_role_norm * 0.12)
                            )
                            * 0.30
                        )
                        + (
                            clamp01(
                                (backend_pressure_proxy * 0.42)
                                + (head_budget_norm * 0.18)
                                + (crossdoc_support_norm * 0.14)
                                + (continuity_norm * 0.14)
                                + (temporal_persist_norm * 0.06)
                                + (0.06 if kv_kind == KV_KIND_V else 0.0)
                            )
                            * 0.20
                        )
                        + (temporal_evidence_norm * 0.16)
                    )
                    service_residual_v2 = max(0.0, service_base_v2 - max(norm_weight, stable_query_base))
                    service_scheduler_overlap_v3 = clamp01(
                        (norm_weight * 0.44)
                        + (stable_query_base * 0.28)
                        + (recentness_norm * 0.16)
                        + (coverage_norm * 0.08)
                        + (stable_query_core * 0.04)
                    )
                    service_scheduler_cold_hint_v3 = clamp01(
                        (distance_norm * 0.28)
                        + ((1.0 - recentness_norm) * 0.24)
                        + (backend_pressure_proxy * 0.18)
                        + (crossdoc_support_norm * 0.12)
                        + (recall_dependency_norm * 0.10)
                        + (recall_risk_norm * 0.04)
                        + (0.04 if kv_kind == KV_KIND_V else 0.0)
                    )
                    service_rescue_gap_v3 = max(
                        0.0,
                        service_scheduler_cold_hint_v3 - (service_scheduler_overlap_v3 * 0.72),
                    )
                    service_issue_overlap_v4 = 0.0
                    service_issue_window_v4 = 0.0
                    if service_criticality_profile == "v2_hard":
                        service_criticality_norm = clamp01(
                            (service_base_v2 * 0.72)
                            + (service_residual_v2 * 0.28)
                        )
                    elif service_criticality_profile == "v2_soft":
                        redundancy_norm = max(norm_weight, stable_query_base)
                        residual_margin = max(0.0, service_base_v2 - (redundancy_norm * 0.82))
                        overheat_penalty = max(0.0, redundancy_norm - 0.92)
                        service_soft_base = clamp01(
                            (service_criticality_current_norm * 0.78)
                            + (residual_margin * 0.28)
                            + (
                                clamp01(
                                    (backend_pressure_proxy * 0.42)
                                    + (head_budget_norm * 0.18)
                                    + (crossdoc_support_norm * 0.14)
                                    + (continuity_norm * 0.14)
                                    + (temporal_persist_norm * 0.06)
                                    + (0.06 if kv_kind == KV_KIND_V else 0.0)
                                )
                                * 0.08
                            )
                            - (overheat_penalty * 0.10)
                        )
                        service_criticality_norm = clamp01((service_soft_base - 0.02) / 0.92)
                    elif service_criticality_profile == "v3_rescue_soft":
                        redundancy_norm = max(norm_weight, stable_query_base)
                        residual_margin = max(0.0, service_base_v2 - (redundancy_norm * 0.84))
                        overheat_penalty = max(0.0, redundancy_norm - 0.94)
                        service_v3_base = clamp01(
                            (service_criticality_current_norm * 0.80)
                            + (residual_margin * 0.22)
                            + (service_scheduler_cold_hint_v3 * 0.06)
                            + (service_rescue_gap_v3 * 0.10)
                            + (
                                clamp01(
                                    (backend_pressure_proxy * 0.42)
                                    + (head_budget_norm * 0.18)
                                    + (crossdoc_support_norm * 0.14)
                                    + (continuity_norm * 0.14)
                                    + (temporal_persist_norm * 0.06)
                                    + (0.06 if kv_kind == KV_KIND_V else 0.0)
                                )
                                * 0.06
                            )
                            - (overheat_penalty * 0.06)
                        )
                        service_criticality_norm = clamp01((service_v3_base - 0.02) / 0.92)
                    elif service_criticality_profile == "v4_issue_soft":
                        redundancy_norm = max(norm_weight, stable_query_base)
                        residual_margin = max(0.0, service_base_v2 - (redundancy_norm * 0.80))
                        overheat_penalty = max(0.0, redundancy_norm - 0.96)
                        service_issue_overlap_v4 = clamp01(
                            (service_scheduler_overlap_v3 * 0.52)
                            + (backend_pressure_proxy * 0.24)
                            + (head_budget_norm * 0.14)
                            + (continuity_norm * 0.10)
                        )
                        service_issue_window_v4 = clamp01(
                            (service_rescue_gap_v3 * 0.36)
                            + (distance_norm * 0.22)
                            + ((1.0 - recentness_norm) * 0.18)
                            + (backend_pressure_proxy * 0.14)
                            + (crossdoc_support_norm * 0.10)
                        )
                        service_v4_base = clamp01(
                            (service_criticality_current_norm * 0.72)
                            + (residual_margin * 0.16)
                            + (service_issue_overlap_v4 * 0.10)
                            + (service_issue_window_v4 * 0.12)
                            + (
                                clamp01(
                                    (backend_pressure_proxy * 0.42)
                                    + (head_budget_norm * 0.18)
                                    + (crossdoc_support_norm * 0.14)
                                    + (continuity_norm * 0.14)
                                    + (temporal_persist_norm * 0.06)
                                    + (0.06 if kv_kind == KV_KIND_V else 0.0)
                                )
                                * 0.08
                            )
                            - (overheat_penalty * 0.04)
                        )
                        service_criticality_norm = clamp01((service_v4_base - 0.01) / 0.90)
                    else:
                        service_criticality_norm = service_criticality_current_norm
                    stable_reuse_pressure_norm = clamp01(
                        (coverage_norm * 0.40)
                        + (recentness_norm * 0.35)
                        + (norm_weight * 0.25)
                    )
                    stable_compression_core = clamp01(
                        (peak_norm * 0.32)
                        + (head_budget_norm * 0.18)
                        + (specificity_norm * 0.16)
                        + ((1.0 - recentness_norm) * 0.14)
                        + (stable_query_base * 0.10)
                        + (0.10 if kv_kind == KV_KIND_V else 0.0)
                    )
                    stable_compression_base = clamp01(stable_compression_core)
                    stable_spill_core = clamp01(
                        (distance_norm * 0.34)
                        + (stable_reuse_pressure_norm * 0.36)
                        + (head_budget_norm * 0.10)
                        + (stable_query_base * 0.10)
                        + (recall_dependency_norm * 0.10)
                    )
                    stable_spill_base = clamp01(stable_spill_core)
                    # Keep query relevance moderately query-specific without turning it into an
                    # overly sparse anchor detector. The stable path mixes query mass with
                    # coverage/recentness so the signal remains useful across all three QA suites.
                    candidate_utility_base = 0.0
                    candidate_actionability = 0.0
                    candidate_pressure_residual = 0.0
                    hybrid_temporal_selectivity_norm = 0.0
                    hybrid_structural_selectivity_norm = 0.0
                    hybrid_selectivity_norm = 0.0
                    hybrid_penalty_norm = 0.0
                    if query_summary_profile == "haqu_s4_tuned":
                        tuned_temporal_focus = clamp01(
                            (stable_query_base * 0.58)
                            + (temporal_persist_norm * 0.10)
                            + (temporal_evidence_norm * 0.08)
                            + (recall_dependency_norm * 0.10)
                            + (evidence_role_norm * 0.08)
                            + (crossdoc_support_norm * 0.04)
                            + (focus_norm * 0.02)
                        )
                        query_base = clamp01(tuned_temporal_focus - (segment_penalty * 0.10))
                        query_norm = clamp01((query_base - 0.05) / 0.86)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.72)
                            + (temporal_persist_norm * 0.12)
                            + (recall_dependency_norm * 0.10)
                            + (backend_pressure_proxy * 0.06)
                        )
                    elif query_summary_profile == "v2_consensus":
                        query_base = clamp01(
                            (consensus_norm * 0.44)
                            + (focus_norm * 0.22)
                            + (recall_guard_norm * 0.20)
                            + (recentness_norm * 0.08)
                            + (distance_norm * 0.06)
                        )
                        query_norm = clamp01((query_base - 0.05) / 0.87)
                    elif query_summary_profile == "v2_usefulness":
                        query_base = clamp01(
                            (anchor_rel_norm * 0.22)
                            + (evidence_role_norm * 0.40)
                            + (recall_risk_norm * 0.24)
                            + (coverage_norm * 0.08)
                            + (recentness_norm * 0.06)
                        )
                        query_norm = clamp01((query_base - 0.04) / 0.90)
                    elif query_summary_profile == "v3_temporal":
                        query_base = clamp01(
                            (query_mass_norm * 0.18)
                            + (focus_norm * 0.16)
                            + (coverage_norm * 0.10)
                            + (recentness_norm * 0.08)
                            + (distance_norm * 0.06)
                            + (evidence_role_norm * 0.16)
                            + (recall_risk_norm * 0.12)
                            + (temporal_persist_norm * 0.14)
                        )
                        query_norm = clamp01((query_base - 0.05) / 0.88)
                    elif query_summary_profile == "v4_evidence_temporal":
                        query_base = clamp01(
                            (evidence_role_norm * 0.22)
                            + (temporal_evidence_norm * 0.18)
                            + (recall_risk_norm * 0.16)
                            + (consensus_norm * 0.14)
                            + (focus_norm * 0.10)
                            + (query_mass_norm * 0.08)
                            + (specificity_norm * 0.06)
                            + (separation_norm * 0.06)
                        )
                        query_norm = clamp01((query_base - 0.05) / 0.86)
                    elif query_summary_profile == "v5_crossdoc":
                        query_base = clamp01(
                            (query_mass_norm * 0.15)
                            + (focus_norm * 0.12)
                            + (coverage_norm * 0.08)
                            + (recentness_norm * 0.06)
                            + (distance_norm * 0.08)
                            + (segment_focus_norm * 0.16)
                            + (segment_mass_norm * 0.10)
                            + (segment_role_norm * 0.10)
                            + (crossdoc_support_norm * 0.10)
                            + (recall_dependency_norm * 0.10)
                        )
                        query_norm = clamp01((query_base - segment_penalty - 0.05) / 0.86)
                    elif query_summary_profile == "v6_usefulness_cost":
                        utility_query_base = clamp01(
                            (anchor_rel_norm * 0.16)
                            + (evidence_role_norm * 0.20)
                            + (recall_risk_norm * 0.18)
                            + (crossdoc_support_norm * 0.10)
                            + (temporal_evidence_norm * 0.10)
                            + (temporal_persist_norm * 0.10)
                            + (head_budget_norm * 0.08)
                            + (focus_norm * 0.05)
                            + (specificity_norm * 0.03)
                        )
                        utility_blend = clamp01((utility_confidence_norm - 0.34) / 0.42)
                        query_base = clamp01(
                            (stable_query_base * (1.0 - utility_blend))
                            + ((utility_query_base - (segment_penalty * 0.60)) * utility_blend)
                        )
                        query_norm = clamp01((query_base - 0.05) / 0.88)
                    elif query_summary_profile == "rpau_v1":
                        candidate_utility_base = clamp01(
                            (norm_weight * 0.42)
                            + (recentness_norm * 0.18)
                            + (head_budget_norm * 0.14)
                            + (stable_query_base * 0.16)
                            + (stable_compression_base * 0.05)
                            + (stable_spill_base * 0.05)
                        )
                        protected_overlap = clamp01(
                            max(norm_weight, recentness_norm, stable_query_base) * 0.78
                        )
                        pressure_need = clamp01(
                            (backend_pressure_proxy * 0.34)
                            + ((1.0 - recentness_norm) * 0.18)
                            + (stable_spill_base * 0.16)
                            + (stable_compression_base * 0.14)
                            + (recall_risk_norm * 0.10)
                            + ((1.0 - coverage_norm) * 0.08)
                        )
                        candidate_pressure_residual = max(0.0, pressure_need - protected_overlap)
                        candidate_actionability = clamp01(
                            (candidate_utility_base * 0.68)
                            + (pressure_need * 0.22)
                            + (candidate_pressure_residual * 0.18)
                            - (max(norm_weight, recentness_norm) * 0.06)
                        )
                        query_base = candidate_actionability
                        query_norm = clamp01((query_base - 0.04) / 0.90)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.58)
                            + (pressure_need * 0.26)
                            + (candidate_pressure_residual * 0.16)
                        )
                    elif query_summary_profile == "rpau_reuse_v2":
                        candidate_utility_base = clamp01(
                            (norm_weight * 0.48)
                            + (recentness_norm * 0.22)
                            + (stable_query_base * 0.12)
                            + (head_budget_norm * 0.08)
                            + (recall_risk_norm * 0.04)
                            + (stable_compression_base * 0.03)
                            + (stable_spill_base * 0.03)
                        )
                        protected_overlap = clamp01(max(norm_weight, recentness_norm) * 0.64)
                        pressure_need = clamp01(
                            (backend_pressure_proxy * 0.22)
                            + (stable_spill_base * 0.20)
                            + (recall_risk_norm * 0.18)
                            + ((1.0 - recentness_norm) * 0.12)
                            + ((1.0 - coverage_norm) * 0.10)
                            + (temporal_persist_norm * 0.10)
                            + (head_budget_norm * 0.08)
                        )
                        candidate_pressure_residual = max(0.0, pressure_need - protected_overlap)
                        candidate_actionability = clamp01(
                            (candidate_utility_base * 0.74)
                            + (pressure_need * 0.16)
                            + (candidate_pressure_residual * 0.12)
                            - (max(norm_weight, recentness_norm) * 0.04)
                        )
                        query_base = candidate_actionability
                        query_norm = clamp01((query_base - 0.04) / 0.90)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.66)
                            + (pressure_need * 0.22)
                            + (candidate_pressure_residual * 0.12)
                        )
                    elif query_summary_profile == "qsr_v1":
                        structural_reuse = clamp01(
                            (crossdoc_support_norm * 0.22)
                            + (segment_focus_norm * 0.18)
                            + (segment_mass_norm * 0.14)
                            + (segment_role_norm * 0.14)
                            + (temporal_persist_norm * 0.14)
                            + (temporal_evidence_norm * 0.10)
                            + (continuity_norm * 0.08)
                        )
                        candidate_utility_base = clamp01(
                            (stable_query_base * 0.24)
                            + (query_mass_norm * 0.18)
                            + (structural_reuse * 0.30)
                            + (recall_dependency_norm * 0.14)
                            + (head_budget_norm * 0.08)
                            + (distance_norm * 0.06)
                        )
                        candidate_actionability = candidate_utility_base
                        query_base = candidate_utility_base
                        query_norm = clamp01((query_base - segment_penalty - 0.04) / 0.88)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.68)
                            + (structural_reuse * 0.20)
                            + (backend_pressure_proxy * 0.12)
                        )
                    elif query_summary_profile == "qrc_v1":
                        quality_cost = clamp01(
                            (recall_risk_norm * 0.24)
                            + (recall_dependency_norm * 0.18)
                            + (stable_compression_base * 0.18)
                            + (stable_spill_base * 0.16)
                            + (evidence_role_norm * 0.10)
                            + (head_budget_norm * 0.08)
                            + (backend_pressure_proxy * 0.06)
                        )
                        candidate_utility_base = clamp01(
                            (stable_query_base * 0.28)
                            + (quality_cost * 0.34)
                            + (norm_weight * 0.18)
                            + (recentness_norm * 0.10)
                            + (temporal_persist_norm * 0.10)
                        )
                        candidate_actionability = candidate_utility_base
                        query_base = candidate_utility_base
                        query_norm = clamp01((query_base - 0.04) / 0.88)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.52)
                            + (quality_cost * 0.32)
                            + (backend_pressure_proxy * 0.16)
                        )
                    elif query_summary_profile == "cas_u_lite":
                        candidate_utility_base = clamp01(
                            (norm_weight * 0.44)
                            + (recentness_norm * 0.20)
                            + (stable_query_base * 0.14)
                            + (head_budget_norm * 0.10)
                            + (recall_risk_norm * 0.06)
                            + (stable_spill_base * 0.04)
                            + (stable_compression_base * 0.02)
                        )
                        protected_overlap = clamp01(
                            (max(norm_weight, recentness_norm, stable_query_base) * 0.72)
                            + (head_budget_norm * 0.08)
                        )
                        pressure_need = clamp01(
                            (backend_pressure_proxy * 0.18)
                            + (stable_spill_base * 0.18)
                            + (recall_risk_norm * 0.14)
                            + (temporal_persist_norm * 0.12)
                            + ((1.0 - recentness_norm) * 0.10)
                            + ((1.0 - coverage_norm) * 0.08)
                            + (stable_query_base * 0.10)
                            + (head_budget_norm * 0.10)
                        )
                        candidate_pressure_residual = max(0.0, pressure_need - protected_overlap)
                        candidate_actionability = clamp01(
                            (candidate_utility_base * 0.78)
                            + (pressure_need * 0.10)
                            + (candidate_pressure_residual * 0.08)
                            - (max(norm_weight, recentness_norm) * 0.03)
                        )
                        query_base = candidate_actionability
                        query_norm = clamp01((query_base - 0.04) / 0.90)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.74)
                            + (pressure_need * 0.16)
                            + (candidate_pressure_residual * 0.10)
                        )
                    elif query_summary_profile == "temporal_aware":
                        temporal_focus = clamp01(
                            (temporal_persist_norm * 0.26)
                            + (temporal_evidence_norm * 0.18)
                            + (recall_dependency_norm * 0.16)
                            + (evidence_role_norm * 0.14)
                            + (query_mass_norm * 0.10)
                            + (focus_norm * 0.06)
                            + (coverage_norm * 0.04)
                            + (head_budget_norm * 0.06)
                        )
                        candidate_utility_base = temporal_focus
                        candidate_actionability = temporal_focus
                        query_base = clamp01((stable_query_base * 0.35) + (temporal_focus * 0.65) - (segment_penalty * 0.20))
                        query_norm = clamp01((query_base - 0.05) / 0.88)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.64)
                            + (temporal_focus * 0.22)
                            + (backend_pressure_proxy * 0.14)
                        )
                    elif query_summary_profile == "temporal_aware_v2":
                        temporal_focus = clamp01(
                            (temporal_persist_norm * 0.30)
                            + (temporal_evidence_norm * 0.22)
                            + (recall_dependency_norm * 0.18)
                            + (evidence_role_norm * 0.10)
                            + (continuity_norm * 0.08)
                            + (distance_norm * 0.06)
                            + (head_budget_norm * 0.06)
                        )
                        temporal_rescue = clamp01(
                            (temporal_persist_norm * 0.18)
                            + (temporal_evidence_norm * 0.18)
                            + (recall_risk_norm * 0.16)
                            + (distance_norm * 0.16)
                            + ((1.0 - recentness_norm) * 0.12)
                            + (backend_pressure_proxy * 0.10)
                            + (coverage_norm * 0.10)
                        )
                        candidate_utility_base = temporal_focus
                        candidate_actionability = clamp01(
                            (temporal_focus * 0.82) + (temporal_rescue * 0.18)
                        )
                        query_base = clamp01(
                            (stable_query_base * 0.22)
                            + (temporal_focus * 0.68)
                            + (temporal_rescue * 0.10)
                            - (segment_penalty * 0.08)
                        )
                        query_norm = clamp01((query_base - 0.04) / 0.88)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.88)
                            + (backend_pressure_proxy * 0.08)
                            + (temporal_rescue * 0.04)
                        )
                    elif query_summary_profile == "temporal_query_hybrid":
                        hybrid_focus = clamp01(
                            (temporal_persist_norm * 0.18)
                            + (temporal_evidence_norm * 0.14)
                            + (recall_dependency_norm * 0.12)
                            + (crossdoc_support_norm * 0.16)
                            + (segment_focus_norm * 0.14)
                            + (segment_role_norm * 0.10)
                            + (continuity_norm * 0.08)
                            + (query_mass_norm * 0.08)
                        )
                        candidate_utility_base = hybrid_focus
                        candidate_actionability = hybrid_focus
                        query_base = clamp01(
                            (stable_query_base * 0.24)
                            + (hybrid_focus * 0.58)
                            + (recall_dependency_norm * 0.10)
                            + (head_budget_norm * 0.08)
                            - (segment_penalty * 0.14)
                        )
                        query_norm = clamp01((query_base - 0.04) / 0.88)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.84)
                            + (backend_pressure_proxy * 0.10)
                            + (hybrid_focus * 0.06)
                        )
                    elif query_summary_profile in ("query_structure_aware", "query_structure_decoupled"):
                        structural_focus = clamp01(
                            (crossdoc_support_norm * 0.20)
                            + (segment_focus_norm * 0.18)
                            + (segment_mass_norm * 0.14)
                            + (segment_role_norm * 0.14)
                            + (query_mass_norm * 0.10)
                            + (coverage_norm * 0.08)
                            + (temporal_persist_norm * 0.08)
                            + (continuity_norm * 0.08)
                        )
                        candidate_utility_base = structural_focus
                        candidate_actionability = structural_focus
                        query_base = clamp01(
                            (stable_query_base * 0.30)
                            + (structural_focus * 0.52)
                            + (recall_dependency_norm * 0.10)
                            + (head_budget_norm * 0.08)
                            - (segment_penalty * 0.20)
                        )
                        query_norm = clamp01((query_base - 0.04) / 0.88)
                        if query_summary_profile == "query_structure_decoupled":
                            service_criticality_norm = clamp01(
                                (service_criticality_norm * 0.90)
                                + (backend_pressure_proxy * 0.08)
                            )
                        else:
                            service_criticality_norm = clamp01(
                                (service_criticality_norm * 0.66)
                                + (structural_focus * 0.22)
                                + (backend_pressure_proxy * 0.12)
                            )
                    elif query_summary_profile == "scheduler_temporal_v1":
                        temporal_focus = clamp01(
                            (temporal_persist_norm * 0.30)
                            + (temporal_evidence_norm * 0.24)
                            + (recall_dependency_norm * 0.16)
                            + (distance_norm * 0.12)
                            + ((1.0 - recentness_norm) * 0.10)
                            + (head_budget_norm * 0.08)
                        )
                        temporal_window = clamp01(
                            (distance_norm * 0.26)
                            + ((1.0 - recentness_norm) * 0.22)
                            + (recall_risk_norm * 0.16)
                            + (backend_pressure_proxy * 0.14)
                            + (temporal_evidence_norm * 0.12)
                            + (coverage_norm * 0.10)
                        )
                        candidate_utility_base = temporal_focus
                        candidate_actionability = clamp01((temporal_focus * 0.72) + (temporal_window * 0.28))
                        query_base = clamp01(
                            (stable_query_base * 0.18)
                            + (temporal_focus * 0.64)
                            + (temporal_window * 0.18)
                            - (segment_penalty * 0.06)
                        )
                        query_norm = clamp01((query_base - 0.04) / 0.88)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.86)
                            + (backend_pressure_proxy * 0.10)
                            + (temporal_window * 0.04)
                        )
                    elif query_summary_profile == "structured_query_v2":
                        structural_focus = clamp01(
                            (crossdoc_support_norm * 0.22)
                            + (segment_focus_norm * 0.20)
                            + (segment_mass_norm * 0.14)
                            + (segment_role_norm * 0.14)
                            + (recall_dependency_norm * 0.10)
                            + (coverage_norm * 0.08)
                            + (temporal_persist_norm * 0.06)
                            + (continuity_norm * 0.06)
                        )
                        candidate_utility_base = structural_focus
                        candidate_actionability = structural_focus
                        query_base = clamp01(
                            (stable_query_base * 0.24)
                            + (structural_focus * 0.60)
                            + (recall_dependency_norm * 0.10)
                            + (head_budget_norm * 0.06)
                            - (segment_penalty * 0.12)
                        )
                        query_norm = clamp01((query_base - 0.04) / 0.88)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.92)
                            + (backend_pressure_proxy * 0.08)
                        )
                    elif query_summary_profile == "scheduler_temporal_query_hybrid_v1":
                        hybrid_focus = clamp01(
                            (temporal_persist_norm * 0.16)
                            + (temporal_evidence_norm * 0.12)
                            + (distance_norm * 0.08)
                            + ((1.0 - recentness_norm) * 0.06)
                            + (crossdoc_support_norm * 0.16)
                            + (segment_focus_norm * 0.15)
                            + (segment_role_norm * 0.10)
                            + (recall_dependency_norm * 0.12)
                            + (head_budget_norm * 0.05)
                        )
                        hybrid_temporal_selectivity_norm = clamp01(
                            (segment_role_norm * 0.28)
                            + (segment_focus_norm * 0.20)
                            + (head_budget_norm * 0.16)
                            + (norm_weight * 0.14)
                            + (recall_dependency_norm * 0.12)
                            + (temporal_evidence_norm * 0.10)
                        )
                        hybrid_structural_selectivity_norm = clamp01(
                            (crossdoc_support_norm * 0.24)
                            + (segment_focus_norm * 0.22)
                            + (segment_role_norm * 0.16)
                            + (recall_dependency_norm * 0.14)
                            + (head_budget_norm * 0.12)
                            + (stable_query_base * 0.12)
                        )
                        hybrid_selectivity_norm = clamp01(
                            (hybrid_structural_selectivity_norm * 0.58)
                            + (hybrid_temporal_selectivity_norm * 0.42)
                        )
                        hybrid_penalty_norm = clamp01(
                            ((1.0 - hybrid_selectivity_norm) * 0.50)
                            + ((1.0 - temporal_evidence_norm) * 0.18)
                            + ((1.0 - crossdoc_support_norm) * 0.18)
                            + ((1.0 - recall_dependency_norm) * 0.14)
                        )
                        candidate_utility_base = hybrid_focus
                        candidate_actionability = clamp01(
                            (hybrid_focus * 0.76)
                            + (hybrid_selectivity_norm * 0.14)
                            + (backend_pressure_proxy * 0.06)
                            + (head_budget_norm * 0.04)
                        )
                        query_base = clamp01(
                            (stable_query_base * 0.14)
                            + (hybrid_focus * 0.56)
                            + (hybrid_structural_selectivity_norm * 0.18)
                            + (recall_dependency_norm * 0.08)
                            + (head_budget_norm * 0.04)
                            - (segment_penalty * 0.08)
                            - (hybrid_penalty_norm * 0.10)
                        )
                        query_norm = clamp01((query_base - 0.04) / 0.88)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.90)
                            + (backend_pressure_proxy * 0.08)
                            + (hybrid_selectivity_norm * 0.02)
                        )
                    elif query_summary_profile == "autopareto_v1":
                        candidate_utility_base = clamp01(
                            (norm_weight * 0.32)
                            + (stable_query_base * 0.18)
                            + (recentness_norm * 0.14)
                            + (head_budget_norm * 0.10)
                            + (recall_risk_norm * 0.10)
                            + (backend_pressure_proxy * 0.08)
                            + (stable_compression_base * 0.04)
                            + (stable_spill_base * 0.04)
                        )
                        candidate_actionability = candidate_utility_base
                        query_base = candidate_utility_base
                        query_norm = clamp01((query_base - 0.05) / 0.88)
                        service_criticality_norm = clamp01(
                            (service_criticality_norm * 0.70)
                            + (backend_pressure_proxy * 0.18)
                            + (candidate_utility_base * 0.12)
                        )
                    else:
                        query_base = stable_query_base
                        query_norm = clamp01((query_base - 0.06) / 0.84)
                    temporal_persist_class = 0
                    reuse_distance_class = 0
                    query_structure_class = 0
                    sched_urgency_hint = 0
                    if query_summary_profile == "scheduler_temporal_v1":
                        # The scheduler-master temporal path only pays off when
                        # temporal ownership penetrates on genuinely actionable
                        # blocks. Weak question/decode blocks were over-tagged on
                        # bridge models, so gate temporal classes with a compact
                        # selectivity term instead of broadening RTL conditions.
                        temporal_selectivity_norm = clamp01(
                            (segment_role_norm * 0.30)
                            + (segment_focus_norm * 0.22)
                            + (query_norm * 0.18)
                            + (head_budget_norm * 0.16)
                            + (norm_weight * 0.14)
                        )
                        temporal_penalty_norm = clamp01(
                            ((1.0 - temporal_selectivity_norm) * 0.58)
                            + ((1.0 - recall_dependency_norm) * 0.22)
                            + ((1.0 - temporal_evidence_norm) * 0.20)
                        )
                        temporal_persist_class = class2_from_norm(
                            (temporal_persist_norm * 0.58)
                            + (temporal_evidence_norm * 0.24)
                            + (recall_dependency_norm * 0.18)
                            - (temporal_penalty_norm * 0.18)
                        )
                        reuse_distance_class = class2_from_norm(
                            (distance_norm * 0.48)
                            + ((1.0 - recentness_norm) * 0.28)
                            + (recall_dependency_norm * 0.24)
                            - (temporal_penalty_norm * 0.14)
                        )
                        # Give the temporal scheduler a denser structured shadow on
                        # focused multi-segment blocks without promoting LCQA-style
                        # broad context blocks into the structured-hot lane.
                        structured_shadow_boost = 0.0
                        if segment_focus_norm >= 0.50 and crossdoc_support_norm >= 0.38:
                            structured_shadow_boost += 0.06
                        if dominant_seg_type == "doc":
                            if segment_focus_norm >= 0.52 and recall_dependency_norm >= 0.48:
                                structured_shadow_boost += 0.10
                            if segment_focus_norm >= 0.58:
                                structured_shadow_boost += 0.06
                        elif dominant_seg_type == "assistant":
                            if segment_focus_norm >= 0.60 and recall_dependency_norm >= 0.54:
                                structured_shadow_boost += 0.04
                        if dominant_seg_type in ("context", "user"):
                            structured_shadow_boost -= 0.06
                        elif dominant_seg_type == "preamble":
                            structured_shadow_boost -= 0.10
                        structural_shadow_norm = clamp01(
                            (crossdoc_support_norm * 0.30)
                            + (segment_focus_norm * 0.22)
                            + (segment_role_norm * 0.16)
                            + (segment_mass_norm * 0.12)
                            + (recall_dependency_norm * 0.12)
                            + (query_norm * 0.08)
                            - (temporal_selectivity_norm * 0.10)
                            + structured_shadow_boost
                        )
                        query_structure_class = class2_from_norm(
                            structural_shadow_norm
                            * (
                                0.80
                                + ((1.0 - temporal_selectivity_norm) * 0.14)
                                + (
                                    0.04
                                    if (
                                        dominant_seg_type == "doc"
                                        and segment_focus_norm >= 0.56
                                    )
                                    else 0.0
                                )
                            )
                        )
                        if temporal_selectivity_norm < 0.33 and temporal_persist_class > 0:
                            temporal_persist_class -= 1
                        if (
                            temporal_selectivity_norm < 0.36
                            and recall_dependency_norm < 0.56
                            and reuse_distance_class > 1
                        ):
                            reuse_distance_class -= 1
                        if temporal_selectivity_norm < 0.34 and query_structure_class > 0:
                            query_structure_class -= 1
                        if (
                            temporal_persist_class >= 2
                            and query_structure_class > 1
                            and segment_focus_norm < 0.62
                        ):
                            query_structure_class -= 1
                        sched_urgency_hint = class2_from_norm(
                            (
                                (backend_pressure_proxy * 0.34)
                                + (distance_norm * 0.24)
                                + (temporal_evidence_norm * 0.18)
                                + ((1.0 - recentness_norm) * 0.14)
                                + (recall_risk_norm * 0.10)
                            )
                            * (0.72 + (temporal_selectivity_norm * 0.28))
                        )
                    elif query_summary_profile == "structured_query_v2":
                        query_structure_class = class2_from_norm(
                            (crossdoc_support_norm * 0.32)
                            + (segment_focus_norm * 0.24)
                            + (segment_role_norm * 0.18)
                            + (segment_mass_norm * 0.14)
                            + (recall_dependency_norm * 0.12)
                        )
                        sched_urgency_hint = class2_from_norm(
                            (query_norm * 0.34)
                            + (crossdoc_support_norm * 0.22)
                            + (recall_dependency_norm * 0.18)
                            + (backend_pressure_proxy * 0.14)
                            + (segment_focus_norm * 0.12)
                        )
                    elif query_summary_profile == "scheduler_temporal_query_hybrid_v1":
                        temporal_persist_class = class2_from_norm(
                            (temporal_persist_norm * 0.48)
                            + (temporal_evidence_norm * 0.20)
                            + (distance_norm * 0.10)
                            + (recall_dependency_norm * 0.22)
                            - (hybrid_penalty_norm * 0.16)
                        )
                        reuse_distance_class = class2_from_norm(
                            (distance_norm * 0.36)
                            + ((1.0 - recentness_norm) * 0.22)
                            + (recall_dependency_norm * 0.22)
                            + (crossdoc_support_norm * 0.12)
                            + (segment_focus_norm * 0.08)
                            - (hybrid_penalty_norm * 0.10)
                        )
                        query_structure_class = class2_from_norm(
                            (crossdoc_support_norm * 0.28)
                            + (segment_focus_norm * 0.22)
                            + (segment_role_norm * 0.16)
                            + (recall_dependency_norm * 0.20)
                            + (query_norm * 0.14)
                            - ((1.0 - hybrid_structural_selectivity_norm) * 0.12)
                        )
                        if hybrid_selectivity_norm < 0.34 and temporal_persist_class > 0:
                            temporal_persist_class -= 1
                        if (
                            hybrid_selectivity_norm < 0.40
                            and recall_dependency_norm < 0.58
                            and reuse_distance_class > 1
                        ):
                            reuse_distance_class -= 1
                        if hybrid_structural_selectivity_norm < 0.38 and query_structure_class > 0:
                            query_structure_class -= 1
                        sched_urgency_hint = class2_from_norm(
                            (
                                (backend_pressure_proxy * 0.28)
                                + (query_norm * 0.20)
                                + (temporal_evidence_norm * 0.14)
                                + (recall_dependency_norm * 0.18)
                                + (crossdoc_support_norm * 0.20)
                            )
                            * (0.74 + (hybrid_selectivity_norm * 0.26))
                        )
                    query_relevance = score_from_weight(query_norm)
                    service_criticality = score_from_weight(service_criticality_norm)
                    if dump_query_usefulness and query_usefulness_dump is not None:
                        query_usefulness_dump.append(
                            {
                                "seq_id": seq_id,
                                "blk": blk,
                                "kv_kind": kv_kind,
                                "query_norm": round(query_norm, 4),
                                "query_mass": round(query_mass_norm, 4),
                                "focus": round(focus_norm, 4),
                                "coverage": round(coverage_norm, 4),
                                "evidence_role": round(evidence_role_norm, 4),
                                "recall_risk": round(recall_risk_norm, 4),
                                "recall_dependency": round(recall_dependency_norm, 4),
                                "crossdoc_support": round(crossdoc_support_norm, 4),
                                "segment_focus": round(segment_focus_norm, 4),
                                "segment_mass": round(segment_mass_norm, 4),
                                "segment_role": round(segment_role_norm, 4),
                                "specificity": round(specificity_norm, 4),
                                "separation": round(separation_norm, 4),
                                "recentness": round(recentness_norm, 4),
                                "distance": round(distance_norm, 4),
                                "temporal_persist": round(temporal_persist_norm, 4),
                                "temporal_evidence": round(temporal_evidence_norm, 4),
                                "head_budget": round(head_budget_norm, 4),
                                "backend_pressure_proxy": round(backend_pressure_proxy, 4),
                                "service_criticality_profile": service_criticality_profile,
                                "service_criticality_current_norm": round(service_criticality_current_norm, 4),
                                "service_base_v2": round(service_base_v2, 4),
                                "service_residual_v2": round(service_residual_v2, 4),
                                "service_scheduler_overlap_v3": round(service_scheduler_overlap_v3, 4),
                                "service_scheduler_cold_hint_v3": round(service_scheduler_cold_hint_v3, 4),
                                "service_rescue_gap_v3": round(service_rescue_gap_v3, 4),
                                "service_issue_overlap_v4": round(service_issue_overlap_v4, 4),
                                "service_issue_window_v4": round(service_issue_window_v4, 4),
                                "service_criticality_norm": round(service_criticality_norm, 4),
                                "stable_query_core": round(stable_query_core, 4),
                                "utility_query_base": round(utility_query_base, 4),
                                "stable_query_blend": round(stable_query_blend, 4),
                                "utility_residual_base": round(utility_residual_base, 4),
                                "residual_gate": round(residual_gate, 4),
                                "stable_query_residual": round(stable_query_residual, 4),
                                "stable_core_weight": round(stable_core_weight, 4),
                                "stable_residual_weight": round(stable_residual_weight, 4),
                                "stable_query_base": round(stable_query_base, 4),
                                "utility_confidence": round(utility_confidence_norm, 4),
                                "candidate_profile": query_summary_profile,
                                "candidate_utility_base": round(candidate_utility_base, 4),
                                "candidate_actionability": round(candidate_actionability, 4),
                                "candidate_pressure_residual": round(candidate_pressure_residual, 4),
                                "attention": round(norm_weight, 4),
                            }
                        )
                    if query_summary_profile == "haqu_s4_tuned":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.60)
                            + (query_norm * 0.14)
                            + (recall_risk_norm * 0.08)
                            + (temporal_persist_norm * 0.08)
                            + (temporal_evidence_norm * 0.06)
                            + (head_budget_norm * 0.04)
                        )
                    elif query_summary_profile == "v2_consensus":
                        compression_risk_base = clamp01(
                            (peak_norm * 0.28)
                            + (query_norm * 0.24)
                            + (head_budget_norm * 0.18)
                            + (specificity_norm * 0.20)
                            + ((1.0 - recentness_norm) * 0.10)
                            + (0.10 if kv_kind == KV_KIND_V else 0.0)
                        )
                    elif query_summary_profile == "v2_usefulness":
                        compression_risk_base = clamp01(
                            (peak_norm * 0.20)
                            + (query_norm * 0.24)
                            + (evidence_role_norm * 0.22)
                            + (specificity_norm * 0.14)
                            + (head_budget_norm * 0.12)
                            + ((1.0 - recentness_norm) * 0.08)
                            + (0.10 if kv_kind == KV_KIND_V else 0.0)
                        )
                    elif query_summary_profile == "v3_temporal":
                        compression_risk_base = clamp01(
                            (peak_norm * 0.18)
                            + (query_norm * 0.22)
                            + (evidence_role_norm * 0.20)
                            + (temporal_persist_norm * 0.16)
                            + (head_budget_norm * 0.10)
                            + (specificity_norm * 0.08)
                            + ((1.0 - recentness_norm) * 0.06)
                            + (0.10 if kv_kind == KV_KIND_V else 0.0)
                        )
                    elif query_summary_profile == "v4_evidence_temporal":
                        compression_risk_base = clamp01(
                            (query_norm * 0.18)
                            + (evidence_role_norm * 0.22)
                            + (temporal_evidence_norm * 0.16)
                            + (peak_norm * 0.12)
                            + (recall_risk_norm * 0.10)
                            + (head_budget_norm * 0.10)
                            + (specificity_norm * 0.04)
                            + (0.10 if kv_kind == KV_KIND_V else 0.0)
                        )
                    elif query_summary_profile == "v5_crossdoc":
                        compression_risk_base = clamp01(
                            (query_norm * 0.18)
                            + (peak_norm * 0.12)
                            + (head_budget_norm * 0.12)
                            + (segment_focus_norm * 0.12)
                            + (segment_role_norm * 0.10)
                            + (segment_mass_norm * 0.08)
                            + (crossdoc_support_norm * 0.10)
                            + (recall_dependency_norm * 0.08)
                            + (specificity_norm * 0.06)
                            + (0.10 if kv_kind == KV_KIND_V else 0.0)
                        )
                    elif query_summary_profile == "v6_usefulness_cost":
                        utility_compression_base = clamp01(
                            (query_norm * 0.18)
                            + (recall_risk_norm * 0.18)
                            + (evidence_role_norm * 0.16)
                            + (peak_norm * 0.12)
                            + (head_budget_norm * 0.10)
                            + (temporal_persist_norm * 0.08)
                            + (specificity_norm * 0.08)
                            + (0.10 if kv_kind == KV_KIND_V else 0.0)
                        )
                        cost_blend = clamp01((utility_confidence_norm - 0.30) / 0.44)
                        compression_risk_base = clamp01(
                            (stable_compression_base * (1.0 - (cost_blend * 0.70)))
                            + (utility_compression_base * (cost_blend * 0.70))
                        )
                    elif query_summary_profile == "v7_cost_v2":
                        compression_risk_base = clamp01(
                            (query_norm * 0.26)
                            + (recall_risk_norm * 0.20)
                            + (peak_norm * 0.14)
                            + (head_budget_norm * 0.14)
                            + (temporal_persist_norm * 0.10)
                            + (evidence_role_norm * 0.08)
                            + (specificity_norm * 0.08)
                            + ((1.0 - recentness_norm) * 0.06)
                            + (0.10 if kv_kind == KV_KIND_V else 0.0)
                        )
                    elif query_summary_profile == "rpau_v1":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.58)
                            + (candidate_actionability * 0.18)
                            + (candidate_pressure_residual * 0.10)
                            + (recall_risk_norm * 0.08)
                            + (backend_pressure_proxy * 0.06)
                        )
                    elif query_summary_profile == "rpau_reuse_v2":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.62)
                            + (candidate_actionability * 0.14)
                            + (recall_risk_norm * 0.10)
                            + (candidate_pressure_residual * 0.08)
                            + (backend_pressure_proxy * 0.06)
                        )
                    elif query_summary_profile == "qsr_v1":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.44)
                            + (query_norm * 0.16)
                            + (crossdoc_support_norm * 0.12)
                            + (segment_focus_norm * 0.10)
                            + (temporal_persist_norm * 0.10)
                            + (head_budget_norm * 0.08)
                        )
                    elif query_summary_profile == "qrc_v1":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.40)
                            + (query_norm * 0.20)
                            + (recall_risk_norm * 0.18)
                            + (recall_dependency_norm * 0.10)
                            + (head_budget_norm * 0.08)
                            + (backend_pressure_proxy * 0.04)
                        )
                    elif query_summary_profile == "cas_u_lite":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.64)
                            + (candidate_actionability * 0.12)
                            + (candidate_pressure_residual * 0.06)
                            + (recall_risk_norm * 0.10)
                            + (backend_pressure_proxy * 0.04)
                            + (query_norm * 0.04)
                        )
                    elif query_summary_profile == "temporal_aware":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.46)
                            + (query_norm * 0.18)
                            + (temporal_evidence_norm * 0.14)
                            + (temporal_persist_norm * 0.12)
                            + (recall_risk_norm * 0.10)
                            + (head_budget_norm * 0.10)
                        )
                    elif query_summary_profile == "temporal_aware_v2":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.42)
                            + (query_norm * 0.16)
                            + (temporal_evidence_norm * 0.18)
                            + (temporal_persist_norm * 0.14)
                            + (recall_risk_norm * 0.10)
                            + (head_budget_norm * 0.10)
                        )
                    elif query_summary_profile == "temporal_query_hybrid":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.40)
                            + (query_norm * 0.16)
                            + (temporal_evidence_norm * 0.12)
                            + (temporal_persist_norm * 0.10)
                            + (crossdoc_support_norm * 0.10)
                            + (segment_focus_norm * 0.08)
                            + (segment_role_norm * 0.08)
                            + (head_budget_norm * 0.08)
                        )
                    elif query_summary_profile == "scheduler_temporal_query_hybrid_v1":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.42)
                            + (query_norm * 0.14)
                            + (temporal_evidence_norm * 0.10)
                            + (temporal_persist_norm * 0.08)
                            + (crossdoc_support_norm * 0.10)
                            + (segment_focus_norm * 0.08)
                            + (segment_role_norm * 0.06)
                            + (head_budget_norm * 0.08)
                            - ((1.0 - hybrid_selectivity_norm) * 0.06)
                        )
                    elif query_summary_profile in ("query_structure_aware", "query_structure_decoupled"):
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.44)
                            + (query_norm * 0.16)
                            + (crossdoc_support_norm * 0.12)
                            + (segment_focus_norm * 0.12)
                            + (segment_role_norm * 0.08)
                            + (head_budget_norm * 0.08)
                        )
                    elif query_summary_profile == "autopareto_v1":
                        compression_risk_base = clamp01(
                            (stable_compression_base * 0.54)
                            + (query_norm * 0.18)
                            + (recall_risk_norm * 0.10)
                            + (head_budget_norm * 0.10)
                            + (backend_pressure_proxy * 0.08)
                        )
                    else:
                        compression_risk_base = stable_compression_base
                    if query_summary_profile in ("v7_cost_v2", "rpau_v1", "rpau_reuse_v2", "qrc_v1", "autopareto_v1", "cas_u_lite"):
                        compression_risk_norm = clamp01((compression_risk_base - 0.04) / 0.84)
                    else:
                        compression_risk_norm = clamp01((compression_risk_base - 0.08) / 0.92)
                    if query_summary_profile == "haqu_s4_tuned":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.58)
                            + (query_norm * 0.10)
                            + (recall_dependency_norm * 0.10)
                            + (temporal_persist_norm * 0.10)
                            + (temporal_evidence_norm * 0.06)
                            + (head_budget_norm * 0.06)
                        )
                        spill_cost_base = clamp01(
                            (stable_spill_base * 0.56)
                            + (reuse_pressure_norm * 0.16)
                            + (query_norm * 0.08)
                            + (recall_dependency_norm * 0.08)
                            + (temporal_persist_norm * 0.08)
                            + (head_budget_norm * 0.04)
                        )
                    elif query_summary_profile == "v2_consensus":
                        reuse_pressure_norm = clamp01(
                            (coverage_norm * 0.38)
                            + (recentness_norm * 0.30)
                            + (norm_weight * 0.20)
                            + (query_norm * 0.12)
                        )
                        spill_cost_base = clamp01(
                            (distance_norm * 0.40)
                            + (reuse_pressure_norm * 0.32)
                            + (query_norm * 0.18)
                            + (consensus_norm * 0.10)
                        )
                    elif query_summary_profile == "v2_usefulness":
                        reuse_pressure_norm = clamp01(
                            (coverage_norm * 0.30)
                            + (recentness_norm * 0.22)
                            + (norm_weight * 0.14)
                            + (query_norm * 0.14)
                            + (evidence_role_norm * 0.20)
                        )
                        spill_cost_base = clamp01(
                            (recall_risk_norm * 0.34)
                            + (distance_norm * 0.22)
                            + (reuse_pressure_norm * 0.22)
                            + (head_budget_norm * 0.12)
                            + (query_norm * 0.10)
                        )
                    elif query_summary_profile == "v3_temporal":
                        reuse_pressure_norm = clamp01(
                            (coverage_norm * 0.24)
                            + (recentness_norm * 0.18)
                            + (norm_weight * 0.12)
                            + (query_norm * 0.12)
                            + (evidence_role_norm * 0.16)
                            + (temporal_persist_norm * 0.18)
                        )
                        spill_cost_base = clamp01(
                            (recall_risk_norm * 0.28)
                            + (distance_norm * 0.18)
                            + (reuse_pressure_norm * 0.18)
                            + (head_budget_norm * 0.10)
                            + (query_norm * 0.10)
                            + (temporal_persist_norm * 0.16)
                        )
                    elif query_summary_profile == "v4_evidence_temporal":
                        reuse_pressure_norm = clamp01(
                            (evidence_role_norm * 0.22)
                            + (temporal_evidence_norm * 0.20)
                            + (coverage_norm * 0.16)
                            + (recentness_norm * 0.12)
                            + (query_norm * 0.10)
                            + (norm_weight * 0.10)
                            + (consensus_norm * 0.10)
                        )
                        spill_cost_base = clamp01(
                            (recall_risk_norm * 0.24)
                            + (temporal_evidence_norm * 0.18)
                            + (evidence_role_norm * 0.18)
                            + (distance_norm * 0.14)
                            + (reuse_pressure_norm * 0.12)
                            + (query_norm * 0.08)
                            + (head_budget_norm * 0.06)
                        )
                    elif query_summary_profile == "v5_crossdoc":
                        reuse_pressure_norm = clamp01(
                            (coverage_norm * 0.18)
                            + (recentness_norm * 0.14)
                            + (norm_weight * 0.10)
                            + (query_norm * 0.10)
                            + (segment_focus_norm * 0.14)
                            + (segment_mass_norm * 0.12)
                            + (segment_role_norm * 0.10)
                            + (crossdoc_support_norm * 0.12)
                        )
                        spill_cost_base = clamp01(
                            (distance_norm * 0.20)
                            + (reuse_pressure_norm * 0.18)
                            + (query_norm * 0.10)
                            + (head_budget_norm * 0.08)
                            + (segment_mass_norm * 0.10)
                            + (segment_focus_norm * 0.12)
                            + (segment_role_norm * 0.10)
                            + (crossdoc_support_norm * 0.06)
                            + (recall_dependency_norm * 0.06)
                        )
                    elif query_summary_profile == "v6_usefulness_cost":
                        utility_reuse_pressure_norm = clamp01(
                            (coverage_norm * 0.24)
                            + (recentness_norm * 0.18)
                            + (query_norm * 0.12)
                            + (evidence_role_norm * 0.14)
                            + (recall_risk_norm * 0.12)
                            + (temporal_persist_norm * 0.10)
                            + (head_budget_norm * 0.10)
                        )
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.65)
                            + (utility_reuse_pressure_norm * 0.35)
                        )
                        utility_spill_base = clamp01(
                            (recall_risk_norm * 0.24)
                            + (distance_norm * 0.18)
                            + (reuse_pressure_norm * 0.18)
                            + (query_norm * 0.12)
                            + (evidence_role_norm * 0.10)
                            + (temporal_evidence_norm * 0.10)
                            + (head_budget_norm * 0.08)
                        )
                        spill_blend = clamp01((utility_confidence_norm - 0.28) / 0.46)
                        spill_cost_base = clamp01(
                            (stable_spill_base * (1.0 - (spill_blend * 0.65)))
                            + (utility_spill_base * (spill_blend * 0.65))
                        )
                    elif query_summary_profile == "v7_cost_v2":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.62)
                            + (query_norm * 0.10)
                            + (recall_risk_norm * 0.10)
                            + (temporal_persist_norm * 0.08)
                            + (head_budget_norm * 0.10)
                        )
                        spill_cost_base = clamp01(
                            (recall_risk_norm * 0.24)
                            + (distance_norm * 0.22)
                            + (reuse_pressure_norm * 0.20)
                            + (backend_pressure_proxy * 0.14)
                            + (query_norm * 0.10)
                            + (temporal_persist_norm * 0.10)
                        )
                    elif query_summary_profile == "rpau_v1":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.46)
                            + (candidate_actionability * 0.20)
                            + (backend_pressure_proxy * 0.16)
                            + (candidate_pressure_residual * 0.10)
                            + (recall_risk_norm * 0.08)
                        )
                        spill_cost_base = clamp01(
                            (stable_spill_base * 0.44)
                            + (reuse_pressure_norm * 0.20)
                            + (backend_pressure_proxy * 0.18)
                            + (candidate_pressure_residual * 0.10)
                            + (query_norm * 0.08)
                        )
                    elif query_summary_profile == "rpau_reuse_v2":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.54)
                            + (candidate_actionability * 0.18)
                            + (recentness_norm * 0.10)
                            + (backend_pressure_proxy * 0.08)
                            + (candidate_pressure_residual * 0.06)
                            + (recall_risk_norm * 0.04)
                        )
                        spill_cost_base = clamp01(
                            (stable_spill_base * 0.50)
                            + (reuse_pressure_norm * 0.20)
                            + (backend_pressure_proxy * 0.12)
                            + (candidate_pressure_residual * 0.10)
                            + (query_norm * 0.08)
                        )
                    elif query_summary_profile == "qsr_v1":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.34)
                            + (query_norm * 0.14)
                            + (crossdoc_support_norm * 0.16)
                            + (segment_mass_norm * 0.12)
                            + (temporal_persist_norm * 0.14)
                            + (continuity_norm * 0.10)
                        )
                        spill_cost_base = clamp01(
                            (distance_norm * 0.22)
                            + (reuse_pressure_norm * 0.24)
                            + (query_norm * 0.12)
                            + (crossdoc_support_norm * 0.12)
                            + (segment_focus_norm * 0.10)
                            + (segment_role_norm * 0.08)
                            + (head_budget_norm * 0.06)
                            + (backend_pressure_proxy * 0.06)
                        )
                    elif query_summary_profile == "qrc_v1":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.40)
                            + (query_norm * 0.16)
                            + (recall_risk_norm * 0.14)
                            + (backend_pressure_proxy * 0.12)
                            + (stable_compression_base * 0.10)
                            + (head_budget_norm * 0.08)
                        )
                        spill_cost_base = clamp01(
                            (stable_spill_base * 0.36)
                            + (reuse_pressure_norm * 0.18)
                            + (recall_risk_norm * 0.18)
                            + (backend_pressure_proxy * 0.14)
                            + (query_norm * 0.08)
                            + (head_budget_norm * 0.06)
                        )
                    elif query_summary_profile == "cas_u_lite":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.56)
                            + (candidate_actionability * 0.14)
                            + (temporal_persist_norm * 0.08)
                            + (backend_pressure_proxy * 0.08)
                            + (candidate_pressure_residual * 0.08)
                            + (recall_risk_norm * 0.06)
                        )
                        spill_cost_base = clamp01(
                            (stable_spill_base * 0.54)
                            + (reuse_pressure_norm * 0.18)
                            + (backend_pressure_proxy * 0.10)
                            + (candidate_pressure_residual * 0.08)
                            + (query_norm * 0.06)
                            + (temporal_persist_norm * 0.04)
                        )
                    elif query_summary_profile == "temporal_aware":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.34)
                            + (query_norm * 0.14)
                            + (temporal_persist_norm * 0.18)
                            + (temporal_evidence_norm * 0.16)
                            + (recall_dependency_norm * 0.10)
                            + (continuity_norm * 0.08)
                        )
                        spill_cost_base = clamp01(
                            (distance_norm * 0.18)
                            + (reuse_pressure_norm * 0.20)
                            + (query_norm * 0.12)
                            + (temporal_persist_norm * 0.18)
                            + (temporal_evidence_norm * 0.12)
                            + (recall_dependency_norm * 0.10)
                            + (head_budget_norm * 0.10)
                        )
                    elif query_summary_profile == "temporal_aware_v2":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.28)
                            + (query_norm * 0.12)
                            + (temporal_persist_norm * 0.22)
                            + (temporal_evidence_norm * 0.16)
                            + (recall_dependency_norm * 0.12)
                            + (distance_norm * 0.10)
                        )
                        spill_cost_base = clamp01(
                            (distance_norm * 0.20)
                            + (reuse_pressure_norm * 0.22)
                            + (query_norm * 0.10)
                            + (temporal_persist_norm * 0.18)
                            + (temporal_evidence_norm * 0.14)
                            + (recall_dependency_norm * 0.10)
                            + (head_budget_norm * 0.06)
                        )
                    elif query_summary_profile == "temporal_query_hybrid":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.24)
                            + (query_norm * 0.12)
                            + (temporal_persist_norm * 0.16)
                            + (temporal_evidence_norm * 0.12)
                            + (crossdoc_support_norm * 0.14)
                            + (segment_focus_norm * 0.12)
                            + (segment_role_norm * 0.10)
                        )
                        spill_cost_base = clamp01(
                            (distance_norm * 0.20)
                            + (reuse_pressure_norm * 0.20)
                            + (query_norm * 0.10)
                            + (temporal_persist_norm * 0.12)
                            + (crossdoc_support_norm * 0.12)
                            + (segment_focus_norm * 0.10)
                            + (segment_role_norm * 0.08)
                            + (head_budget_norm * 0.08)
                        )
                    elif query_summary_profile == "scheduler_temporal_query_hybrid_v1":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.26)
                            + (query_norm * 0.12)
                            + (temporal_persist_norm * 0.14)
                            + (temporal_evidence_norm * 0.10)
                            + (crossdoc_support_norm * 0.14)
                            + (segment_focus_norm * 0.10)
                            + (segment_role_norm * 0.08)
                            + (head_budget_norm * 0.08)
                            - ((1.0 - hybrid_selectivity_norm) * 0.08)
                        )
                        spill_cost_base = clamp01(
                            (distance_norm * 0.18)
                            + (reuse_pressure_norm * 0.20)
                            + (query_norm * 0.10)
                            + (temporal_persist_norm * 0.10)
                            + (crossdoc_support_norm * 0.10)
                            + (segment_focus_norm * 0.08)
                            + (segment_role_norm * 0.06)
                            + (head_budget_norm * 0.08)
                            - ((1.0 - hybrid_selectivity_norm) * 0.06)
                        )
                    elif query_summary_profile in ("query_structure_aware", "query_structure_decoupled"):
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.30)
                            + (query_norm * 0.14)
                            + (crossdoc_support_norm * 0.18)
                            + (segment_mass_norm * 0.12)
                            + (segment_focus_norm * 0.12)
                            + (segment_role_norm * 0.08)
                            + (continuity_norm * 0.06)
                        )
                        spill_cost_base = clamp01(
                            (distance_norm * 0.22)
                            + (reuse_pressure_norm * 0.22)
                            + (query_norm * 0.12)
                            + (crossdoc_support_norm * 0.12)
                            + (segment_focus_norm * 0.10)
                            + (segment_role_norm * 0.08)
                            + (head_budget_norm * 0.08)
                            + (backend_pressure_proxy * 0.06)
                        )
                    elif query_summary_profile == "autopareto_v1":
                        reuse_pressure_norm = clamp01(
                            (stable_reuse_pressure_norm * 0.52)
                            + (query_norm * 0.16)
                            + (recall_risk_norm * 0.10)
                            + (backend_pressure_proxy * 0.10)
                            + (head_budget_norm * 0.08)
                            + (temporal_persist_norm * 0.04)
                        )
                        spill_cost_base = clamp01(
                            (stable_spill_base * 0.48)
                            + (reuse_pressure_norm * 0.20)
                            + (backend_pressure_proxy * 0.14)
                            + (query_norm * 0.10)
                            + (recall_risk_norm * 0.08)
                        )
                    else:
                        reuse_pressure_norm = stable_reuse_pressure_norm
                        spill_cost_base = stable_spill_base
                    if query_summary_profile in ("v7_cost_v2", "rpau_v1", "rpau_reuse_v2", "qrc_v1", "autopareto_v1", "cas_u_lite"):
                        spill_cost_norm = clamp01((spill_cost_base - 0.04) / 0.84)
                    else:
                        spill_cost_norm = clamp01((spill_cost_base - 0.08) / 0.90)
                    compression_risk = cost_class_from_weight(compression_risk_norm)
                    spill_cost = cost_class_from_weight(spill_cost_norm)
                    if query_summary_profile == "cas_u_lite":
                        block_policy_select_s5 = casu_lite_block_policy_select(
                            op=KCMU_OP_RD,
                            attn_valid=1,
                            attn_score=attn_score,
                            recent_rank=min(15, recent_idx),
                            head_budget_class=head_budget_class,
                            query_relevance=query_relevance,
                            compression_risk=compression_risk,
                            spill_cost=spill_cost,
                            service_criticality=service_criticality,
                        )
                    else:
                        block_policy_select_s5 = casu_block_policy_select(
                            op=KCMU_OP_RD,
                            attn_valid=1,
                            attn_score=attn_score,
                            recent_rank=min(15, recent_idx),
                            head_budget_class=head_budget_class,
                            query_relevance=query_relevance,
                            compression_risk=compression_risk,
                            spill_cost=spill_cost,
                            service_criticality=service_criticality,
                        )
                    sig_valid, query_sig, key_sig, prefix_class, router_class = descriptor_v2_signatures(
                        dominant_seg_type=dominant_seg_type,
                        blk=blk,
                        query_norm=query_norm,
                        norm_weight=norm_weight,
                        segment_focus_norm=segment_focus_norm,
                        segment_mass_norm=segment_mass_norm,
                        crossdoc_support_norm=crossdoc_support_norm,
                        recall_dependency_norm=recall_dependency_norm,
                        temporal_persist_norm=temporal_persist_norm,
                        temporal_evidence_norm=temporal_evidence_norm,
                        recentness_norm=recentness_norm,
                        distance_norm=distance_norm,
                        head_budget_class=head_budget_class,
                    )
                    seq_history_next[history_key] = {
                        "ema_query": clamp01((query_norm * 0.60) + (prev_ema * 0.40)),
                        "ema_consensus": clamp01((consensus_norm * 0.55) + (prev_consensus * 0.45)),
                        "ema_evidence": clamp01((evidence_role_norm * 0.60) + (prev_evidence * 0.40)),
                        "ema_recall": clamp01((recall_risk_norm * 0.60) + (prev_recall * 0.40)),
                        "last_seen_step": step,
                        "streak": streak,
                    }
                    commands.append(
                        desc(
                            KCMU_OP_RD,
                            descriptor_base(seq_id, blk, kv_kind),
                            4,
                            attn_score,
                            seq_id=seq_id,
                            phase=PHASE_DECODE,
                            kv_kind=kv_kind,
                            attn_valid=1,
                            attn_score=attn_score,
                            recent_rank=min(15, recent_idx),
                            token_block_id=token_block_id(seq_id, blk, kv_kind),
                            attn_epoch=step + 1,
                            head_budget_class=head_budget_class,
                            query_relevance=query_relevance,
                            compression_risk=compression_risk,
                            spill_cost=spill_cost,
                            service_criticality=service_criticality,
                            policy_select_s5=block_policy_select_s5,
                            temporal_persist_class=temporal_persist_class,
                            reuse_distance_class=reuse_distance_class,
                            query_structure_class=query_structure_class,
                            sched_urgency_hint=sched_urgency_hint,
                            sig_valid=sig_valid,
                            query_sig=query_sig,
                            key_sig=key_sig,
                            prefix_class=prefix_class,
                            router_class=router_class,
                        )
                    )
                    seq_entry["blocks"].append(
                        {
                            "token": blk,
                            "kv_kind": kv_kind,
                            "score": weight,
                            "attn_score": attn_score,
                            "query_relevance": query_relevance,
                            "service_criticality": service_criticality,
                            "head_budget_class": head_budget_class,
                            "compression_risk": compression_risk,
                            "spill_cost": spill_cost,
                            "segment_type": dominant_seg_type,
                            "segment_role_weight": round(segment_role_norm, 4),
                            "segment_focus_norm": round(segment_focus_norm, 4),
                            "segment_mass_norm": round(segment_mass_norm, 4),
                            "crossdoc_support_norm": round(crossdoc_support_norm, 4),
                            "recall_dependency_norm": round(recall_dependency_norm, 4),
                            "sig_valid": sig_valid,
                            "query_sig": query_sig,
                            "key_sig": key_sig,
                            "prefix_class": prefix_class,
                            "router_class": router_class,
                        }
                    )
                query_history[seq_slot] = seq_history_next
            else:
                for layer_idx, attn in enumerate(attns[:n_layers]):
                    seq_attn = attn[seq_slot]
                    for head_idx in range(min(int(seq_attn.shape[0]), n_heads)):
                        vec = seq_attn[head_idx, -1, :seq_total_len]
                        top_k = min(spec.top_k_per_head, int(vec.shape[0]))
                        if top_k <= 0:
                            continue
                        vals, idxs = torch.topk(vec, k=top_k)
                        for pos, weight in zip(idxs.tolist(), vals.tolist()):
                            token = block_start(int(pos))
                            prio = bucket_prio(float(weight))
                            for kv_kind in (KV_KIND_K, KV_KIND_V):
                                commands.append(
                                    cmd(
                                        KCMU_OP_RD,
                                        legacy_addr_region(seq_slot, batch_size, n_layers, n_heads, layer_idx, head_idx, token, kv_kind),
                                        0,
                                        seq_id,
                                        PHASE_DECODE,
                                        kv_kind,
                                        layer_idx,
                                        head_idx,
                                        token,
                                        prio,
                                    )
                                )
                            seq_entry["blocks"].append({"token": token, "head": head_idx, "layer": layer_idx, "score": float(weight)})
            step_record["seqs"].append(seq_entry)
        attention_records.append(step_record)

        should_advance = not (attention_capture == "decode_only" and step >= (spec.max_new_tokens - 1))
        if should_advance:
            logits = outputs.logits[:, -1, :]
            next_ids = torch.argmax(logits, dim=-1, keepdim=True)
            next_mask = torch.ones_like(next_ids, device=device)
            for seq_slot in range(batch_size):
                generated[seq_slot].append(int(next_ids[seq_slot, 0].item()))

            with torch.no_grad():
                outputs = model(
                    input_ids=next_ids,
                    attention_mask=torch.cat([cur_mask, next_mask], dim=1),
                    past_key_values=past,
                    use_cache=True,
                    output_attentions=True,
                    return_dict=True,
                )
            past = outputs.past_key_values
            cur_mask = torch.cat([cur_mask, next_mask], dim=1)
            write_step = step if attention_capture == "prefill_and_decode" else step + 1
            append_decode_time_writes(write_step)

    selector_question_ratio, policy_select_s5 = selector_v1_full_policy(attention_records)
    kspu_v220_metrics, kspu_v220_select = kspu_epoch_selector_v220_policy(commands)
    if spec.trace_mode == "descriptor":
        per_block_policy_profiles = {
            "rpau_v1",
            "rpau_reuse_v2",
            "qsr_v1",
            "qrc_v1",
            "autopareto_v1",
            "cas_u_lite",
        }
        if query_summary_profile == "kspu_epoch_selector_v220":
            for command in commands:
                if command["op"] != KCMU_OP_RD or command["attn_valid"] == 0:
                    command["policy_select_s5"] = 0
                else:
                    command["policy_select_s5"] = kspu_v220_select
        elif query_summary_profile in per_block_policy_profiles:
            for command in commands:
                if command["op"] != KCMU_OP_RD or command["attn_valid"] == 0:
                    command["policy_select_s5"] = 0
                else:
                    command["policy_select_s5"] = int(command.get("policy_select_s5", 0))
        else:
            for command in commands:
                command["policy_select_s5"] = policy_select_s5

    runtime_meta = {
        "generator": "hf_runtime_tracegen",
        "model": getattr(model.config, "_name_or_path", "unknown"),
        "query_summary_profile": query_summary_profile,
        "attention_capture": attention_capture,
        "device": device,
        "prompts": spec.prompts,
        "batch_size": batch_size,
        "prompt_lengths": seq_prompt_lens,
        "max_new_tokens": spec.max_new_tokens,
        "top_k_per_head": spec.top_k_per_head,
        "n_layers": n_layers,
        "n_heads": n_heads,
        "trace_mode": spec.trace_mode,
        "generated_token_ids": generated,
        "generated_text": [tokenizer.decode(ids, skip_special_tokens=True) for ids in generated],
        "attention_records": attention_records,
        "selector_policy": {
            "name": "selector_v1_full_question_ratio",
            "question_ratio": round(selector_question_ratio, 6),
            "threshold": 0.285714,
            "policy_select_s5": int(policy_select_s5),
            "candidate_when_true": "haqu_rpau",
            "reference_when_false": "haqu",
        },
        "kspu_v220_selector": {
            "name": "kspu_epoch_selector_v220_workload_descriptor",
            "metrics": kspu_v220_metrics,
            "policy_select_s5": int(kspu_v220_select),
            "predicate": "reads>=128 && 62<=top10_mass<=78",
            "candidate_when_true": "kspu_recent_valid_keep_contract",
            "reference_when_false": "fpga_true_h2o_service",
        },
        "device": device,
    }
    if spec.metadata:
        runtime_meta["benchmark"] = spec.metadata
    expect = {
        "should_activate": [
            "l1_hit",
            "l2_dfill",
            "mem_wait",
            "hbm_rd_req",
            "demand_miss",
            "miss_rate_permille",
        ],
        "baseline_generated_token_ids": generated,
        "baseline_generated_text": runtime_meta["generated_text"],
        "notes": f"Trace exported from a real HuggingFace decode run using model={runtime_meta['model']}.",
    }
    if spec.metadata:
        expect["benchmark"] = spec.metadata
    return commands, payload_words, runtime_meta, expect


def build_suite(
    out_dir: Path,
    model_name: str,
    workloads: list[HFWorkloadSpec] | None = None,
    suite_meta: dict[str, Any] | None = None,
    query_summary_profile: str = "stable",
    service_criticality_profile: str = "current",
    attention_capture: str = "prefill_and_decode",
    torch_threads: int = 1,
    device: str = "cpu",
    dump_query_usefulness: bool = False,
) -> Path:
    query_summary_profile = normalize_query_summary_profile(query_summary_profile)
    model, tokenizer, device = load_model_bundle(
        model_name,
        torch_threads=torch_threads,
        device=device,
        attention_capture=attention_capture,
    )
    workloads = workloads or default_workload_specs(model_name)
    manifest = {
        "schema": "kiloware_hf_runtime_trace_manifest_v3",
        "generator": "hf_runtime_tracegen",
        "model": model_name,
        "query_summary_profile": query_summary_profile,
        "service_criticality_profile": service_criticality_profile,
        "attention_capture": attention_capture,
        "torch_threads": max(1, int(torch_threads)),
        "device": device,
        "trace_format": {
            "legacy_fields": [
                "op",
                "addr",
                "wdata",
                "meta_valid",
                "seq_id",
                "phase",
                "kv_kind",
                "layer",
                "head",
                "token",
                "prio",
            ],
            "descriptor_fields": [
                "op",
                "base_addr",
                "len",
                "score",
                "seq_id",
                "phase",
                "kv_kind",
                "attn_valid",
                "attn_score",
                "recent_rank",
                "token_block_id",
                "attn_epoch",
                "head_budget_class",
                "query_relevance",
                "compression_risk",
                "spill_cost",
                "service_criticality",
                "policy_select_s5",
                "temporal_persist_class",
                "reuse_distance_class",
                "query_structure_class",
                "sched_urgency_hint",
                "sig_valid",
                "query_sig",
                "key_sig",
                "prefix_class",
                "router_class",
            ],
            "descriptor_payload_fields": ["wdata"],
        },
        "workloads": [],
    }
    if suite_meta:
        manifest["suite_meta"] = suite_meta

    for spec in workloads:
        query_usefulness_dump: list[dict[str, float | int | str]] = []
        commands, payload_words, runtime_meta, expect = run_decode(
            model,
            tokenizer,
            device,
            spec,
            query_summary_profile=query_summary_profile,
            service_criticality_profile=service_criticality_profile,
            attention_capture=attention_capture,
            dump_query_usefulness=dump_query_usefulness,
            query_usefulness_dump=query_usefulness_dump,
        )
        meta = HFWorkloadMeta(
            name=spec.name,
            prefetch_enable=spec.prefetch_enable,
            description=spec.description,
            tags=spec.tags,
            trace_file=f"{spec.name}.trace",
            op_count=sum(c.get("len", 1) for c in commands),
            trace_mode=spec.trace_mode,
            runtime_meta_file=f"{spec.name}.runtime.json",
            expect_file=f"{spec.name}.expect.json",
            payload_file=f"{spec.name}.payload" if spec.trace_mode == "descriptor" else None,
        )
        emit_trace(out_dir / meta.trace_file, spec.name, spec.description, commands, spec.trace_mode)
        if meta.payload_file:
            emit_payload(out_dir / meta.payload_file, payload_words)
        if dump_query_usefulness:
            usefulness_path = out_dir / f"{meta.name}.query_usefulness.json"
            usefulness_path.write_text(
                json.dumps(query_usefulness_dump, indent=2),
                encoding="utf-8",
            )
        emit_json(out_dir / meta.runtime_meta_file, runtime_meta)
        emit_json(out_dir / meta.expect_file, expect)
        manifest["workloads"].append(asdict(meta))

    manifest_path = out_dir / "manifest.json"
    emit_json(manifest_path, manifest)
    return manifest_path


def build_single_export(
    out_dir: Path,
    model_name: str,
    prompts: list[str],
    max_new_tokens: int,
    top_k_per_head: int,
    name: str,
    trace_mode: str = "legacy",
    query_summary_profile: str = "stable",
    service_criticality_profile: str = "current",
    attention_capture: str = "prefill_and_decode",
    torch_threads: int = 1,
    device: str = "cpu",
    dump_query_usefulness: bool = False,
) -> Path:
    query_summary_profile = normalize_query_summary_profile(query_summary_profile)
    model, tokenizer, device = load_model_bundle(
        model_name,
        torch_threads=torch_threads,
        device=device,
        attention_capture=attention_capture,
    )
    query_usefulness_dump: list[dict[str, float | int | str]] | None = [] if dump_query_usefulness else None
    spec = HFWorkloadSpec(
        name=name,
        prompts=prompts,
        max_new_tokens=max_new_tokens,
        top_k_per_head=top_k_per_head,
        trace_mode=trace_mode,
        prefetch_enable=1,
        description=f"HuggingFace runtime-derived trace from model={model_name}",
        tags=["runtime", "hf", "single-export"],
    )
    commands, payload_words, runtime_meta, expect = run_decode(
        model,
        tokenizer,
        device,
        spec,
        query_summary_profile=query_summary_profile,
        service_criticality_profile=service_criticality_profile,
        attention_capture=attention_capture,
        dump_query_usefulness=dump_query_usefulness,
        query_usefulness_dump=query_usefulness_dump,
    )
    meta = HFWorkloadMeta(
        name=spec.name,
        prefetch_enable=1,
        description=spec.description,
        tags=spec.tags,
        trace_file=f"{spec.name}.trace",
        op_count=sum(c.get("len", 1) for c in commands),
        trace_mode=spec.trace_mode,
        runtime_meta_file=f"{spec.name}.runtime.json",
        expect_file=f"{spec.name}.expect.json",
        payload_file=f"{spec.name}.payload" if spec.trace_mode == "descriptor" else None,
    )
    emit_trace(out_dir / meta.trace_file, meta.name, meta.description, commands, spec.trace_mode)
    if meta.payload_file:
        emit_payload(out_dir / meta.payload_file, payload_words)
    if dump_query_usefulness:
        usefulness_path = out_dir / f"{meta.name}.query_usefulness.json"
        usefulness_path.write_text(
            json.dumps(query_usefulness_dump, indent=2),
            encoding="utf-8",
        )
    emit_json(out_dir / meta.runtime_meta_file, runtime_meta)
    emit_json(out_dir / meta.expect_file, expect)
    manifest_path = out_dir / "manifest.json"
    emit_json(
        manifest_path,
        {
            "schema": "kiloware_hf_runtime_trace_manifest_v2",
            "generator": "hf_runtime_tracegen",
            "model": model_name,
            "query_summary_profile": query_summary_profile,
            "service_criticality_profile": service_criticality_profile,
            "attention_capture": attention_capture,
            "torch_threads": max(1, int(torch_threads)),
            "device": device,
            "workloads": [asdict(meta)],
        },
    )
    return manifest_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Export KCMU traces from a real HuggingFace causal LM decode run.")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--model", default="sshleifer/tiny-gpt2")
    parser.add_argument(
        "--dump-query-usefulness",
        action="store_true",
        help="Dump per-block query usefulness diagnostics to JSON.",
    )
    parser.add_argument("--mode", choices=["suite", "single"], default="suite")
    parser.add_argument("--spec-file", help="JSON workload/benchmark manifest for suite mode.")
    parser.add_argument("--prompt", action="append", dest="prompts", help="Prompt text. May be specified multiple times.")
    parser.add_argument("--prompt-file", help="UTF-8 text file with one prompt per line.")
    parser.add_argument("--max-new-tokens", type=int, default=8)
    parser.add_argument("--top-k-per-head", type=int, default=2)
    parser.add_argument("--name", default="hf_runtime_export")
    parser.add_argument("--trace-mode", choices=["legacy", "descriptor"], default="legacy")
    parser.add_argument("--query-summary-profile", choices=list(QUERY_SUMMARY_PROFILES), default="stable")
    parser.add_argument("--service-criticality-profile", choices=list(SERVICE_CRITICALITY_PROFILES), default="current")
    parser.add_argument(
        "--torch-threads",
        type=int,
        default=1,
        help="CPU torch thread count for tracegen. Default 1 preserves historical runs; increase only for documented local pilots.",
    )
    parser.add_argument(
        "--device",
        choices=["cpu", "cuda", "auto"],
        default="cpu",
        help="Device for model execution. Default cpu preserves historical runs; use auto/cuda on a suitable GPU host.",
    )
    parser.add_argument(
        "--attention-capture",
        choices=["prefill_and_decode", "decode_only"],
        default="prefill_and_decode",
        help=(
            "prefill_and_decode preserves the historical tracegen behavior and captures full prefill attentions; "
            "decode_only captures attentions only from real cached decode steps to avoid O(prompt^2) prefill attention tensors."
        ),
    )
    args = parser.parse_args()

    if not HF_AVAILABLE:
        fail_missing_deps()

    torch.manual_seed(0)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.mode == "suite":
        workloads = None
        suite_meta = None
        if args.spec_file:
            workloads, suite_meta = load_workload_specs_from_manifest(Path(args.spec_file))
        manifest_path = build_suite(
            out_dir,
            args.model,
            workloads=workloads,
            suite_meta=suite_meta,
            query_summary_profile=args.query_summary_profile,
            service_criticality_profile=args.service_criticality_profile,
            attention_capture=args.attention_capture,
            torch_threads=args.torch_threads,
            device=args.device,
            dump_query_usefulness=args.dump_query_usefulness,
        )
    else:
        prompts: list[str] = []
        if args.prompt_file:
            prompt_file = Path(args.prompt_file)
            prompts.extend([line.strip() for line in prompt_file.read_text(encoding="utf-8").splitlines() if line.strip()])
        if args.prompts:
            prompts.extend([p for p in args.prompts if p.strip()])
        if not prompts:
            prompts = ["The KiloWare controller manages KV cache traffic efficiently."]
        manifest_path = build_single_export(
            out_dir=out_dir,
            model_name=args.model,
            prompts=prompts,
            max_new_tokens=args.max_new_tokens,
            top_k_per_head=args.top_k_per_head,
            name=args.name,
            trace_mode=args.trace_mode,
            query_summary_profile=args.query_summary_profile,
            service_criticality_profile=args.service_criticality_profile,
            attention_capture=args.attention_capture,
            torch_threads=args.torch_threads,
            device=args.device,
            dump_query_usefulness=args.dump_query_usefulness,
        )

    print(f"HF_RUNTIME_MANIFEST={manifest_path}")


if __name__ == "__main__":
    main()


