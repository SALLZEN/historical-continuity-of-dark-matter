from __future__ import annotations

from pathlib import Path
from typing import Dict

WORKSPACE_MARKER = Path('config/workspace.json')


def _as_path(start: str | Path) -> Path:
    return Path(start).resolve()


def find_workspace_root(start: str | Path) -> Path:
    start_path = _as_path(start)
    search_roots = [start_path, *start_path.parents]
    for candidate in search_roots:
        if (candidate / WORKSPACE_MARKER).exists():
            return candidate
    raise FileNotFoundError(
        f'Could not find workspace root above {start_path} using marker {WORKSPACE_MARKER}'
    )


def workspace_config_path(start: str | Path) -> Path:
    return find_workspace_root(start) / WORKSPACE_MARKER


def find_paper_root(start: str | Path) -> Path:
    return find_workspace_root(start).parent


def find_research_root(start: str | Path) -> Path:
    return find_paper_root(start).parent


def find_shared_assets_root(start: str | Path) -> Path:
    return find_research_root(start) / 'shared-assets'


def canonical_workspace_paths(start: str | Path) -> Dict[str, Path]:
    workspace_root = find_workspace_root(start)
    paper_root = workspace_root.parent
    research_root = paper_root.parent
    shared_assets_root = research_root / 'shared-assets'
    return {
        'workspace': workspace_root,
        'paper': paper_root,
        'research': research_root,
        'shared_assets': shared_assets_root,
        'code': workspace_root / 'code',
        'config': workspace_root / 'config',
        'data': workspace_root / 'data',
        'outputs': workspace_root / 'outputs',
        'docs': workspace_root / 'docs',
        'local': workspace_root / 'local',
        'paper_dir': paper_root / 'paper',
        'paper_outputs': paper_root / 'outputs',
        'overleaf': paper_root / 'overleaf',
    }
