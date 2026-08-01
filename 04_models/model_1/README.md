# Model 1: Style and Era

Two movies are similar if they share at least **3 genres** and came out
**within 20 years** of each other.

Precision 81.8% on train and 59.8% on test, against baselines of 51.3% and
49.1%. 46,318 pairs across 1,000 base movies.

## The idea

Genre carries the style, the year gap carries the era. Neither half works
alone. The universe is 3,569 movies over 6,951 genre rows, so a single shared
genre puts most dramas next to most other dramas. A shared release year says
nothing at all. The model is the conjunction.

## Choosing the parameters

Tuned on train over a grid of 5 year windows by 4 genre thresholds. Cells
resting on fewer than 100 rated pairs were printed but were not eligible.

**Why 3 shared genres and not 2?** Precision goes from 76.7% to 81.8%. That is
a 5.1 point gain, the largest single step anywhere in the grid.

**Why not 4?** Precision falls to 77.6%, and it rests on 58 rated pairs, below
the credibility floor. Worse on both axes at once.

**Why a 20 year window and not tighter?** Because tightening buys nothing. At 3
shared genres the five windows give:

| Window | 2 years | 5 | 10 | 15 | 20 |
|---|---|---|---|---|---|
| Precision | 81.1% | 81.1% | 79.7% | 81.4% | 81.8% |
| Pairs returned | 12,652 | 23,994 | 35,558 | 42,300 | 46,318 |

A 2.1 point spread with no direction, while volume grows 3.7 times. A parameter
that does not move precision should not throw away 73% of the output, so the
loosest window measured is the right one.

**This is a negative result and it belongs in the report.** The era half of
"Style and Era" does not earn its place. In substance this model is "two movies
sharing 3 or more genres", and the year gap survives only as a bound on how
much gets materialised.

**Why not wider than 20?** Unknown, and that is a limit rather than a
justification. 20 is the materialisation ceiling in `model_1.sql`, so the chosen
value sits at the edge of the measured range. Precision is flat and volume is
still climbing there, so nothing says 20 is where the window should stop.
Rebuilding at 40 would settle it.

## Coverage ceiling

| | |
|---|---|
| Movies in `gs_movies` | 3,569 |
| Movies with at least one genre row | 3,178 |
| Movies the model can reach | 3,178 |

Reachable movies equal genre-carrying movies exactly. The model reaches every
film that has a genre, and the 391 it cannot see are missing genre data
entirely rather than failing any threshold. 89.0% genre coverage is the
ceiling, and it is an input limit rather than a tuning choice.

## Data quality

This model reads `gs_movies` and `gs_movies_genres`. Neither carries anything
the duplicate filter acts on, so the layer has no effect here, and that is the
honest answer rather than a gap.

The `year IS NOT NULL` guard in the query is dead code on this data: zero
movies in `gs_movies` have a null year, and the filter costs zero candidate
pairs. Pipeline step 06 already excluded year-less films when it built the
trimmed universe. The guard stays because it is correct, not because it does
anything.

## Files

| File | What it does |
|---|---|
| `model_1.sql` | Builds the candidate table and runs the final query |
| `tune_model_1.py` | Sweeps the grid over the stored table |
| `grid_train.csv` | The full grid, as measured |

```
mysql -u root -p imdb_ijs < model_1.sql
python tune_model_1.py
```

`model_1.sql` materialises every pair sharing a genre within 20 years and keeps
both components as columns, so tuning never re-runs the expensive join.
