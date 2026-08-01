# Model 3: Director Genre DNA

Two movies are similar if they share a genre and **both their directors score
at least 0.15** in that genre. Directors are only considered if they have at
least 3 films in the universe.

Precision 93.4% on train and 59.4% on test, against baselines of 51.3% and
49.1%. 158,306 pairs across 835 base movies.

**Strongest model on train. Second weakest on test.** That reversal is the
interesting part, and it is discussed below.

## The idea

A genre tag says what a movie is. A director's genre probability says what they
consistently make. Two movies are similar if they share a genre and both
directors are strongly associated with it, so there is expertise on both sides
rather than just a label match.

This is deliberately not the course's "same director" example. The two
directors can be different people. The link is the genre signature, not the
person.

The score for a pair is the **weaker** of the two directors. Thresholding on
the minimum is the same as requiring both to clear the bar, and it gives one
column to tune. Where a pair shares several genres, the best one wins.

## The Laplace correction

Score is `(films in genre + 1) / (total films + 21)`, where 21 is the number of
distinct genres.

The `prob` column already in the data carries no small sample correction: a
director with one film in one genre scores 1.0 there. Laplace pulls those
extremes back toward the middle in proportion to how little evidence supports
them.

This has a consequence worth stating. A 3-film director working only in one
genre reaches at most `(3+1)/(3+21) = 0.167`. So the whole scale sits low, and
a threshold of 0.15 is strict rather than loose. The observed range is 0.031 to
0.474.

The strongest signatures are recognisable specialists, not artefacts of short
filmographies:

| Director | Genre | Films in genre | Total | Score |
|---|---|---|---|---|
| Walt Disney | Animation | 17 | 17 | 0.474 |
| Woody Allen | Comedy | 16 | 16 | 0.460 |
| Martin Scorsese | Drama | 21 | 35 | 0.393 |
| Alfred Hitchcock | Thriller | 11 | 11 | 0.375 |
| Tony Scott | Action | 13 | 20 | 0.342 |
| Hayao Miyazaki | Animation | 11 | 16 | 0.324 |

## Choosing the threshold

| Score >= | Pairs returned | Rated | Precision | Recall |
|---|---|---|---|---|
| 0.10 | 257,014 | 712 | 88.8% | 23.1% |
| 0.12 | 233,644 | 690 | 90.3% | 22.7% |
| **0.15** | **158,306** | **594** | **93.4%** | **20.3%** |
| 0.20 | 54,392 | 303 | 93.7% | 10.4% |
| 0.30 | 4,064 | 159 | 95.6% | 5.5% |
| 0.35 | 1,732 | 122 | 100.0% | 4.5% |

**Why 0.15 and not 0.12?** +3.1 points, the largest single step in the curve.

**Why not 0.20?** +0.3 points for two thirds of the volume, and recall halves.
The gain has stopped, only the cost continues.

**Why not 0.30 or 0.35, where precision is higher?** 0.35 reads 100.0% on 122
rated pairs. That is the same small sample trap Model 2 shows above k=8.
0.15 rests on 594 rated pairs, the widest support of any cell above 93%.

**Why is the 3-film floor not tuned?** A director with two films has no
filmography, only a coincidence. The Laplace correction handles what small
sample bias remains above the floor. Tuning it as well would be fitting a
parameter that reasoning already fixes.

## Coverage ceiling

| | |
|---|---|
| Directors in `gs_movies_directors` | 2,674 |
| Directors with 3 or more films | 189 |
| Films covered by those directors | 959 of 3,063 |
| Base movies reached | 835 |

The floor removes 93% of directors. 2,201 of them have a single film in the
trimmed universe. This is an input limit, and the recall figure has to be read
against it.

## Why the model falls so far on test

The 34.0 point drop is the largest of the five. Two things are worth saying
about it rather than smoothing it over.

The train figure rests on 594 rated pairs. The test figure rests on 1,235, so
**the test number is the better supported of the two** and the report leads
with it.

Recall moves the other way, 20.3% to 31.7%. The model reaches more of the test
set while being right about less of it.

## Data quality

The layer here is the Laplace correction plus the 3-film floor. Both are
structural rather than a cleaning pass over rows. Rerunning the model against
the discarded `prob` column would measure what the correction bought. That
comparison was not run.

## Files

| File | What it does |
|---|---|
| `model_3.sql` | Builds the director and pair tables, runs the final query |
| `tune_model_3.py` | Sweeps the threshold and prints the strongest signatures |
| `curve_train.csv` | The full curve, as measured |
