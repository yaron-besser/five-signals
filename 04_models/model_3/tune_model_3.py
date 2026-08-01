"""
tune_model_3.py - measure the Director Genre DNA curve, then choose p.

Run model_3.sql first. This script only reads.

One tunable parameter: p, the minimum Laplace probability. The minimum films
per director is a hard pre-filter set by reasoning and is not swept.

Usage:
    /opt/anaconda3/bin/python3 tune_model_3.py
"""

import sys
import pathlib

import matplotlib.pyplot as plt

sys.path.append(str(pathlib.Path(__file__).parent.parent))  # model_utils lives one level up

from model_utils import BASELINES, SimilarityModel, run_query

# Observed dna_strength range is 0.031 to 0.474. A 3-film director working in
# one genre only reaches (3+1)/(3+21) = 0.167, so the useful range sits low.
P_THRESHOLDS = [0.05, 0.08, 0.10, 0.12, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40]

MIN_LABELLED_PAIRS = 100

CANDIDATE_SQL = """
SELECT movie_id_1,
       movie_id_2,
       dna_strength
FROM model_3_candidates
"""


def plot_curve(curve, path, split="train"):
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(curve["threshold"], curve["precision"], marker="o", label="Precision")
    ax.axhline(BASELINES[split], ls="--", color="red",
               label=f"Baseline {BASELINES[split]:.1%}")
    ax.set(xlabel="Minimum Laplace probability (p)", ylabel="Precision",
           title=f"Model 3 - Director Genre DNA, {split}")
    ax.legend(loc="lower left")

    ax2 = ax.twinx()  # high precision over a handful of pairs is worthless
    ax2.plot(curve["threshold"], curve["pairs_scored"], color="grey", alpha=0.4)
    ax2.set(ylabel="Labelled pairs remaining", yscale="log")

    fig.tight_layout()
    fig.savefig(path, dpi=150)
    return path


def genre_dna_examples():
    """Sanity check the signal: the strongest director-genre pairs should look
    like real specialists, not artefacts of a short filmography."""
    sql = """
        SELECT CONCAT(d.first_name, ' ', d.last_name) AS director,
               dg.genre AS genre,
               dg.films_in_genre AS films_in_genre,
               dg.total_films AS total_films,
               ROUND(dg.laplace_prob, 4) AS laplace_prob
        FROM model_3_director_genre AS dg
        JOIN gs_directors AS d ON d.id = dg.director_id
        ORDER BY dg.laplace_prob DESC
        LIMIT 12
    """
    print("\n=== Strongest director-genre signatures ===")
    print(run_query(sql).to_string(index=False))


def main():
    model = SimilarityModel(
        name="Model 3 - Director Genre DNA",
        sql=CANDIDATE_SQL,
        score_col="dna_strength",
    )
    curve = model.curve(split="train", thresholds=P_THRESHOLDS)
    curve.to_csv("curve_train.csv", index=False)

    print(f"\n=== Model 3, Director Genre DNA - TRAIN ===")
    print(f"candidate pairs: {len(model.candidates):,}")
    print(f"baseline to beat: {BASELINES['train']:.1%}\n")
    shown = curve.copy()
    shown["precision"] = (shown["precision"] * 100).round(1)
    shown["recall"] = (shown["recall"] * 100).round(1)
    print(shown[["threshold", "pairs_returned", "pairs_scored", "good",
                 "precision", "recall"]].to_string(index=False))

    credible = curve[curve["pairs_scored"] >= MIN_LABELLED_PAIRS]
    if not credible.empty:
        best = credible.loc[credible["precision"].idxmax()]
        print(f"\nNumerical maximum on {MIN_LABELLED_PAIRS}+ labelled pairs: "
              f"p >= {best['threshold']}, precision {best['precision']:.1%} "
              f"on {int(best['pairs_scored'])} labelled pairs."
              f"\nNot automatically the right cell - the elbow argument goes in README.md.")

    genre_dna_examples()
    print("\nsaved:", plot_curve(curve, "curve_train.png"))


if __name__ == "__main__":
    main()
