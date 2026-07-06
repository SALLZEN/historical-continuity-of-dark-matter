

# workspace_rooting

Shared root-resolution helpers for Python, R, and notebook bootstrap
code.

## Contract

- every computational workspace contains `config/workspace.json`
- helpers find the nearest ancestor containing that file
- helpers derive sibling paths from the resolved `workspace/` root
- launch cwd must not be the primary root-resolution mechanism
