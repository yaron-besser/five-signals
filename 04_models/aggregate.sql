USE imdb_ijs;

-- ============================================================
-- aggregate.sql - combine the five models into one score.
--
--   Score = sum over models of (train precision x normalised output)
--
-- Weights are each model's measured train precision. Models 3 and 5 are
-- already bounded 0-1, model 4 is binary, and models 1 and 2 divide by their
-- observed maximum (10 shared genres, 47 shared actors). The maximum possible
-- score is the sum of the weights, 4.3097. See README.md.
--
-- PREREQUISITE: all five model files have run, so their _candidates tables
-- exist.
-- ============================================================

DROP TABLE IF EXISTS model_agg;

CREATE TABLE model_agg AS
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       COUNT(*) AS models_firing,  -- kept for error analysis
       SUM(weighted) AS score
FROM (
    SELECT movie_id_1, movie_id_2, 0.8182 * shared_genres / 10 AS weighted
    FROM model_1_candidates
    WHERE shared_genres >= 3 AND year_gap <= 20

    UNION ALL
    SELECT movie_id_1, movie_id_2, 0.9179 * common_actors / 47
    FROM model_2_candidates

    UNION ALL
    SELECT movie_id_1, movie_id_2, 0.9343 * dna_strength
    FROM model_3_candidates
    WHERE dna_strength >= 0.15

    UNION ALL
    SELECT movie_id_1, movie_id_2, 0.7300
    FROM model_4_candidates

    UNION ALL
    SELECT movie_id_1, movie_id_2, 0.9093 * jaccard
    FROM model_5_candidates
    WHERE co_raters >= 2 AND jaccard >= 0.50
) AS u
GROUP BY movie_id_1, movie_id_2;

ALTER TABLE model_agg
ADD PRIMARY KEY (movie_id_1, movie_id_2);

ALTER TABLE model_agg
ADD KEY idx_model_agg_score (score);

SELECT COUNT(*) AS pairs,
       MIN(score) AS min_score,
       MAX(score) AS max_score,
       MAX(models_firing) AS max_models_firing
FROM model_agg;
-- RESULT: 223,248 pairs, score 0.0586 to 2.2471, at most 5 models firing.
--         The observed maximum is barely half the theoretical 4.3097.

-- How the pairs spread across how many models fired on them.
SELECT models_firing AS models_firing,
       COUNT(*) AS pairs,
       MIN(score) AS min_score,
       MAX(score) AS max_score
FROM model_agg
GROUP BY models_firing
ORDER BY models_firing;
-- RESULT: 1 model  211,642 pairs   2 models 10,812   3 models 684
--         4 models     94          5 models     16
--         94.8% of pairs fire on exactly one model, so the score is mostly one
--         model's opinion scaled by its precision, not a vote.

-- THRESHOLD CURVE. One pass over the labelled pairs, each pair counted into
-- every bucket it clears.
SELECT SUM(a.score >= 0.1) AS n_10,
       SUM(a.score >= 0.2) AS n_20,
       SUM(a.score >= 0.4) AS n_40,
       SUM(a.score >= 0.6) AS n_60,
       SUM(a.score >= 0.8) AS n_80,
       SUM(a.score >= 1.0) AS n_100,
       SUM(a.score >= 0.1 AND g.recommendation > 5) AS good_10,
       SUM(a.score >= 0.2 AND g.recommendation > 5) AS good_20,
       SUM(a.score >= 0.4 AND g.recommendation > 5) AS good_40,
       SUM(a.score >= 0.6 AND g.recommendation > 5) AS good_60,
       SUM(a.score >= 0.8 AND g.recommendation > 5) AS good_80,
       SUM(a.score >= 1.0 AND g.recommendation > 5) AS good_100
FROM model_agg AS a
JOIN gt_pairs_train AS g
    ON g.base_movie_id = a.movie_id_1
    AND g.recommended_movie_id = a.movie_id_2;
-- RESULT: threshold  labelled  good  precision  recall
--              0.1      1,044   905     86.7%    33.0%
--              0.2        904   783     86.6%    28.6%
--              0.4        632   536     84.8%    19.6%
--              0.6        478   407     85.1%    14.9%
--              0.8        237   209     88.2%     7.6%
--              1.0        142   126     88.7%     4.6%
--         Flat, with no elbow. 33.0% at the loosest cutoff is the highest
--         recall measured anywhere in this project.

-- FINAL RECOMMENDATIONS. The table the confusion matrix reads.
--
-- Cut at 1.0. Precision is flat across the whole range, so the curve alone
-- gives no reason to prefer a cutoff. Size decides it: at 0.1 the table holds
-- 222,082 pairs out of a 3,569-film universe, which is a list of everything
-- rather than a recommendation. 776 pairs is a set a person could be shown.
--
-- Scores map onto 6-10, not 1-10: every row here is a recommendation, so every
-- row must read as positive, and the course guide requires 6 or above.
-- DECIMAL, not INT, because the ground truth is DECIMAL(_,4) and rounding here
-- would drop resolution the other side keeps.
DROP TABLE IF EXISTS my_models_agg;

CREATE TABLE my_models_agg AS
SELECT movie_id_1 AS base_movie_id,
       movie_id_2 AS recommended_movie_id,
       6 + 4 * (score - 1.0) / (2.2471 - 1.0) AS recommendation,
       models_firing AS models_firing,
       score AS raw_score  -- kept for error analysis
FROM model_agg
WHERE score >= 1.0;

ALTER TABLE my_models_agg
ADD PRIMARY KEY (base_movie_id, recommended_movie_id);

SELECT COUNT(*) AS pairs,
       MIN(recommendation) AS min_rec,
       MAX(recommendation) AS max_rec
FROM my_models_agg;
-- RESULT: 776 pairs, recommendation 6.0038 to 9.9999.
--
-- FINAL PERFORMANCE, measured once on each split:
--   split  labelled  TP   precision  recall  baseline
--   TRAIN       142  126      88.7%    4.6%     51.3%
--   TEST        238  196      82.4%    8.5%     49.1%
--
-- The 6.3 point drop from train to test is the smallest of anything measured
-- here. The flat score curve is why: with no sharp threshold, nothing overfits.
