"""
common_cast.py - Model 2: Common Cast Members.

Two movies are similar if they share at least k actors. Tunes k on train.

Runs twice: once on the raw cast, once on the credited cast built by
build_credited_roles.sql. The gap between the two curves is what
the data quality layer bought.

Both directions of every pair are produced: the ground truth is directed,
and a symmetric model emitting only (A,B) would miss every (B,A) label.
"""

import sys, pathlib
sys.path.append(str(pathlib.Path(__file__).parent.parent))  # model_utils lives one level up

from model_utils import SimilarityModel, BASELINES

COMMON_CAST_SQL = """
SELECT gr1.movie_id AS movie_id_1,
       gr2.movie_id AS movie_id_2,
       COUNT(DISTINCT gr1.actor_id) AS common_actors  -- an actor with two roles in one film counts once
FROM {table} AS gr1
JOIN {table} AS gr2
    ON gr1.actor_id = gr2.actor_id
    AND gr1.movie_id <> gr2.movie_id  -- <> not < : emits both directions
GROUP BY gr1.movie_id, gr2.movie_id
"""

CAST_TABLES = {
    "raw": "gs_roles",
    "credited": "gs_roles_credited",
}

if __name__ == "__main__":
    for label, table in CAST_TABLES.items():
        model = SimilarityModel(
            name=f"Model 2 - Common Cast ({label})",
            sql=COMMON_CAST_SQL.format(table=table),
            score_col="common_actors",
        )
        curve = model.curve(split="train")

        print(f"\n=== {model.name} ===")
        print(f"candidate pairs at k=1: {len(model.candidates):,}")
        print(f"baseline to beat: {BASELINES['train']:.1%}")
        print(curve.to_string(index=False, float_format="{:.3f}".format))

        print("saved:", model.plot(curve, f"curve_{label}.png"))
