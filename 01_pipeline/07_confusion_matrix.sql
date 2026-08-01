
# Use a reference to your recommendations instead on this table
# Note to use your aggregated version.
# The comment here are for explainability.
drop table if exists imdb_ijs.dummy_recommendations;

create table imdb_ijs.dummy_recommendations
(base_movie_id int
, recommended_movie_id int
, recommendation int 
, suggested_by varchar(255)
, justification varchar(255)
, comment varchar(255)
);

insert into imdb_ijs.dummy_recommendations values (85871, 335337, 9, null, 'Bond', 'TP');
insert into imdb_ijs.dummy_recommendations values (85871, 531, 3, null, 'Bond and a fake Bond', 'TN');
insert into imdb_ijs.dummy_recommendations values (-1, -1, 9, null, 'Similar', 'FP - since the pair does not exists'); # Consider if to include
insert into imdb_ijs.dummy_recommendations values (-2, -2, 3, null, 'Similar - bad recommendation', 'Should have been a TN but pair does not exist');

insert into imdb_ijs.dummy_recommendations values (92573, 368418, 3, null, 'Bond', 'FN -  bad recommendation on two Bonds');
insert into imdb_ijs.dummy_recommendations values (85871, 175469, 9, null, 'Bond', 'FP - good recommendation on a Bond and a fake');


select
count(distinct concat(cast(base_movie_id as char), '_', cast(recommended_movie_id as char))) as samples
from
(
select * from imdb_ijs.dummy_recommendations
union
select * from imdb_ijs.movies_recommendations_agg
) as inSql
;

select 
count(distinct if(class.recommendation > 5
					, concat(cast(class.base_movie_id as char), '_', cast(class.recommended_movie_id as char)
					, null)) as positives
from 
imdb_ijs.movies_recommendations_agg as class
left join
imdb_ijs.dummy_recommendations as predictor
on
class.base_movie_id = predictor.base_movie_id
and 
class.recommended_movie_id = predictor.recommended_movie_id
;


select 
count(distinct if(class.recommendation > 5
					, concat(cast(class.base_movie_id as char)
								, '_'
                                , cast(class.recommended_movie_id as char))
					, null)) as positives
, count(distinct if(class.recommendation > 5 and predictor.recommendation > 5
					, concat(cast(class.base_movie_id as char)
								, '_'
                                , cast(class.recommended_movie_id as char))
					, null)) as true_positives
, count(distinct if(class.recommendation > 5 and predictor.recommendation > 5
					, concat(cast(class.base_movie_id as char)
								, '_'
                                , cast(class.recommended_movie_id as char))
					, null))/count(distinct if(class.recommendation > 5
					, concat(cast(class.base_movie_id as char)
								, '_'
                                , cast(class.recommended_movie_id as char))
					, null)) as recall
from 
imdb_ijs.movies_recommendations_agg as class
left join
imdb_ijs.dummy_recommendations as predictor
on
class.base_movie_id = predictor.base_movie_id
and 
class.recommended_movie_id = predictor.recommended_movie_id
;


select 
count(distinct if(predictor.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as hits
, count(distinct if(predictor.recommendation > 5 and class.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as true_positives


, count(distinct if(predictor.recommendation > 5 and class.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as true_positives
/count(distinct if(predictor.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as precision
from 
imdb_ijs.dummy_recommendations as predictor
left join
imdb_ijs.movies_recommendations_agg as class
on
class.base_movie_id = predictor.base_movie_id
and 
class.recommended_movie_id = predictor.recommended_movie_id
;


select 
count(distinct if(predictor.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as hits
, count(distinct if(predictor.recommendation > 5 and class.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as true_positives


, count(distinct if(predictor.recommendation > 5 and class.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null))/count(distinct if(predictor.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as precision_metric
from 
imdb_ijs.dummy_recommendations as predictor
left join
imdb_ijs.movies_recommendations_agg as class
on
class.base_movie_id = predictor.base_movie_id
and 
class.recommended_movie_id = predictor.recommended_movie_id
;