"""Regenerate final 32/32 evaluation figures from locked CSVs.

This script only redraws existing paper figures from supplied result CSVs.
It does not recompute or change experimental values.
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

import matplotlib as mpl

mpl.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.lines import Line2D
from matplotlib.patches import Patch


ROOT = Path(__file__).resolve().parents[2]
FIGS = ROOT / "paper_figures"
SRC = ROOT / "scripts" / "paper_figures"

BLUE = "#0072B2"
ORANGE = "#E69F00"
GREEN = "#009E73"
DARK = "#1F1F1F"
GRAY = "#6F6F6F"
LIGHT = "#D9D9D9"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def f(row: dict[str, str], key: str) -> float:
    return float(row[key])


def clean(ax: plt.Axes, grid_axis: str = "y") -> None:
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_color(DARK)
    ax.spines["bottom"].set_color(DARK)
    ax.tick_params(colors=DARK, labelcolor=DARK, pad=1.1)
    if grid_axis:
        ax.grid(axis=grid_axis, color="#E8E8E8", linewidth=0.55, zorder=0)


def save(fig: plt.Figure, name: str) -> None:
    (FIGS / "pdf").mkdir(parents=True, exist_ok=True)
    (FIGS / "png").mkdir(parents=True, exist_ok=True)
    fig.savefig(FIGS / "pdf" / f"{name}.pdf", bbox_inches="tight", pad_inches=0.02)
    fig.savefig(FIGS / "png" / f"{name}.png", dpi=600, bbox_inches="tight", pad_inches=0.02)
    plt.close(fig)


def init_style() -> None:
    mpl.rcParams.update(
        {
            "font.family": "Arial",
            "font.size": 7.4,
            "axes.labelsize": 7.8,
            "axes.titlesize": 7.8,
            "xtick.labelsize": 7.0,
            "ytick.labelsize": 7.0,
            "legend.fontsize": 6.4,
            "axes.linewidth": 0.8,
            "xtick.major.width": 0.75,
            "ytick.major.width": 0.75,
            "xtick.major.size": 2.7,
            "ytick.major.size": 2.7,
            "lines.linewidth": 1.35,
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
        }
    )


def build_context_rates() -> None:
    rows = read_csv(SRC / "F32_context_summary.csv")
    x = np.arange(len(rows))
    labels = [r["context"] for r in rows]

    fig, axes = plt.subplots(1, 2, figsize=(3.35, 1.55), constrained_layout=True, sharex=True)
    for ax in axes:
        clean(ax)
        ax.set_xticks(x)
        ax.set_xticklabels(labels)
        ax.set_xlabel("Prompt context")
        ax.set_ylim(0, 76)
        ax.set_yticks([0, 25, 50, 75])

    axes[0].plot(
        x,
        [f(r, "base_l1_hit_pct") for r in rows],
        color=GRAY,
        marker="o",
        markerfacecolor="white",
        markeredgewidth=1.05,
        label="Baseline",
    )
    axes[0].plot(
        x,
        [f(r, "kw_l1_hit_pct") for r in rows],
        color=BLUE,
        marker="o",
        markerfacecolor="white",
        markeredgewidth=1.05,
        label="KiloWare",
    )
    axes[0].set_ylabel("L1 hit rate (%)")
    axes[0].set_title("L1 hit", pad=3.0)

    axes[1].plot(
        x,
        [f(r, "base_hier_miss_pct") for r in rows],
        color=DARK,
        marker="s",
        markerfacecolor="white",
        markeredgewidth=1.1,
        linestyle="--",
        label="Baseline",
    )
    axes[1].plot(
        x,
        [f(r, "kw_hier_miss_pct") for r in rows],
        color=GREEN,
        marker="s",
        markerfacecolor="white",
        markeredgewidth=1.05,
        linestyle="--",
        label="KiloWare",
    )
    axes[1].set_ylabel("Hierarchy miss (%)")
    axes[1].set_title("Hierarchy miss", pad=3.0)

    for ax in axes:
        ax.legend(
            loc="upper center",
            bbox_to_anchor=(0.5, 1.34),
            ncol=2,
            frameon=False,
            handlelength=1.0,
            columnspacing=0.75,
            borderaxespad=0.0,
        )

    save(fig, "F32-context-rates")


def build_size_sweep() -> None:
    rows = read_csv(SRC / "F32_size_sweep.csv")
    x = np.arange(len(rows))
    width = 0.34
    base_miss = [f(r, "base_hier_miss_pct") for r in rows]
    kw_miss = [f(r, "kw_hier_miss_pct") for r in rows]
    latency = [f(r, "latency_gain_pct") for r in rows]

    fig, ax = plt.subplots(figsize=(3.35, 1.52), constrained_layout=True)
    clean(ax)
    ax.bar(
        x - width / 2,
        base_miss,
        width=width,
        color=LIGHT,
        edgecolor=DARK,
        linewidth=0.7,
        hatch="////",
        label="Baseline",
        zorder=3,
    )
    ax.bar(
        x + width / 2,
        kw_miss,
        width=width,
        color=BLUE,
        edgecolor=DARK,
        linewidth=0.45,
        label="KiloWare",
        zorder=3,
    )
    ax.set_xticks(x)
    ax.set_xticklabels([r["size"] for r in rows], rotation=25, ha="right")
    ax.set_ylabel("Hierarchy\nmiss (%)")
    ax.set_xlabel("L1/L2 capacity (lines)")
    ax.set_ylim(0, 75)
    ax.set_yticks([0, 25, 50, 75])

    ax2 = ax.twinx()
    ax2.plot(
        x,
        latency,
        color=ORANGE,
        marker="D",
        markersize=3.5,
        markerfacecolor="white",
        markeredgewidth=1.1,
        linewidth=1.25,
        label="Latency gain",
    )
    ax2.set_ylim(0, 3.0)
    ax2.set_yticks([0, 1, 2, 3])
    ax2.set_ylabel("Latency\ngain (%)", color=ORANGE)
    ax2.tick_params(axis="y", colors=ORANGE, labelsize=7.0, pad=1.0)
    ax2.spines["top"].set_visible(False)
    ax2.spines["right"].set_color(ORANGE)

    selected_idx = [r["size"] for r in rows].index("32/32")
    ax.scatter(
        [selected_idx],
        [kw_miss[selected_idx]],
        marker="*",
        s=140,
        color="#D62728",
        edgecolor=DARK,
        linewidth=0.55,
        zorder=6,
    )
    legend_handles = [
        Patch(facecolor=LIGHT, edgecolor=DARK, hatch="////", linewidth=0.7, label="Baseline"),
        Patch(facecolor=BLUE, edgecolor=DARK, linewidth=0.45, label="KiloWare"),
        Line2D(
            [0],
            [0],
            color=ORANGE,
            marker="D",
            markerfacecolor="white",
            markeredgewidth=1.1,
            linewidth=1.25,
            markersize=3.5,
            label="Latency gain",
        ),
    ]
    ax.legend(
        legend_handles,
        [h.get_label() for h in legend_handles],
        loc="upper center",
        bbox_to_anchor=(0.5, 1.25),
        ncol=3,
        frameon=False,
        handlelength=1.2,
        columnspacing=0.65,
        borderaxespad=0.0,
    )
    save(fig, "F32-size-sweep")


def main() -> None:
    init_style()
    build_context_rates()
    build_size_sweep()


if __name__ == "__main__":
    main()
