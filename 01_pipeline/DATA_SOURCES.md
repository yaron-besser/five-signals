# 01_pipeline

Loading and preparation, run 01 to 07 in filename order.

## Where the class data comes from

`02_load_2025_train.sql` and `03_load_personal_rankings.sql` hold data the
class produced, not us: the 2025 movie pair ratings and the personal movie
rankings of 35 students, each with the name they submitted under and their
own written justification.

Every student submitted their own file as a pull request to the course
repository, where it is public:

    https://github.com/evidencebp/databases-course

- personal rankings: `recommendations_goldstandard/collaborative_filtering/rating/`
- movie pair ratings: `recommendations_goldstandard/recommendations/`

The copies here are assembled from those submissions so the pipeline runs in
one pass. They are reproduced with attribution to the course repository as the
source of record. Nothing here was written by us except the loading order.

## Run order

1. The four course files: `build_gs`, `movies_recommendations`,
   `movies_recommendations_agg`, `build_restricted_gs_db`.
2. `01` through `07` in this folder, in filename order.
3. `02_ground_truth/build_gt_tables.sql`, which builds `gt_pairs_train`.

Step 01 resets every table it owns, so the sequence is always a build from
scratch.
