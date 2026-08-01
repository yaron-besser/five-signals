USE imdb_ijs;

-- ============================================================
-- Model 2: Common Cast Members
--
-- Two movies are similar if they share at least 3 credited actors.
--
-- k = 3 is the elbow: precision goes 84.7% at k=2, 91.8% at k=3, then only 3
-- points more at k=4 while volume halves. Baseline 51.3%. See README.md.
--
-- Reads gs_roles_credited, built by build_credited_roles.sql.
-- ============================================================

SELECT gr1.movie_id AS movie_id_1,
       gr2.movie_id AS movie_id_2,
       COUNT(DISTINCT gr1.actor_id) AS common_actors  -- normalised at aggregation
FROM gs_roles_credited AS gr1
JOIN gs_roles_credited AS gr2
    ON gr1.actor_id = gr2.actor_id
    AND gr1.movie_id <> gr2.movie_id  -- <> not < : emits both directions
GROUP BY gr1.movie_id, gr2.movie_id
HAVING COUNT(DISTINCT gr1.actor_id) >= 3;
-- RESULT: 2,934 pairs across 863 base movies, common_actors 3 to 47.

-- The same query as a table, so aggregation reads all five models the same way.
DROP TABLE IF EXISTS model_2_candidates;

CREATE TABLE model_2_candidates AS
SELECT gr1.movie_id AS movie_id_1,
       gr2.movie_id AS movie_id_2,
       COUNT(DISTINCT gr1.actor_id) AS common_actors
FROM gs_roles_credited AS gr1
JOIN gs_roles_credited AS gr2
    ON gr1.actor_id = gr2.actor_id
    AND gr1.movie_id <> gr2.movie_id
GROUP BY gr1.movie_id, gr2.movie_id
HAVING COUNT(DISTINCT gr1.actor_id) >= 3;

-- Fails loudly if the query ever produces a duplicate pair.
ALTER TABLE model_2_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2);
-- RESULT: 2,934 pairs, added without error, so there are no duplicate pairs.

-- Measurement view for ../evaluate_model.sql. The fixed 9 exists only so the
-- confusion matrix has a value above 5 to read. Baselines 51.3% and 49.1%.
DROP VIEW IF EXISTS eval_predictor;

CREATE VIEW eval_predictor AS
SELECT movie_id_1 AS base_movie_id,
       movie_id_2 AS recommended_movie_id,
       9 AS recommendation
FROM model_2_candidates;
-- RESULT: train precision 91.8% on 414 rated pairs, 380 true positives
--         test  precision 68.6% on 405 rated pairs, 278 true positives
