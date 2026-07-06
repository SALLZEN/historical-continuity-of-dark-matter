#!/bin/zsh
set -euo pipefail
BUNDLE_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$BUNDLE_ROOT"
echo "==> Step 1/3: bootstrapping local Python environment"
./bootstrap_python_env.sh
echo ""
echo "==> Step 2/3: installing the bundle-local Jupyter kernel"
./install_repo_kernel.sh
echo ""
echo "==> Step 3/3: restoring R packages with renv"
R -q -e 'renv::restore(project = "historical-continuity/workspace", lockfile = "historical-continuity/workspace/renv.lock")'
echo ""
echo "Repository configuration complete."
echo "Next: read the bundle README and the paper/workspace READMEs for the rebuild order."
