USE imdb_ijs;

-- ============================================================
-- Model 4: Shared Star Actor
--
-- Two movies are similar if they share at least one star actor.
--
-- No tunable threshold. The curated list of 22 names is the filter. A film
-- count threshold was rejected: it admits prolific unknowns and excludes
-- stars with short filmographies in this universe. See README.md.
--
-- Reads gs_roles_credited, built by model_2/build_credited_roles.sql.
-- ============================================================

-- Matched by name rather than by id, so the table survives a rebuild.
-- The (I) suffixes are IMDB disambiguators and part of the stored name.
DROP TABLE IF EXISTS model_4_star_actors;

CREATE TABLE model_4_star_actors AS
SELECT a.id AS actor_id,
       CONCAT(a.first_name, ' ', a.last_name) AS actor_name,
       COUNT(DISTINCT r.movie_id) AS credits  -- reported only, not a filter
FROM gs_actors AS a
JOIN gs_roles_credited AS r
    ON r.actor_id = a.id
WHERE (a.first_name, a.last_name) IN (
    ('Tom', 'Hanks'), ('Leonardo', 'DiCaprio'), ('Robert', 'De Niro'),
    ('Al', 'Pacino'), ('Brad', 'Pitt'), ('Jack', 'Nicholson'),
    ('Tom', 'Cruise'), ('Clint', 'Eastwood'), ('Dustin', 'Hoffman'),
    ('Anthony', 'Hopkins'), ('Jim', 'Carrey'), ('Gene', 'Hackman'),
    ('Marlon', 'Brando'), ('Nicolas', 'Cage'), ('Johnny', 'Depp'),
    ('Matt', 'Damon'), ('Ben', 'Affleck'), ('George', 'Clooney'),
    ('Kevin', 'Costner'), ('Morgan (I)', 'Freeman'),
    ('Samuel L.', 'Jackson'), ('Mel (I)', 'Gibson')
)
GROUP BY a.id, a.first_name, a.last_name;

ALTER TABLE model_4_star_actors
ADD PRIMARY KEY (actor_id);

-- Anything other than 22 means a name failed to match.
SELECT COUNT(*) AS stars_found
FROM model_4_star_actors;
-- RESULT: 22

-- Both directions, because the ground truth is directed.
DROP TABLE IF EXISTS model_4_candidates;

CREATE TABLE model_4_candidates AS
SELECT r1.movie_id AS movie_id_1,
       r2.movie_id AS movie_id_2,
       COUNT(DISTINCT r1.actor_id) AS shared_stars
FROM gs_roles_credited AS r1
JOIN gs_roles_credited AS r2
    ON r1.actor_id = r2.actor_id
    AND r1.movie_id <> r2.movie_id  -- <> not < : emits both directions
JOIN model_4_star_actors AS s
    ON s.actor_id = r1.actor_id
GROUP BY r1.movie_id, r2.movie_id;

ALTER TABLE model_4_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2);

SELECT COUNT(*) AS candidate_pairs,
       COUNT(DISTINCT movie_id_1) AS base_movies,
       MAX(shared_stars) AS max_shared_stars
FROM model_4_candidates;
-- RESULT: 7,328 pairs, 315 base movies, at most 3 shared stars

-- FINAL QUERY. Emits the raw signal; aggregate.sql normalises and weights it.
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       shared_stars AS shared_stars
FROM model_4_candidates;

-- Measurement view for ../evaluate_model.sql. The fixed 9 exists only so the
-- confusion matrix has a value above 5 to read. Baselines 51.3% and 49.1%.
DROP VIEW IF EXISTS eval_predictor;

CREATE VIEW eval_predictor AS
SELECT movie_id_1 AS base_movie_id,
       movie_id_2 AS recommended_movie_id,
       9 AS recommendation
FROM model_4_candidates;
-- RESULT: train precision 73.0% on 237 rated pairs, recall 6.3%
--         test  precision 64.8% on 230 rated pairs, recall 6.5%

-- CONTROL: the star list removed, so any shared credited actor qualifies.
-- This is the number that decides whether the curated list contributes.
DROP VIEW IF EXISTS eval_predictor_control;

CREATE VIEW eval_predictor_control AS
SELECT gr1.movie_id AS base_movie_id,
       gr2.movie_id AS recommended_movie_id,
       9 AS recommendation
FROM gs_roles_credited AS gr1
JOIN gs_roles_credited AS gr2
    ON gr1.actor_id = gr2.actor_id
    AND gr1.movie_id <> gr2.movie_id
GROUP BY gr1.movie_id, gr2.movie_id;
-- RESULT: train precision 73.2% on 1,206 rated pairs
--         test  precision 60.2% on 1,160 rated pairs
--         The list costs 92% of the volume and moves train precision by
--         -0.2 points, but holds up better on test. See README.md.
