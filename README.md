# five_signals

Movie to movie recommendation system built in SQL over the IMDB dataset.

Final project, Databases for Data Analytics, Reichman University, 2026B.
Yaron Besser (324943109) and Nevo Aloni (322815820).

## What this is

Five models, each defining a different reason why two movies are similar. Each
returns a list of movie pairs with a raw score. An aggregation step combines
all five into one table, `my_models_agg`, which the course confusion matrix
reads.

The metric we optimised is **precision**. A recommendation system shows a short
list, so a bad film on that list costs more than a good film left off it. Every
threshold was tuned on the 2025 ground truth. The 2026 ground truth was
measured once, at the end, after all five models were locked.

Precision is counted over labelled pairs only. A pair the class never rated is
unknown, not wrong, so it is excluded from the denominator.

## Results

| Model | Train | Test | Change |
|---|---|---|---|
| Model 3, Director Genre DNA | 93.4% | 59.4% | -34.0 |
| Model 2, Common Cast | 91.8% | 68.6% | -23.2 |
| Model 5, Collaborative Filtering | 90.9% | 76.8% | -14.1 |
| Model 1, Style and Era | 81.8% | 59.8% | -22.0 |
| Model 4, Shared Star Actor | 73.0% | 64.8% | -8.2 |
| **All five combined** | **88.7%** | **82.4%** | **-6.3** |

Baselines, meaning a model that calls every pair good: 51.3% on train and 49.1%
on test.

The combination does not beat its best member on train, but it beats every
member on test and drops the least. Full analysis is in the report.

## How to run

Everything runs in schema `imdb_ijs`.

1. Run the four course files first: `build_gs`, `movies_recommendations`,
   `movies_recommendations_agg`, `build_restricted_gs_db`.
2. Run `01_pipeline/` in filename order, 01 through 07. Step 01 resets every
   table it owns, so the sequence is always a build from scratch.
3. Run `02_ground_truth/build_gt_tables.sql`.
4. Run the models. Either file by file from `04_models/`, or in one pass:

```
mysql -u root -p imdb_ijs < deliverables/five_signals_models.sql
```

That single file contains all five models and the aggregation, in dependency
order. It runs clean from a built pipeline with no errors.

## Folder map

| Folder | What is in it |
|---|---|
| `deliverables/` | The three submitted files, and nothing else |
| `01_pipeline/` | Loading and preparation, run 01 to 07 |
| `02_ground_truth/` | Train and test split, and its validation |
| `03_validation/` | Data validation queries |
| `04_models/` | The five models, the aggregation, the shared evaluation |
| `docs/` | Design decisions and the reasoning behind them |
| `figures/` | The charts used in the report |
