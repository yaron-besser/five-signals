"""
tune_model_1.py - measure the Style & Era grid, then choose.

Run model_1.sql first. This script only reads.

Two parameters, so this is a grid: year window on the outside, shared genres
on the inside. Train only.

Usage:
    /opt/anaconda3/bin/python3 tune_model_1.py
"""

import sys
import pathlib

import pandas as pd
import matplotlib.pyplot as plt

sys.path.append(str(pathlib.Path(__file__).parent.parent))  # model_utils lives one level up

from model_utils import BASELINES, SimilarityModel, run_query

YEAR_WINDOWS = [2, 5, 10, 15, 20]

# Volume collapses above 4 shared genres - 462 pairs at 5, 36 at 6 - so every
# cell above 4 sits far below the credibility floor. Observed maximum is 10.
GENRE_THRESHOLDS = [1, 2, 3, 4]

# Credibility floor. Precision over a handful of labelled pairs is noise.
MIN_LABELLED_PAIRS = 100


def candidate_sql(max_year_gap):
    return f"""
        SELECT movie_id_1, movie_id_2, shared_genres
        FROM model_1_candidates
        WHERE year_gap <= {max_year_gap}
    """


def grid(split="train"):
    frames = []
    for window in YEAR_WINDOWS:
        model = SimilarityModel(
            name=f"year_gap <= {window}",
            sql=candidate_sql(window),
            score_col="shared_genres",
        )
        curve = model.curve(split=split, thresholds=GENRE_THRESHOLDS)
        if curve.empty:
            continue
        curve.insert(0, "year_gap", window)
        frames.append(curve)

    if not frames:
        raise SystemExit("No cell produced a labelled pair. Check model_1.sql ran.")
    return pd.concat(frames, ignore_index=True)


def plot_grid(g, path, split="train"):
    """One figure, not one per window. The window comparison is the finding -
    the lines sit on top of each other, which is the point."""
    fig, ax = plt.subplots(figsize=(9, 5))
    for window, part in g.groupby("year_gap"):
        part = part.sort_values("threshold")
        ax.plot(part["threshold"], part["precision"], marker="o",
                label=f"year_gap <= {int(window)}")
    ax.axhline(BASELINES[split], ls="--", color="red",
               label=f"Baseline {BASELINES[split]:.1%}")
    ax.set(xlabel="Minimum shared genres", ylabel="Precision",
           title=f"Model 1 - Style & Era, {split}")
    ax.legend(loc="lower right", fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    return path


def report(g, split):
    print(f"\n=== Model 1, Style & Era - {split.upper()} ===")
    print(f"Baseline to beat: {BASELINES[split]:.1%}\n")
    shown = g.copy()
    shown["precision"] = (shown["precision"] * 100).round(1)
    shown["recall"] = (shown["recall"] * 100).round(1)
    print(shown[["year_gap", "threshold", "pairs_returned", "pairs_scored",
                 "good", "precision", "recall"]].to_string(index=False))

    credible = g[g["pairs_scored"] >= MIN_LABELLED_PAIRS]
    if credible.empty:
        print(f"\nNo cell has {MIN_LABELLED_PAIRS}+ labelled pairs.")
        return None

    best = credible.loc[credible["precision"].idxmax()]
    print(f"\nNumerical maximum: year_gap <= {int(best['year_gap'])}, "
          f"shared_genres >= {int(best['threshold'])}, "
          f"precision {best['precision']:.1%} on {int(best['pairs_scored'])} labelled pairs.")
    return best


def window_comparison(g, genre_threshold):
    """Every window at one genre threshold. If precision is flat, the year
    parameter is inert and the report has to say so."""
    same = g[g["threshold"] == genre_threshold].sort_values("year_gap")
    print(f"\n=== Does the year window do anything - at shared_genres >= {genre_threshold} ===")
    for _, r in same.iterrows():
        print(f"  year_gap <= {int(r['year_gap']):>2}: precision {r['precision']:.1%}, "
              f"{int(r['pairs_scored'])} labelled, {int(r['pairs_returned'])} returned")


def seed_row_check(genre_threshold, year_gap):
    """Finding 6: 924 train pairs come from one rater and one film series.
    Those films share genre and era by construction, so this model fires on
    them mechanically. Both numbers get reported."""
    sql = f"""
        SELECT 'all train pairs' AS population,
               COUNT(*) AS labelled,
               SUM(g.recommendation > 5) AS good
        FROM model_1_candidates AS c
        JOIN gt_pairs_train AS g
            ON g.base_movie_id = c.movie_id_1
            AND g.recommended_movie_id = c.movie_id_2
        WHERE c.shared_genres >= {genre_threshold}
            AND c.year_gap <= {year_gap}
        UNION ALL
        SELECT 'seed rows excluded',
               COUNT(*),
               SUM(g.recommendation > 5)
        FROM model_1_candidates AS c
        JOIN gt_pairs_train AS g
            ON g.base_movie_id = c.movie_id_1
            AND g.recommended_movie_id = c.movie_id_2
        WHERE c.shared_genres >= {genre_threshold}
            AND c.year_gap <= {year_gap}
            AND g.suggested_by <> 'seed'
    """
    print("\n=== Seed rows (Finding 6) ===")
    print(run_query(sql).to_string(index=False))


def main():
    g = grid(split="train")
    g.to_csv("grid_train.csv", index=False)
    report(g, "train")
    window_comparison(g, 3)
    print("\nsaved:", plot_grid(g, "curve_grid.png"))


if __name__ == "__main__":
    main()
