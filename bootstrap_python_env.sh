#!/bin/zsh
set -euo pipefail
BUNDLE_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
VENV_DIR="$BUNDLE_ROOT/.venv"
LOCK_FILE="$BUNDLE_ROOT/historical-continuity/workspace/config/requirements.lock.txt"
if [[ -z "${PYTHON_BIN:-}" ]]; then
  if command -v python3.11 >/dev/null 2>&1; then
    PYTHON_BIN="python3.11"
  else
    PYTHON_BIN="python3"
  fi
fi
PYTHON_VERSION="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
case "$PYTHON_VERSION" in
  3.11|3.12|3.13) ;;
  *)
    echo "Unsupported Python version: $PYTHON_VERSION" >&2
    echo "This exported lock expects Python 3.11 or newer." >&2
    echo "Retry with, for example:" >&2
    echo "  PYTHON_BIN=python3.11 ./bootstrap_python_env.sh" >&2
    exit 1
    ;;
esac
if [[ ! -d "$VENV_DIR" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
"$VENV_DIR/bin/python" -m pip install -r "$LOCK_FILE"
echo "Bundle environment ready at $VENV_DIR"
echo "Launch notebooks with: $VENV_DIR/bin/python -m jupyter lab"
