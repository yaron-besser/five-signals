# deliverables

The two files submitted for the course, plus the editable source of the report.

| File | What it is |
|---|---|
| `five_signals_models.sql` | All five models and the aggregation, in one file |
| `five_signals_report.pdf` | The report. This is the submitted document |
| `five_signals_report.docx` | Editable source of the report |

## The SQL file

895 lines, assembled from the files in `04_models/` in dependency order. It is
not a rewrite. Each section is the same query that lives in its model folder.

Run it top to bottom on schema `imdb_ijs`, after the four course files and the
pipeline have run:

```
mysql -u root -p imdb_ijs < five_signals_models.sql
```

It runs clean with no errors and takes about 20 seconds. It reproduces the
headline numbers exactly: 776 pairs returned, 88.7% precision on train over 142
rated pairs, 82.4% on test over 238.

Section order matters in one place. Section 0 builds `gs_roles_credited`, which
sections 2 and 4 read.

## The report

Seven pages. Goal and method, the data, the five models, the aggregation, what
the results say, the data quality layer, limits.

Both team ID numbers are on the first page, as the course guide requires, and
the team name is in both filenames.
