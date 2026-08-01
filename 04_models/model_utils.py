"""
model_utils.py - shared tools for the similarity models.

Contract: every model returns candidate pairs as
movie_id_1, movie_id_2, and one score column to threshold on.

Thresholds are tuned on train only. Tuning on test leaks the answers.
"""

import os

import pandas as pd
import matplotlib.pyplot as plt
from sqlalchemy import create_engine

# Credentials come from the environment so nothing is hardcoded here.
# Set MYSQL_USER, MYSQL_PASSWORD, MYSQL_HOST, MYSQL_DB to override.
USER = os.environ.get("MYSQL_USER", "root")
PASSWORD = os.environ.get("MYSQL_PASSWORD", "")
HOST = os.environ.get("MYSQL_HOST", "localhost")
DB = os.environ.get("MYSQL_DB", "imdb_ijs")

ENGINE = create_engine(f"mysql+mysqlconnector://{USER}:{PASSWORD}@{HOST}/{DB}")

# Baseline: a model that calls every pair good. Measured, see 02_ground_truth/README.md
BASELINES = {"train": 0.513, "test": 0.491}

# movies_recommendations_agg is the 2026 test set despite its name.
# It arrives already aggregated. See 02_ground_truth/README.md.
GROUND_TRUTH_TABLES = {"train": "gt_pairs_train", "test": "movies_recommendations_agg"}


def run_query(sql):
    """Run SQL and return a DataFrame. Read only."""
    return pd.read_sql(sql, ENGINE)


class SimilarityModel:
    """One model: a candidate query, tuned against the ground truth."""

    def __init__(self, name, sql, score_col):
        self.name = name
        self.sql = sql
        self.score_col = score_col
        self._candidates = None
        self._ground_truth = {}

    @property
    def candidates(self):
        """Candidate pairs, fetched once and cached."""
        if self._candidates is None:
            self._candidates = run_query(self.sql)
        return self._candidates

    def ground_truth(self, split="train"):
        """Labelled pairs. The > 5 cutoff is fixed by the confusion matrix."""
        if split not in self._ground_truth:
            gt = run_query(f"""
                SELECT base_movie_id,
                       recommended_movie_id,
                       recommendation
                FROM {GROUND_TRUTH_TABLES[split]}
            """)
            gt["is_good"] = gt["recommendation"] > 5
            self._ground_truth[split] = gt
        return self._ground_truth[split]

    def curve(self, split="train", thresholds=None):
        """
        Precision and recall at each threshold.
        pairs_returned is the full output; pairs_scored is the labelled
        subset that precision is actually measured on.
        """
        gt = self.ground_truth(split)
        total_good = int(gt["is_good"].sum())
        scored = gt.merge(
            self.candidates,
            left_on=["base_movie_id", "recommended_movie_id"],
            right_on=["movie_id_1", "movie_id_2"],
            how="inner",
        )

        rows = []
        for t in thresholds or sorted(self.candidates[self.score_col].unique()):
            hits = scored[scored[self.score_col] >= t]
            if len(hits) == 0:
                break  # nothing left to measure
            good = int(hits["is_good"].sum())
            rows.append({
                "threshold": t,
                "pairs_returned": int((self.candidates[self.score_col] >= t).sum()),
                "pairs_scored": len(hits),
                "good": good,
                "precision": good / len(hits),
                "recall": good / total_good,
            })
        return pd.DataFrame(rows)

    def plot(self, curve, path, split="train"):
        """Precision left, volume right. High precision over three pairs is worthless."""
        fig, ax = plt.subplots(figsize=(9, 5))
        ax.plot(curve["threshold"], curve["precision"], marker="o", label="Precision")
        ax.axhline(BASELINES[split], ls="--", color="red",
                   label=f"Baseline {BASELINES[split]:.1%}")
        ax.set(xlabel=f"Threshold on {self.score_col}", ylabel="Precision",
               title=f"{self.name} - {split}")
        ax.legend(loc="lower left")

        ax2 = ax.twinx()
        ax2.plot(curve["threshold"], curve["pairs_scored"], color="grey", alpha=0.4)
        ax2.set(ylabel="Labelled pairs remaining", yscale="log")

        fig.tight_layout()
        fig.savefig(path, dpi=150)
        return path
