"""
five_signals_analysis.py

Final project, Databases for Data Analytics, Reichman University, 2026B
Team: five_signals
Yaron Besser (324943109), Nevo Alani (322815820)

The measurement half of the project. five_signals_models.sql builds the
tables; this file reads them and produces every number in the report.

HOW TO RUN
    pip install -r requirements.txt
    MYSQL_PASSWORD=yourpassword python3 five_signals_analysis.py

    Credentials come from the environment: MYSQL_USER, MYSQL_PASSWORD,
    MYSQL_HOST, MYSQL_DB. They default to root on localhost against imdb_ijs
    with no password.

    Three packages are needed: pandas, sqlalchemy, and mysql-connector-python
    for the driver. If any is missing this file says so and stops, rather than
    failing on an import line. Run five_signals_models.sql first. This file
    only reads, it creates nothing and changes nothing. Takes about ten
    seconds.

WHAT IT PRINTS
    0  Setup and the two baselines
    1  Model 1, the year window by shared genre grid
    2  Model 2, raw cast against credited cast
    3  Model 3, the Laplace probability curve
    4  Model 4, the curated list against two controls
    5  Model 5, the support floor by Jaccard grid
    6  The aggregation, threshold curve on train and on test
    7  The final table: precision, recall and F1 for all six, both splits

HOW PRECISION IS COUNTED
    A pair counts as an error only when the class rated it 5 or below. Pairs
    the class never rated leave the denominator, because unrated is unknown
    rather than wrong. The course confusion matrix counts unrated pairs as
    errors, which is why it prints 25.3% where this file prints 82.4%. Both
    describe the same 776 pairs and the same 196 correct ones.

ON THE SPLITS
    Train is the 2025 class, in gt_pairs_train. Test is the 2026 class, in
    movies_recommendations_agg. Every threshold was tuned on train. Test was
    measured once, after all five models were locked.

FIGURES
    The five figures in the report came from the per model scripts in the
    repository. Set MAKE_FIGURES = True below to regenerate them here.
"""

import os
import sys

try:
    import pandas as pd
    from sqlalchemy import create_engine, inspect
    import mysql.connector  # noqa: F401  the driver SQLAlchemy will use
except ImportError as missing:
    sys.exit(
        f"\nMissing package: {missing.name}\n\n"
        "This file needs three packages. Install them with:\n"
        "    pip install -r requirements.txt\n"
        "or directly:\n"
        "    pip install pandas sqlalchemy mysql-connector-python\n\n"
        f"The interpreter being used is:\n    {sys.executable}\n"
        "If that is not the Python you installed the packages into, run this\n"
        "file with the one that is.\n"
    )

# Override with environment variables if your credentials differ:
#   MYSQL_USER, MYSQL_PASSWORD, MYSQL_HOST, MYSQL_DB
USER = os.environ.get("MYSQL_USER", "root")
PASSWORD = os.environ.get("MYSQL_PASSWORD", "")
HOST = os.environ.get("MYSQL_HOST", "localhost")
DB = os.environ.get("MYSQL_DB", "imdb_ijs")

ENGINE = create_engine(f"mysql+mysqlconnector://{USER}:{PASSWORD}@{HOST}/{DB}")

MAKE_FIGURES = False

# A model that calls every pair good. Measured, not assumed.
BASELINES = {"train": 0.513, "test": 0.491}

# movies_recommendations_agg comes from the course files, so everyone has it.
# gt_pairs_train is the 2025 ground truth we built ourselves, and it is not
# part of the course pipeline. If it is absent, every train figure is skipped
# and the file still runs end to end on test alone.
GROUND_TRUTH = {"train": "gt_pairs_train", "test": "movies_recommendations_agg"}

try:
    SPLITS = [s for s in ("train", "test")
              if inspect(ENGINE).has_table(GROUND_TRUTH[s])]
except Exception as err:
    sys.exit(
        f"\nCannot reach the database at {HOST}, schema {DB}, as user {USER}.\n\n"
        "Set the credentials in the environment, for example:\n"
        "    MYSQL_PASSWORD=yourpassword python3 five_signals_analysis.py\n"
        "Available: MYSQL_USER, MYSQL_PASSWORD, MYSQL_HOST, MYSQL_DB.\n\n"
        f"The server said:\n    {str(err).splitlines()[0]}\n"
    )
if not SPLITS:
    sys.exit("\nNo ground truth table found in schema " + DB + ".\n"
             "Run the four course files, then five_signals_models.sql.\n")

# Precision over a handful of labelled pairs is noise, not evidence.
MIN_LABELLED_PAIRS = 100


# ============================================================
# SECTION 0 - SHARED MACHINERY
# ============================================================

def run(sql):
    """Run SQL, return a DataFrame. Read only."""
    return pd.read_sql(sql, ENGINE)


def positives(split):
    """How many good pairs exist in this split. The recall denominator."""
    t = GROUND_TRUTH[split]
    return int(run(f"SELECT SUM(recommendation > 5) AS n FROM {t}")["n"][0])


def score(candidate_sql, split):
    """
    Precision, recall and F1 for one candidate query against one split.

    labelled is the pairs the class rated, correct is those it rated good.
    F1 comes from the raw counts, not from the rounded percentages:
        F1 = 2 * correct / (labelled + positives)
    """
    t = GROUND_TRUTH[split]
    row = run(f"""
        SELECT COUNT(*) AS labelled,
               SUM(g.recommendation > 5) AS correct
        FROM ({candidate_sql}) AS c
        JOIN {t} AS g
            ON g.base_movie_id = c.movie_id_1
            AND g.recommended_movie_id = c.movie_id_2
    """).iloc[0]
    labelled = int(row["labelled"])
    if labelled == 0:
        return None
    correct = int(row["correct"])
    pos = positives(split)
    return {
        "split": split,
        "labelled": labelled,
        "correct": correct,
        "precision": 100 * correct / labelled,
        "recall": 100 * correct / pos,
        "f1": 100 * 2 * correct / (labelled + pos),
    }


def volume(candidate_sql):
    """Total pairs returned, labelled or not."""
    return int(run(f"SELECT COUNT(*) AS n FROM ({candidate_sql}) AS c")["n"][0])


def show(title, rows, cols):
    print(f"\n=== {title} ===")
    print(pd.DataFrame(rows)[cols].to_string(index=False))


# ============================================================
# SECTION 1 - MODEL 1: STYLE & ERA
#
# Two parameters, so this is a grid. Year window on the outside, shared
# genres on the inside. The finding is that the window does nothing.
# ============================================================

YEAR_WINDOWS = [2, 5, 10, 15, 20]

# Volume collapses above 4 shared genres, so higher cells sit below the
# credibility floor. Observed maximum is 10.
GENRE_THRESHOLDS = [1, 2, 3, 4]


def model_1_sql(genres, years):
    return f"""
        SELECT movie_id_1, movie_id_2
        FROM model_1_candidates
        WHERE shared_genres >= {genres}
            AND year_gap <= {years}
    """


def section_1():
    if "train" not in SPLITS:
        print("\n=== MODEL 1, Style & Era - skipped, gt_pairs_train is absent ===")
        return
    rows = []
    for years in YEAR_WINDOWS:
        for genres in GENRE_THRESHOLDS:
            sql = model_1_sql(genres, years)
            s = score(sql, "train")
            if s is None:
                continue
            rows.append({"year_gap": years, "genres": genres,
                         "returned": volume(sql), "labelled": s["labelled"],
                         "precision": round(s["precision"], 1),
                         "recall": round(s["recall"], 1)})
    show("MODEL 1, Style & Era - train grid", rows,
         ["year_gap", "genres", "returned", "labelled", "precision", "recall"])

    print("\nThe window at 3 shared genres, which is the negative finding:")
    for r in rows:
        if r["genres"] == 3:
            print(f"  year_gap <= {r['year_gap']:>2}: precision {r['precision']}%, "
                  f"{r['labelled']} labelled, {r['returned']:,} returned")
    print("  A 2.1 point spread with no direction, while volume grows 3.7 times.")
    # RESULT: 81.1, 81.1, 79.7, 81.4, 81.8 across the five windows.
    #         Chosen cell: 3 shared genres, 20 year window, 46,318 pairs.


# ============================================================
# SECTION 2 - MODEL 2: COMMON CAST
#
# Runs twice, on the raw cast and on the credited cast. The gap between the
# two curves is what the data quality layer bought.
# ============================================================

CAST_TABLES = {"raw": "gs_roles", "credited": "gs_roles_credited"}
K_THRESHOLDS = [1, 2, 3, 4, 5]


def model_2_sql(table, k):
    return f"""
        SELECT gr1.movie_id AS movie_id_1,
               gr2.movie_id AS movie_id_2
        FROM {table} AS gr1
        JOIN {table} AS gr2
            ON gr1.actor_id = gr2.actor_id
            AND gr1.movie_id != gr2.movie_id
        GROUP BY gr1.movie_id, gr2.movie_id
        HAVING COUNT(DISTINCT gr1.actor_id) >= {k}
    """


def section_2():
    if "train" not in SPLITS:
        print("\n=== MODEL 2, Common Cast - skipped, gt_pairs_train is absent ===")
        return
    rows = []
    for label, table in CAST_TABLES.items():
        for k in K_THRESHOLDS:
            s = score(model_2_sql(table, k), "train")
            if s is None:
                continue
            rows.append({"cast": label, "k": k, "labelled": s["labelled"],
                         "precision": round(s["precision"], 1),
                         "recall": round(s["recall"], 1)})
    show("MODEL 2, Common Cast - train, raw cast against credited cast", rows,
         ["cast", "k", "labelled", "precision", "recall"])

    at3 = {r["cast"]: r["precision"] for r in rows if r["k"] == 3}
    if len(at3) == 2:
        print(f"\nWhat the cleaning step buys at k=3: "
              f"{at3['raw']}% raw against {at3['credited']}% credited, "
              f"{round(at3['credited'] - at3['raw'], 1)} points.")
    # RESULT: 73.2, 84.7, 91.8, 94.8, 95.2 on the credited cast at k = 1 to 5.
    #         The gain collapses after 3, and 3 returns twice the volume of 4.
    #         Cleaning buys 6.7 points at the chosen threshold, 85.1 to 91.8.


# ============================================================
# SECTION 3 - MODEL 3: DIRECTOR GENRE DNA
#
# One tunable parameter, p. The 3 film floor per director is fixed by
# reasoning and is not swept: a director with two films has no filmography.
# ============================================================

P_THRESHOLDS = [0.05, 0.08, 0.10, 0.12, 0.15, 0.20, 0.25, 0.30, 0.35]


def model_3_sql(p):
    return f"""
        SELECT movie_id_1, movie_id_2
        FROM model_3_candidates
        WHERE dna_strength >= {p}
    """


def section_3():
    if "train" not in SPLITS:
        print("\n=== MODEL 3, Director Genre DNA - skipped, gt_pairs_train is absent ===")
        return
    rows = []
    for p in P_THRESHOLDS:
        sql = model_3_sql(p)
        s = score(sql, "train")
        if s is None:
            continue
        rows.append({"p": p, "returned": volume(sql), "labelled": s["labelled"],
                     "precision": round(s["precision"], 1),
                     "recall": round(s["recall"], 1)})
    show("MODEL 3, Director Genre DNA - train curve", rows,
         ["p", "returned", "labelled", "precision", "recall"])

    print("\nStrongest director genre signatures, a sanity check on the signal:")
    print(run("""
        SELECT CONCAT(d.first_name, ' ', d.last_name) AS director,
               dg.genre AS genre,
               ROUND(dg.laplace_prob, 4) AS laplace_prob
        FROM model_3_director_genre AS dg
        JOIN gs_directors AS d ON d.id = dg.director_id
        ORDER BY dg.laplace_prob DESC
        LIMIT 8
    """).to_string(index=False))
    # RESULT: 0.12 gives 90.3%, 0.15 gives 93.4%, the largest step. 0.20 adds
    #         0.3 points and halves recall. 0.35 reads 100% on 122 pairs.
    #         Chosen: p >= 0.15, 158,306 pairs, resting on 594 labelled.


# ============================================================
# SECTION 4 - MODEL 4: SHARED STAR ACTOR
#
# No threshold to tune, so instead we test whether the star list earns its
# place. Two controls: any shared credited actor, and actors with 3 or more
# credits here. On train all three land within 0.2 points. On test the list
# holds up 4.6 points better. Both halves are reported.
# ============================================================

MODEL_4_VARIANTS = {
    "curated list of 22": """
        SELECT movie_id_1, movie_id_2 FROM model_4_candidates
    """,
    "any credited actor": """
        SELECT gr1.movie_id AS movie_id_1, gr2.movie_id AS movie_id_2
        FROM gs_roles_credited AS gr1
        JOIN gs_roles_credited AS gr2
            ON gr1.actor_id = gr2.actor_id
            AND gr1.movie_id != gr2.movie_id
        GROUP BY gr1.movie_id, gr2.movie_id
    """,
    "actor with 3+ credits": """
        SELECT gr1.movie_id AS movie_id_1, gr2.movie_id AS movie_id_2
        FROM gs_roles_credited AS gr1
        JOIN gs_roles_credited AS gr2
            ON gr1.actor_id = gr2.actor_id
            AND gr1.movie_id != gr2.movie_id
        JOIN (SELECT actor_id FROM gs_roles_credited
              GROUP BY actor_id
              HAVING COUNT(DISTINCT movie_id) >= 3) AS busy
            ON busy.actor_id = gr1.actor_id
        GROUP BY gr1.movie_id, gr2.movie_id
    """,
}


def section_4():
    rows = []
    for label, sql in MODEL_4_VARIANTS.items():
        r = {"definition of a star": label, "returned": volume(sql)}
        for split in SPLITS:
            s = score(sql, split)
            r[f"{split} labelled"] = s["labelled"]
            r[f"{split} prec"] = round(s["precision"], 1)
        rows.append(r)
    cols = ["definition of a star", "returned"]
    for split in SPLITS:
        cols += [f"{split} labelled", f"{split} prec"]
    show("MODEL 4, Shared Star Actor - the list against two controls", rows, cols)
    print("\nOn train the list buys nothing. On test it holds up better.")
    # RESULT: 73.0 / 73.2 / 73.1 on train. 64.8 against 60.2 on test.
    #         The list costs 92% of the volume and buys nothing on train.


# ============================================================
# SECTION 5 - MODEL 5: COLLABORATIVE FILTERING
#
# Two parameters, so this is a grid. Support floor on the outside, Jaccard
# on the inside. Floor 1 is the no floor case, and the comparison against
# it is what justifies having a floor at all.
# ============================================================

SUPPORT_FLOORS = [1, 2, 3, 4, 5]
JACCARD_THRESHOLDS = [0.02, 0.05, 0.10, 0.15, 0.20, 0.30, 0.50]


def model_5_sql(floor, j):
    return f"""
        SELECT movie_id_1, movie_id_2
        FROM model_5_candidates
        WHERE co_raters >= {floor}
            AND jaccard >= {j}
    """


def section_5():
    if "train" not in SPLITS:
        print("\n=== MODEL 5, Collaborative Filtering - skipped, gt_pairs_train is absent ===")
        return
    rows = []
    for floor in SUPPORT_FLOORS:
        for j in JACCARD_THRESHOLDS:
            s = score(model_5_sql(floor, j), "train")
            if s is None:
                continue
            rows.append({"co_raters": floor, "jaccard": j,
                         "labelled": s["labelled"],
                         "precision": round(s["precision"], 1),
                         "recall": round(s["recall"], 1)})
    show("MODEL 5, Collaborative Filtering - train grid", rows,
         ["co_raters", "jaccard", "labelled", "precision", "recall"])

    print("\nWhy a support floor, every floor at jaccard >= 0.50:")
    for r in rows:
        if r["jaccard"] == 0.50:
            print(f"  co_raters >= {r['co_raters']}: precision {r['precision']}%, "
                  f"{r['labelled']} labelled")
    print("  Floor 1 to 2 is the only real step. Above that it is not even a")
    print("  rising line, which is what noise looks like.")

    print("\nWhat this model can see, and why its precision reads high:")
    print(run("""
        SELECT COUNT(*) AS train_pairs_visible,
               ROUND(100 * SUM(g.recommendation > 5) / COUNT(*), 1) AS pct_already_good
        FROM gt_pairs_train AS g
        WHERE g.base_movie_id IN (SELECT movie_id FROM model_5_liked)
            AND g.recommended_movie_id IN (SELECT movie_id FROM model_5_liked)
    """).to_string(index=False))
    print("  Against 51.3% for train as a whole. The fair comparison for this")
    print("  model is 90.9% against that number, not against the baseline.")
    # RESULT: floors 2 to 5 give 90.9, 90.4, 90.4, 91.2 at jaccard 0.50.
    #         Chosen: co_raters >= 2, jaccard >= 0.50, 20,888 pairs.


# ============================================================
# SECTION 6 - THE AGGREGATION
#
# The threshold curve on both splits. On train it is flat, which is why size
# and not precision decided the cut. On test it rises while recall falls.
# ============================================================

AGG_CUTS = [0.1, 0.4, 0.8, 1.0]


def agg_sql(cut):
    return f"""
        SELECT movie_id_1, movie_id_2
        FROM model_agg
        WHERE score >= {cut}
    """


def section_6():
    rows = []
    for cut in AGG_CUTS:
        sql = agg_sql(cut)
        r = {"cut": cut, "returned": volume(sql)}
        for split in SPLITS:
            s = score(sql, split)
            r[f"{split} n"] = s["labelled"]
            r[f"{split} prec"] = round(s["precision"], 1)
            r[f"{split} rec"] = round(s["recall"], 1)
        rows.append(r)
    cols = ["cut", "returned"]
    for split in SPLITS:
        cols += [f"{split} n", f"{split} prec", f"{split} rec"]
    show("THE AGGREGATION - threshold curve", rows, cols)

    print("\nHow often the models agree:")
    print(run("""
        SELECT models_firing AS models_firing, COUNT(*) AS pairs
        FROM model_agg
        GROUP BY models_firing
        ORDER BY models_firing
    """).to_string(index=False))
    print("  94.8% of the pairs that survive come from exactly one model.")
    # RESULT: train 86.7 / 84.8 / 88.2 / 88.7, a 2.0 point spread with a dip.
    #         test  61.4 / 70.7 / 79.2 / 82.4, rising at every step.
    #         The cut sits at 1.0, giving 776 pairs.


# ============================================================
# SECTION 7 - THE FINAL TABLE
#
# Every model and the combination, on both splits, with F1. This is the
# table in section 5 of the report.
#
# F1 is reported because precision alone hides what the cut costs. It also
# shows the combination near the bottom, which is the honest reading: F1
# treats a good pair we missed as costly as a wrong pair we showed, and this
# project decided at the outset that it is not.
# ============================================================

FINAL_MODELS = {
    "Model 1, Style and Era":           model_1_sql(3, 20),
    "Model 2, Common Cast":             "SELECT movie_id_1, movie_id_2 FROM model_2_candidates",
    "Model 3, Director Genre DNA":      model_3_sql(0.15),
    "Model 4, Shared Star Actor":       "SELECT movie_id_1, movie_id_2 FROM model_4_candidates",
    "Model 5, Collaborative Filtering": model_5_sql(2, 0.50),
    "All five combined":                agg_sql(1.0),
}


def section_7():
    rows = []
    for name, sql in FINAL_MODELS.items():
        r = {"model": name, "returned": volume(sql)}
        for split in SPLITS:
            s = score(sql, split)
            r[f"{split} prec"] = round(s["precision"], 1)
            r[f"{split} rec"] = round(s["recall"], 1)
            r[f"{split} F1"] = round(s["f1"], 1)
        if len(SPLITS) == 2:
            r["change"] = round(r["test prec"] - r["train prec"], 1)
        rows.append(r)
    cols = ["model", "returned"]
    for split in SPLITS:
        cols += [f"{split} prec", f"{split} rec", f"{split} F1"]
    if len(SPLITS) == 2:
        cols.append("change")
    show("THE FINAL TABLE - every model, every split", rows, cols)
    for split in SPLITS:
        print(f"\n{split}: baseline {BASELINES[split]:.1%}, "
              f"{positives(split):,} good pairs in the recall denominator.")
    if "train" not in SPLITS:
        print("\ntrain columns are absent because gt_pairs_train is not part of "
              "the course\npipeline. It is the 2025 ground truth we built. Test "
              "figures are unaffected.")
    # RESULT: the combination reads 88.7 / 82.4 on precision, the smallest
    #         fall of anything measured, and 8.7 / 15.4 on F1, second from
    #         bottom. Both are true and the report says why.


def main():
    print(__doc__.split("FIGURES")[0].rstrip())
    section_1()
    section_2()
    section_3()
    section_4()
    section_5()
    section_6()
    section_7()
    print("\nDone.")


if __name__ == "__main__":
    main()
