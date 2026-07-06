workspace_marker <- function() {
  file.path('config', 'workspace.json')
}

find_workspace_root <- function(start = getwd()) {
  candidate <- normalizePath(start, winslash = '/', mustWork = TRUE)
  search_roots <- c(candidate, dirname(candidate))

  while (TRUE) {
    marker <- file.path(candidate, workspace_marker())
    if (file.exists(marker)) {
      return(candidate)
    }

    parent <- dirname(candidate)
    if (identical(parent, candidate)) {
      stop(
        paste('Could not find workspace root above', start, 'using marker', workspace_marker()),
        call. = FALSE
      )
    }
    candidate <- parent
  }
}

workspace_config_path <- function(start = getwd()) {
  file.path(find_workspace_root(start), workspace_marker())
}

find_paper_root <- function(start = getwd()) {
  dirname(find_workspace_root(start))
}

find_research_root <- function(start = getwd()) {
  dirname(find_paper_root(start))
}

find_shared_assets_root <- function(start = getwd()) {
  file.path(find_research_root(start), 'shared-assets')
}

canonical_workspace_paths <- function(start = getwd()) {
  workspace_root <- find_workspace_root(start)
  paper_root <- dirname(workspace_root)
  research_root <- dirname(paper_root)
  shared_assets_root <- file.path(research_root, 'shared-assets')

  list(
    workspace = workspace_root,
    paper = paper_root,
    research = research_root,
    shared_assets = shared_assets_root,
    code = file.path(workspace_root, 'code'),
    config = file.path(workspace_root, 'config'),
    data = file.path(workspace_root, 'data'),
    outputs = file.path(workspace_root, 'outputs'),
    docs = file.path(workspace_root, 'docs'),
    local = file.path(workspace_root, 'local'),
    paper_dir = file.path(paper_root, 'paper'),
    paper_outputs = file.path(paper_root, 'outputs'),
    overleaf = file.path(paper_root, 'overleaf')
  )
}
