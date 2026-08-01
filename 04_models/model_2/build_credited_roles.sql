USE imdb_ijs;

-- Step 1: identify role names that are function labels, not characters.
-- Cut at 38: below it the band is mostly genuine character names. Above it
-- almost everything is a function label - Man, Mother, Student, Newscaster.
--
-- Keep-list: genuine characters that the cut would otherwise catch.
-- Given names stay - a character called John is a real part.
DROP TABLE IF EXISTS generic_roles;

CREATE TABLE generic_roles AS
SELECT role AS role_name,
       COUNT(DISTINCT movie_id) AS movies_with_role
FROM gs_roles
WHERE TRIM(role) <> ''
    AND role NOT LIKE '%James Bond%'  -- keep-list
    AND role NOT LIKE '%Alice%'
    AND role NOT LIKE '%John%'
GROUP BY role
HAVING COUNT(DISTINCT movie_id) >= 38;
-- RESULT: 33 generic role names

-- Step 2: the cast table the models run against.
DROP TABLE IF EXISTS gs_roles_credited;

CREATE TABLE gs_roles_credited AS
SELECT r.actor_id AS actor_id,
       r.movie_id AS movie_id,
       r.role AS role
FROM gs_roles AS r
LEFT JOIN generic_roles AS g
    ON r.role = g.role_name
WHERE TRIM(r.role) != ''  
    AND g.role_name IS NULL; 
-- RESULT: 71,020 role rows, down from 84,232 - 13,212 removed (15.7%)
-- RESULT: movies with any cast drops from 3,019 to 2,548 - 471 films lose
--         their entire cast and become unreachable for this model

CREATE INDEX idx_credited_actor ON gs_roles_credited (actor_id);
CREATE INDEX idx_credited_movie ON gs_roles_credited (movie_id);
