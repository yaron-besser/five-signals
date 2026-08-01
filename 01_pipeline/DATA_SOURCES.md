# 01_pipeline

Loading and preparation, run 01 to 07 in filename order.

## Two files are not in this repository

`02_load_2025_train.sql` and `03_load_personal_rankings.sql` hold the class
data: the 2025 movie pair ratings and the personal movie rankings of 35
students, with their names and their written justifications.

That data is not ours to republish. It lives in the course repository, where
each student submitted it themselves:

    https://github.com/evidencebp/databases-course

- personal rankings: `recommendations_goldstandard/collaborative_filtering/rating/`
- movie pair ratings: `recommendations_goldstandard/recommendations/`

## To reproduce the pipeline

1. Run the four course files: `build_gs`, `movies_recommendations`,
   `movies_recommendations_agg`, `build_restricted_gs_db`.
2. Load the class ratings from the links above into
   `personal_movies_ranking` and `movies_recommendations`.
3. Run `04_apply_data_quality.sql`, then `05` and `06` in order.
4. Run `02_ground_truth/build_gt_tables.sql` to build `gt_pairs_train`.

Everything downstream of that point is in this repository and runs.
