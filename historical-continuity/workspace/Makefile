RSCRIPT ?= Rscript
PYTHON ?= ../../.venv/bin/python
JUPYTER_KERNEL ?= historical-continuity-repo
CONFIG ?= config/paths.yml

AVG_CITATIONS_PARQUET := data/derived/avg_citations_result.parquet
IMPACT_PDF := outputs/manuscript/figures/fig-impact.pdf
STRATUM_PDF := outputs/manuscript/figures/fig-stratum.pdf
ARXIV_PDF := outputs/manuscript/figures/fig-arxiv.pdf
LUNDMARK_IMAGE := outputs/manuscript/figures/lundmark_tabell.png
ADS_TABLE := outputs/manuscript/tables/ads_summary.tex
R_ASSETS_STAMP := outputs/manuscript/.r-assets-complete
RUNTIME_ROOT := $(CURDIR)/.runtime
EXECUTED_NOTEBOOK_DIR := $(RUNTIME_ROOT)/executed-notebooks
PREPARE_NOTEBOOK := code/notebooks/1.0.0-prepare_avg_citations.ipynb
IMPACT_NOTEBOOK := code/notebooks/2.0.0-build_impact_figure.ipynb

.PHONY: assets sync verify

assets: $(AVG_CITATIONS_PARQUET) $(IMPACT_PDF) $(R_ASSETS_STAMP) $(LUNDMARK_IMAGE)

$(EXECUTED_NOTEBOOK_DIR):
	mkdir -p $(EXECUTED_NOTEBOOK_DIR)

$(AVG_CITATIONS_PARQUET): $(PREPARE_NOTEBOOK) $(CONFIG) $(EXECUTED_NOTEBOOK_DIR)
	WORKSPACE_ROOT=$(CURDIR) $(PYTHON) -m jupyter nbconvert --to notebook --execute $(PREPARE_NOTEBOOK) --output 01_prepare_avg_citations.executed.ipynb --output-dir $(EXECUTED_NOTEBOOK_DIR) --ExecutePreprocessor.timeout=1200 --ExecutePreprocessor.kernel_name=$(JUPYTER_KERNEL)

$(IMPACT_PDF): $(IMPACT_NOTEBOOK) $(CONFIG) $(AVG_CITATIONS_PARQUET) $(EXECUTED_NOTEBOOK_DIR)
	WORKSPACE_ROOT=$(CURDIR) $(PYTHON) -m jupyter nbconvert --to notebook --execute $(IMPACT_NOTEBOOK) --output 02_build_impact_figure.executed.ipynb --output-dir $(EXECUTED_NOTEBOOK_DIR) --ExecutePreprocessor.timeout=1200 --ExecutePreprocessor.kernel_name=$(JUPYTER_KERNEL)

$(R_ASSETS_STAMP): code/scripts/3.0.0-build_manuscript_assets.R $(CONFIG)
	WORKSPACE_ROOT=$(CURDIR) $(RSCRIPT) code/scripts/3.0.0-build_manuscript_assets.R
	touch $@

$(LUNDMARK_IMAGE): $(CONFIG)
	mkdir -p $(dir $@)
	cp ../paper/assets/images/lundmark_tabell.png $@

sync: assets
	mkdir -p ../paper/assets/figures ../paper/assets/images ../paper/assets/tables ../overleaf/figures ../overleaf/tables
	cp $(IMPACT_PDF) ../paper/assets/figures/fig-impact.pdf
	cp $(STRATUM_PDF) ../paper/assets/figures/fig-stratum.pdf
	cp $(ARXIV_PDF) ../paper/assets/figures/fig-arxiv.pdf
	cp $(LUNDMARK_IMAGE) ../paper/assets/images/lundmark_tabell.png
	cp $(ADS_TABLE) ../paper/assets/tables/ads_summary.tex
	cp ../paper/assets/figures/fig-impact.pdf ../overleaf/figures/fig-impact.pdf
	cp ../paper/assets/figures/fig-stratum.pdf ../overleaf/figures/fig-stratum.pdf
	cp ../paper/assets/figures/fig-arxiv.pdf ../overleaf/figures/fig-arxiv.pdf
	cp ../paper/assets/images/lundmark_tabell.png ../overleaf/figures/lundmark_tabell.png
	cp ../paper/assets/tables/ads_summary.tex ../overleaf/tables/ads_summary.tex

verify:
	test -f $(PREPARE_NOTEBOOK)
	test -f $(IMPACT_NOTEBOOK)
	test -f $(AVG_CITATIONS_PARQUET)
	test -f $(IMPACT_PDF)
	test -f $(STRATUM_PDF)
	test -f $(ARXIV_PDF)
	test -f $(LUNDMARK_IMAGE)
	test -f $(ADS_TABLE)
	test -f ../paper/assets/figures/fig-impact.pdf
	test -f ../paper/assets/figures/fig-stratum.pdf
	test -f ../paper/assets/figures/fig-arxiv.pdf
	test -f ../paper/assets/images/lundmark_tabell.png
	test -f ../paper/assets/tables/ads_summary.tex
	test -f ../overleaf/figures/fig-impact.pdf
	test -f ../overleaf/figures/fig-stratum.pdf
	test -f ../overleaf/figures/fig-arxiv.pdf
	test -f ../overleaf/figures/lundmark_tabell.png
	test -f ../overleaf/tables/ads_summary.tex
