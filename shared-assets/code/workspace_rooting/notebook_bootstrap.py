from pathlib import Path

from workspace_rooting.workspace_paths import canonical_workspace_paths

paths = canonical_workspace_paths(Path.cwd())
workspace_root = paths['workspace']
shared_assets_root = paths['shared_assets']

print('workspace_root:', workspace_root)
print('shared_assets_root:', shared_assets_root)
