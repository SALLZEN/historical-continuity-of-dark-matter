#!/bin/zsh
set -euo pipefail
BUNDLE_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
PYTHON_BIN="$BUNDLE_ROOT/.venv/bin/python"
KERNEL_NAME="historical-continuity-repo"
DISPLAY_NAME="historical-continuity-repo"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Missing interpreter: $PYTHON_BIN" >&2
  exit 1
fi
"$PYTHON_BIN" -m ipykernel install --user --name "$KERNEL_NAME" --display-name "$DISPLAY_NAME"
echo "Installed Jupyter kernel: $KERNEL_NAME"
