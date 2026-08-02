# The submitted files

Three files go to the course. The `.docx` is the editable source of the report
and is not submitted.

| File | What it is |
|---|---|
| `five_signals_models.sql` | All five models and the aggregation, in one file |
| `five_signals_analysis.py` | The measurement half: every number in the report |
| `five_signals_report.pdf` | The report. This is the submitted document |
| `five_signals_report.docx` | Editable source, not submitted |

## The SQL file

767 lines, assembled from the files in `04_models/` in dependency order. It is
not a rewrite. Each section is the same query that lives in its model folder.

```
mysql -u root -p imdb_ijs < five_signals_models.sql
```

Runs clean in about 15 seconds and emits roughly 326,000 rows, because each
model prints its full pair list. Redirect to a file if running interactively.

It reproduces the headline numbers exactly: 776 pairs returned, 88.7% precision
on train over 142 rated pairs, 82.4% on test over 238.

Two things it deliberately does not do. It never reads `gt_pairs_train`, which
is a table we built and nobody else has, so the file runs anywhere the four
course files have run. And section order matters in one place: section 0 builds
`gs_roles_credited`, which sections 2 and 4 read.

## The Python file

512 lines. Reads the tables the SQL file built and prints the tuning grids,
the threshold curves and the final metrics table, including F1.

```
pip install -r requirements.txt
MYSQL_PASSWORD=yourpassword python3 five_signals_analysis.py
```

Takes about 7 seconds and creates nothing. Every way it can fail prints a
sentence saying what to do rather than a stack trace: a missing package names
the package and the interpreter in use, and an unreachable database names the
host, schema and user. If `gt_pairs_train` is absent it skips every train
figure and still runs end to end on test.

## The report

Seven pages. Goal and method, the data, the five models, the aggregation, what
the results say, what we would improve, the data quality layer, limits, and a
note on the course confusion matrix.

Both team ID numbers are on the first page, as the course guide requires, and
the team name is in every filename.
