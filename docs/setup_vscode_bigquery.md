# Connecting VS Code to BigQuery

One-time setup, about 15 minutes. Your Google account already has access to eICU (PhysioNet) in the BigQuery console; this lets code on your computer use the same account.

## 1. Install the Google Cloud CLI

Follow https://cloud.google.com/sdk/docs/install for your operating system. On a Mac with Homebrew:

```bash
brew install --cask google-cloud-sdk
```

Check it worked:

```bash
gcloud --version
```

## 2. Log in and set the project

```bash
gcloud auth login                                  # opens a browser - use your PhysioNet-linked Google account
gcloud config set project evocative-ethos-471602-r3
gcloud auth application-default login              # lets Python use the same login
```

The last command is the important one: the Python BigQuery library looks for these "application default credentials". No key files are needed, so there's nothing secret to keep out of the repo.

## 3. Open the project in VS Code

1. Install VS Code: https://code.visualstudio.com
2. **File → Open Folder…** → choose `sepsis-imv-aki-tte`
3. VS Code will suggest the recommended extensions (Python, BigQuery Runner). Click **Install**.

## 4. Create a Python environment

In the VS Code terminal (**Terminal → New Terminal**):

```bash
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

If VS Code asks which Python interpreter to use, pick the one inside `.venv`. (On Windows, change `.venv/bin/python` to `.venv\Scripts\python.exe` in `.vscode/settings.json`.)

## 5. Test the connection

```bash
python scripts/run_sql.py --test
```

Expected: `Connected. eICU patient table has 200,859 ICU stays (expected 200,859).`

If it fails:
- **"Could not automatically determine credentials"** → rerun `gcloud auth application-default login`.
- **"Access Denied" on physionet-data** → the logged-in Google account isn't the one linked to PhysioNet. Check with `gcloud auth list`.
- **"billing" / "project" errors** → `gcloud config set project evocative-ethos-471602-r3`.

## 6. Running queries

**From the terminal (main workflow).** This saves results to `results/` automatically:

```bash
python scripts/run_sql.py sql/pipeline/01_sepsis_cohort.sql       # builds tables
python scripts/run_sql.py sql/checks/05_creatinine_urine.sql      # runs every block, saves CSVs
python scripts/run_sql.py sql/checks/08_feasibility.sql --only 08b_outcome_scenarios
python scripts/run_sql.py sql/checks/06_kidney_history_baseline.sql --dry-run   # estimate cost first
bash scripts/run_all.sh                                           # everything, in order
```

**Inside the editor (optional, for quick exploration).** The **BigQuery Runner** extension runs the open file, or the selected text, and shows results in a panel. Open the Command Palette (Cmd/Ctrl+Shift+P) and type "BigQuery Runner" to see its commands. If it asks for a project ID, use `evocative-ethos-471602-r3` (already set in `.vscode/settings.json`). Select a single `@query` block before running, since check files contain several queries.

Google also has an official BigQuery integration in the **Google Cloud Code** extension, but it's in preview and notebook-based, so the Python runner above is simpler for this project.

## 7. Cost

eICU tables are small by BigQuery standards: most checks scan well under 1 GB, and the first 1 TB scanned per month is free. Use `--dry-run` to check before running something new.

## 8. Put it on GitHub (private)

```bash
git init
git add .
git commit -m "Target trial SQL pipeline, checks, decisions and results"
```

Then create a **private** repository on GitHub, and follow its instructions to push. Before every commit, check that only SQL, docs and aggregated CSVs are included (`git status`). Never commit exported patient-level data.
