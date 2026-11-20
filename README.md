# SideQuest ML

Model code for SideQuest lives here. The Flask app, frontend, and data collectors stay in the SideQuest app repository.

## NYC Parks clustering

`experiments/michael_parks_clustering/` prepares activities from one NYC Parks file, fits K-means, and compares k=4 retrieval with an exhaustive search. It does not call an API or a database.

The input file is `data/nyc_parks/latest/events.json`, the October 13, 2026 Parks pull. Outputs are written to `experiments/michael_parks_clustering/output/`.

From this repository root:

```bash
python3 -m venv experiments/michael_parks_clustering/.venv
experiments/michael_parks_clustering/.venv/bin/python -m pip install -r experiments/michael_parks_clustering/requirements.txt
experiments/michael_parks_clustering/.venv/bin/python experiments/michael_parks_clustering/run_experiment.py
```

See `experiments/michael_parks_clustering/README.md` for the feature definitions, split, and limitations.
