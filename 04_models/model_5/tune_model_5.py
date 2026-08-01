"""
tune_model_5.py - measure the collaborative filtering grid, then choose.

Run model_5.sql first. This script only reads.

Two parameters, so this is a grid: support floor (co_raters) on the outside,
jaccard on the inside. Train only.

Usage:
    /opt/anaconda3/bin/python3 tune_model_5.py
"""

import sys
import pathlib

import pandas as pd
import matplotlib.pyplot as plt

sys.path.append(str(pathlib.Path(__file__).parent.parent))  # model_utils lives one level up

from model_utils import BASELINES, SimilarityModel, run_query

# 1 is the "no floor" case. The comparison against it justifies having a floor.
SUPPORT_FLOORS = [1, 2, 3, 4, 5]

# Jaccard over at most 35 raters, so real values sit low.
JACCARD_THRESHOLDS = [0.02, 0.05, 0.10, 0.15, 0.20, 0.30, 0.50]

# Credibility floor. Lower than the metadata models' 100 because coverage here
# is structurally limited to the 1,810 personally ranked movies.
MIN_LABELLED_PAIRS = 50


def candidate_sql(min_co_raters):
    return f"""
        SELECT movie_id_1, movie_id_2, jaccard
        FROM model_5_candidates
        WHERE co_raters >= {min_co_raters}
    """


def grid(split="train"):
    frames = []
    for floor in SUPPORT_FLOORS:
        model = SimilarityModel(
            name=f"co_raters >= {floor}",
            sql=candidate_sql(floor),
            score_col="jaccard",
        )
        curve = model.curve(split=split, thresholds=JACCARD_THRESHOLDS)
        if curve.empty:
            continue
        curve.insert(0, "co_raters", floor)
        frames.append(curve)

    if not frames:
        raise SystemExit("No cell produced a labelled pair. Check model_5.sql ran.")
    return pd.concat(frames, ignore_index=True)


def plot_grid(g, path, split="train"):
    """One figure, not one per floor. The floor comparison is the actual
    decision, so it belongs on the same axes."""
    fig, ax = plt.subplots(figsize=(9, 5))
    for floor, part in g.groupby("co_raters"):
        part = part.sort_values("threshold")
        ax.plot(part["threshold"], part["precision"], marker="o",
                label=f"co_raters >= {int(floor)}")
    ax.axhline(BASELINES[split], ls="--", color="red",
               label=f"Baseline {BASELINES[split]:.1%}")
    ax.set(xlabel="Jaccard threshold", ylabel="Precision",
           title=f"Model 5 - Collaborative Filtering, {split}")
    ax.legend(loc="lower right", fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    return path


def report(g, split):
    print(f"\n=== Model 5, Collaborative Filtering - {split.upper()} ===")
    print(f"Baseline to beat: {BASELINES[split]:.1%}\n")
    shown = g.copy()
    shown["precision"] = (shown["precision"] * 100).round(1)
    shown["recall"] = (shown["recall"] * 100).round(1)
    print(shown[["co_raters", "threshold", "pairs_returned", "pairs_scored",
                 "good", "precision", "recall"]].to_string(index=False))

    credible = g[g["pairs_scored"] >= MIN_LABELLED_PAIRS]
    if credible.empty:
        print(f"\nNo cell has {MIN_LABELLED_PAIRS}+ labelled pairs.")
        return None

    best = credible.loc[credible["precision"].idxmax()]
    print(f"\nNumerical maximum: co_raters >= {int(best['co_raters'])}, "
          f"jaccard >= {best['threshold']}, precision {best['precision']:.1%} "
          f"on {int(best['pairs_scored'])} labelled pairs."
          f"\nNot automatically the right cell - see README.md.")
    return best


def floor_comparison(g, jaccard_cutoff):
    """Every floor at one jaccard cutoff. If floor 1 matches the rest, the
    floor is unjustified and should be dropped."""
    same = g[g["threshold"] == jaccard_cutoff].sort_values("co_raters")
    print(f"\n=== Why a support floor - all floors at jaccard >= {jaccard_cutoff} ===")
    for _, r in same.iterrows():
        print(f"  co_raters >= {int(r['co_raters'])}: precision {r['precision']:.1%}, "
              f"{int(r['pairs_scored'])} labelled, {int(r['pairs_returned'])} returned")


def data_quality_contribution():
    """Model 5 is the only model reading personal_movies_ranking, so the step
    04 duplicate filter can only show up here."""
    sql = """
        SELECT 'clean' AS variant,
               COUNT(DISTINCT CONCAT(movie_id, '-', suggested_by)) AS liked_pairs,
               COUNT(DISTINCT movie_id) AS liked_movies,
               COUNT(*) AS rows_read
        FROM personal_movies_ranking
        WHERE recommendation > 5
        UNION ALL
        SELECT 'raw',
               COUNT(DISTINCT CONCAT(movie_id, '-', suggested_by)),
               COUNT(DISTINCT movie_id),
               COUNT(*)
        FROM personal_movies_ranking_raw
        WHERE recommendation > 5
    """
    print("\n=== Data quality layer ===")
    print(run_query(sql).to_string(index=False))
    print("rows_read should differ, liked_pairs should not - the duplicates were"
          "\nexact, so DISTINCT absorbs them.")


def main():
    g = grid(split="train")
    g.to_csv("grid_train.csv", index=False)
    report(g, "train")
    floor_comparison(g, 0.50)
    data_quality_contribution()
    print("\nsaved:", plot_grid(g, "curve_grid.png"))


if __name__ == "__main__":
    main()
