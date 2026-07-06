

<br>

## Historical Continuity as Justification for Dark Matter

This is a paper on the historical continuity of dark matter research,
with a focus on the epistemic role that history can play in the
justification of dark matter. The paper is partially based on a
computational analysis of the scientific literature on dark matter,
using bibliometric and text mining techniques to trace the development
of the field over time.

Status: computational paper.

## Authoritative entrypoints

- manuscript: `paper/main.qmd`
- computational companion: `workspace/`
- rebuildable analytical and manuscript outputs are omitted in repo mode
- explicit repo-mode exceptions remain under `workspace/outputs/`

## Shared dependencies

- shared ADS backbone via `../shared-assets/data/processed-data/`

## Derived local data

- rebuildable citation-ranking parquet via
  `workspace/data/derived/avg_citations_result.parquet`

## Runtime contract

- Python notebooks: `workspace/code/notebooks/`
- R manuscript-asset build:
  `workspace/code/scripts/3.0.0-build_manuscript_assets.R`
- Python environment contract: `workspace/config/requirements.txt`
- R environment contract: `workspace/config/requirements-R.txt`
- R lockfile: `workspace/config/renv.lock`
- R package manifest: `workspace/config/DESCRIPTION`
- bundle-local Python habitat: `../.venv/`, created by `../configure_repo.sh` (or `../bootstrap_python_env.sh` if you are setting things up manually)
- restore R dependencies in-paper with `renv::restore()`

## Build contract

- shared inputs are read through `workspace/config/paths.yml`
- paper-local derived data is written to `workspace/data/derived/`
- manuscript-facing figures and tables are rebuilt under
  `workspace/outputs/manuscript/`
- `paper/assets/` is the authoritative manuscript asset surface
- `overleaf/` mirrors the authoritative files from `paper/assets/`

## Standalone bundle notes

- this directory already lives inside a standalone export bundle
- start at the bundle-root `README.md` for setup and rebuild order
- shared-resource provenance for this exported copy is recorded in `../manifest.resolved.json`