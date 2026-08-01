-- ============================================================
-- 01_build_gs.sql
-- Adapted from the course file build_gs.txt
--
-- Both CREATE statements below are byte-for-byte the originals. Removed: the
-- seed INSERT of 924 pairs, because those same rows load again at step 02 and
-- the double load forces the pipeline to run with --force; and two diagnostic
-- SELECTs that print grids and build nothing. Full reasoning in
-- ../docs/design_decisions.md.
--
-- Also here, and not in the original: the full reset below, and the staging
-- personal_movies_ranking.
--
-- RUN IN ORDER, FORWARD ONLY. This file is destructive by design. Never run a
-- single step backwards mid-session; start again from 01.
-- ============================================================

use imdb_ijs;

-- Full reset. The 7 IMDB source tables are never touched.
DROP TABLE IF EXISTS gt_pairs_train;
DROP TABLE IF EXISTS dummy_recommendations;
DROP TABLE IF EXISTS gs_roles;
DROP TABLE IF EXISTS gs_actors;
DROP TABLE IF EXISTS gs_movies_directors;
DROP TABLE IF EXISTS gs_directors;
DROP TABLE IF EXISTS gs_movies_genres;
DROP TABLE IF EXISTS gs_movies;
DROP TABLE IF EXISTS gs_movies_ids;
DROP TABLE IF EXISTS personal_movies_ranking_raw;
DROP TABLE IF EXISTS personal_movies_ranking;

drop table if exists movies_recommendations;

create table movies_recommendations
(base_movie_id int
, recommended_movie_id int
, recommendation int 
, suggested_by varchar(255)
, justification varchar(1000) not null
, comment varchar(255)
, PRIMARY KEY (base_movie_id, recommended_movie_id, suggested_by)
, CONSTRAINT CHK_recommendation CHECK (recommendation >=1 AND 10 >= recommendation)
, FOREIGN KEY (base_movie_id) REFERENCES movies(Id)
, FOREIGN KEY (recommended_movie_id) REFERENCES movies(Id)
);

drop table if exists movies_recommendations_agg;

create table movies_recommendations_agg
as
select
base_movie_id 
, recommended_movie_id 
, avg(recommendation) as recommendation
, stddev(recommendation) as recommendation_std
, count(distinct suggested_by) as suggested_by_num
, count(distinct justification) as justifications_num
from
movies_recommendations
group by
base_movie_id 
, recommended_movie_id 
;


-- Staging table for the personal rankings. Same five columns and same name as
-- the constrained version, but no primary key and no constraints, so the class
-- file at step 03 loads with zero rejections. Step 04 applies the constrained
-- definition byte-for-byte from the course file and measures what it removes.
DROP TABLE IF EXISTS personal_movies_ranking;

CREATE TABLE personal_movies_ranking (
    movie_id        INT,
    recommendation  INT,
    suggested_by    VARCHAR(255),
    justification   VARCHAR(255),
    comment         VARCHAR(255)
);

-- Recommendation semantics, from the course file. This is the scale behind
-- every score in the project, and behind the > 5 positive threshold.
-- 10  love it, happy to see it any time
--  8  loved it, might see more
--  7  loved it at the time
--  6  good movie, fits my taste
--  5  ok movie
--  4  don't like it
--  2  no way
--  1  would need to be forced
