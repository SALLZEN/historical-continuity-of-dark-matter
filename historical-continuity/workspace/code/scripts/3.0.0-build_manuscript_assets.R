#!/usr/bin/env Rscript

# Manuscript-asset build for the historical-continuity workspace.
#
# The script reads the shared ADS backbone plus the local derived citation file,
# rebuilds the manuscript-facing figures and tables, syncs them into the
# authoritative `paper/assets/` surface, and mirrors Overleaf from there.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(forcats)
  library(ggplot2)
  library(ggsci)
  library(grid)
  library(patchwork)
  library(rcartocolor)
  library(scales)
  library(stringr)
  library(yaml)
})

script_path <- if (!is.null(sys.frames()[[1]]$ofile)) {
  normalizePath(sys.frames()[[1]]$ofile, winslash = "/", mustWork = TRUE)
} else {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE)
  } else {
    NA_character_
  }
}

script_dir <- if (!is.na(script_path)) {
  dirname(script_path)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

workspace_helper_candidates <- c(
  file.path(script_dir, "..", "..", "..", "..", "shared-assets", "code", "workspace_rooting", "workspace_paths.R"),
  file.path(script_dir, "..", "..", "..", "shared-assets", "code", "workspace_rooting", "workspace_paths.R")
)

workspace_helper <- vapply(
  workspace_helper_candidates,
  function(path) normalizePath(path, winslash = "/", mustWork = FALSE),
  character(1)
)
workspace_helper <- workspace_helper[file.exists(workspace_helper)][1]

if (is.na(workspace_helper) || !nzchar(workspace_helper)) {
  stop(
    paste(
      "Could not locate shared-assets/code/workspace_rooting/workspace_paths.R.",
      "Run this script from the workspace root or from code/scripts/, or execute it with Rscript."
    ),
    call. = FALSE
  )
}

source(workspace_helper)

paths <- canonical_workspace_paths(file.path(script_dir, "..", ".."))
workspace_dir <- normalizePath(paths$workspace, winslash = "/", mustWork = TRUE)
setwd(workspace_dir)
rplots_path <- file.path(workspace_dir, "Rplots.pdf")

# Keep the analysis surface singular: the authoritative build products live
# under `output/`, so any default-device spillover should be removed.
if (file.exists(rplots_path)) {
  unlink(rplots_path)
}
on.exit({
  if (file.exists(rplots_path)) {
    unlink(rplots_path)
  }
}, add = TRUE)

cat("Working directory:\n")
cat(workspace_dir, "\n\n")

# -------------------------------------------------------------------
# Step 2. Load data
# -------------------------------------------------------------------

papers_path <- file.path(paths$shared_assets, "data", "processed-data", "papers.parquet")
paper_metrics_long_path <- file.path(paths$shared_assets, "data", "processed-data", "paper_metrics_long.parquet")
paper_arxiv_classes_path <- file.path(paths$shared_assets, "data", "processed-data", "paper_arxiv_classes.parquet")
paper_citations_path <- file.path(paths$shared_assets, "data", "processed-data", "paper_citations.parquet")

ads_summary_tex_path <- file.path(paths$outputs, "manuscript", "tables", "ads_summary.tex")
stratum_plot_pdf_path <- file.path(paths$outputs, "manuscript", "figures", "fig-stratum.pdf")
arxiv_plot_pdf_path <- file.path(paths$outputs, "manuscript", "figures", "fig-arxiv.pdf")
arxiv_waffle_plot_pdf_path <- file.path(paths$outputs, "manuscript", "figures", "fig-arxiv-waffle.pdf")
arxiv_waffle_plot_wide_pdf_path <- file.path(paths$outputs, "manuscript", "figures", "fig-arxiv-waffle-wide.pdf")
bar_waffle_combo_plot_pdf_path <-  file.path(paths$outputs, "manuscript", "figures", "fig-bar_waffle_combo_plot.pdf")

dir.create(file.path(paths$outputs, "manuscript", "tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(paths$outputs, "manuscript", "figures"), recursive = TRUE, showWarnings = FALSE)

config_path <- file.path(paths$config, "paths.yml")
path_config <- yaml::read_yaml(config_path)

resolve_config_path <- function(specification) {
  path <- path.expand(as.character(specification))
  if (grepl("^/", path)) {
    return(normalizePath(path, winslash = "/", mustWork = FALSE))
  }
  normalizePath(file.path(workspace_dir, path), winslash = "/", mustWork = FALSE)
}

sync_figures_dir <- resolve_config_path(path_config$sync$figures_dir)
sync_images_dir <- resolve_config_path(path_config$sync$images_dir)
sync_tables_dir <- resolve_config_path(path_config$sync$tables_dir)
sync_overleaf_figures_dir <- resolve_config_path(path_config$sync$overleaf_figures_dir)
sync_overleaf_tables_dir <- resolve_config_path(path_config$sync$overleaf_tables_dir)
lundmark_source_path <- resolve_config_path(path_config$inputs$lundmark_image)

dir.create(sync_figures_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(sync_images_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(sync_tables_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(sync_overleaf_figures_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(sync_overleaf_tables_dir, recursive = TRUE, showWarnings = FALSE)

copy_rendered_asset <- function(source, targets) {
  source_norm <- normalizePath(source, winslash = "/", mustWork = TRUE)
  for (target in targets) {
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    target_norm <- normalizePath(target, winslash = "/", mustWork = FALSE)
    if (identical(source_norm, target_norm)) {
      next
    }
    file.copy(source_norm, target, overwrite = TRUE)
  }
}

sync_manuscript_asset <- function(source, paper_target, mirror_targets = character()) {
  copy_rendered_asset(source, c(paper_target))
  if (length(mirror_targets) > 0) {
    copy_rendered_asset(paper_target, mirror_targets)
  }
}

papers_data <- read_parquet(papers_path)
paper_metrics_long <- read_parquet(paper_metrics_long_path)
paper_arxiv_classes <- read_parquet(paper_arxiv_classes_path)
paper_citations <- read_parquet(paper_citations_path)

primary_arxiv_class <- paper_arxiv_classes |>
  arrange(bibcode, class_pos) |>
  distinct(bibcode, .keep_all = TRUE) |>
  select(bibcode, arxiv_class, arxiv_category)

paper_metadata <- papers_data |>
  select(bibcode, year, doctype) |>
  left_join(primary_arxiv_class, by = "bibcode")

# -------------------------------------------------------------------
# Step 3. Compute
# -------------------------------------------------------------------

total_papers <- nrow(papers_data)
first_year_in_corpus <- min(papers_data$year, na.rm = TRUE)
last_year_in_corpus <- max(papers_data$year, na.rm = TRUE)
arxiv_labeled_papers <- n_distinct(paper_arxiv_classes$bibcode)
unique_arxiv_classes <- n_distinct(paper_arxiv_classes$arxiv_class)

citation_rows <- paper_metrics_long |>
  filter(metric == "citations")

citations_by_paper <- citation_rows |>
  group_by(bibcode) |>
  summarise(total_citations = sum(value, na.rm = TRUE), .groups = "drop")

average_abstract_length <- round(mean(nchar(papers_data$abstract), na.rm = TRUE), 1)
average_total_citations <- round(mean(citations_by_paper$total_citations, na.rm = TRUE), 1)

coverage_summary <- data.frame(
  Metric = c(
    "Total papers",
    "Year range",
    "arXiv-labeled papers",
    "Unique arXiv classes",
    "Unique keywords"
  ),
  Value = c(
    as.character(total_papers),
    paste0(first_year_in_corpus, "--", last_year_in_corpus),
    as.character(arxiv_labeled_papers),
    as.character(unique_arxiv_classes),
    "Not available in local canonical data"
  ),
  stringsAsFactors = FALSE
)

averages_summary <- data.frame(
  Metric = c(
    "Distinct authors",
    "Avg. abstract length",
    "Avg. citations",
    "Avg. downloads",
    "Avg. reads"
  ),
  Value = c(
    "Not available in local canonical data",
    as.character(average_abstract_length),
    as.character(average_total_citations),
    "Not available in local canonical data",
    "Not available in local canonical data"
  ),
  stringsAsFactors = FALSE
)

bh_id <- "2018RvMP...90d5002B"

bh_citers <- paper_citations |>
  filter(bibcode == bh_id) |>
  distinct(citing_bibcode)

bh_citers_meta <- bh_citers |>
  left_join(
    paper_metadata,
    by = c("citing_bibcode" = "bibcode")
  )

arxiv_plot_data <- bh_citers_meta |>
  filter(!is.na(arxiv_category)) |>
  filter(!arxiv_category %in% c("nuclear physics", "quantum physics")) |>
  count(arxiv_category, arxiv_class, name = "n") |>
  group_by(arxiv_category) |>
  mutate(total_n = sum(n)) |>
  ungroup()

category_order <- arxiv_plot_data |>
  distinct(arxiv_category, total_n) |>
  arrange(desc(total_n), arxiv_category) |>
  pull(arxiv_category)

arxiv_plot_data <- arxiv_plot_data |>
  mutate(
    arxiv_category = factor(as.character(arxiv_category), levels = category_order),
    category_label = factor(as.character(arxiv_category), levels = category_order),
    subclass_share = n / total_n
  ) |>
  ungroup()

category_palette_names <- c(
  "astrophysics" = "pink",
  "high-energy physics" = "cyan",
  "general relativity and quantum cosmology" = "indigo",
  "physics" = "amber"
)

build_family_palette <- function(data, palette_name) {
  ordered_classes <- data |>
    arrange(n, arxiv_class) |>
    pull(arxiv_class)

  n_classes <- length(ordered_classes)
  full_gradient <- ggsci::pal_material(palette = palette_name)(10)

  if (n_classes == 1) {
    family_colors <- full_gradient[7]
  } else {
    family_colors <- grDevices::colorRampPalette(full_gradient[2:10])(n_classes)
  }

  stats::setNames(family_colors, ordered_classes)
}

hex_luminance <- function(colors) {
  rgb_matrix <- grDevices::col2rgb(colors)
  as.numeric(c(0.2126, 0.7152, 0.0722) %*% rgb_matrix)
}

class_palette_list <- split(
  arxiv_plot_data,
  factor(arxiv_plot_data$arxiv_category, levels = category_order)
) |>
  lapply(function(category_data) {
    palette_name <- category_palette_names[[as.character(category_data$arxiv_category[[1]])]]
    build_family_palette(category_data, palette_name)
  })

class_palette <- do.call(c, unname(class_palette_list))
category_palette <- stats::setNames(
  vapply(
    class_palette_list,
    function(palette_vec) unname(palette_vec[[length(palette_vec)]]),
    character(1)
  ),
  names(class_palette_list)
)

category_levels <- rev(category_order)

category_totals <- arxiv_plot_data |>
  distinct(arxiv_category, total_n) |>
  mutate(
    category_label = as.character(arxiv_category),
    arxiv_category = factor(as.character(arxiv_category), levels = category_levels),
    category_label = factor(category_label, levels = category_levels)
  )

max_legend_columns <- max(lengths(class_palette_list))

legend_plot_data <- do.call(
  rbind,
  lapply(seq_along(rev(class_palette_list)), function(i) {
    category_classes <- rev(class_palette_list)[[i]]
    ordered_class_names <- rev(names(category_classes))
    ordered_fill_colors <- rev(unname(category_classes))
    class_positions <- seq_along(ordered_class_names)

    data.frame(
      row_id = i,
      class_name = ordered_class_names,
      fill_color = ordered_fill_colors,
      class_position = class_positions,
      stringsAsFactors = FALSE
    )
  })
)

class_order <- arxiv_plot_data |>
  mutate(
    arxiv_category = factor(arxiv_category, levels = category_order),
    class_color = unname(class_palette[as.character(arxiv_class)]),
    class_luminance = hex_luminance(class_color)
  ) |>
  arrange(desc(total_n), arxiv_category, desc(n), class_luminance, arxiv_class) |>
  pull(arxiv_class)

class_label_data <- arxiv_plot_data |>
  mutate(
    arxiv_category = factor(arxiv_category, levels = category_order),
    arxiv_class = factor(arxiv_class, levels = class_order),
    legend_label = paste0(as.character(arxiv_class), " (n = ", scales::comma(n), ")")
  ) |>
  arrange(arxiv_class) |>
  select(arxiv_class, legend_label)

class_label_map <- stats::setNames(
  class_label_data$legend_label,
  as.character(class_label_data$arxiv_class)
)

arxiv_plot_data <- arxiv_plot_data |>
  mutate(
    arxiv_category = factor(arxiv_category, levels = category_levels),
    category_label = factor(as.character(category_label), levels = category_levels),
    arxiv_class = factor(arxiv_class, levels = class_order)
  ) |>
  arrange(desc(total_n), arxiv_category, desc(n), arxiv_class)

allocate_squares <- function(shares, total_squares = 100) {
  raw_squares <- shares / sum(shares) * total_squares
  base_squares <- floor(raw_squares)
  remainder <- total_squares - sum(base_squares)

  if (remainder > 0) {
    promote_idx <- order(raw_squares - base_squares, decreasing = TRUE)[seq_len(remainder)]
    base_squares[promote_idx] <- base_squares[promote_idx] + 1L
  }

  if (remainder < 0) {
    demote_idx <- order(raw_squares - base_squares, decreasing = FALSE)[seq_len(abs(remainder))]
    base_squares[demote_idx] <- pmax(0L, base_squares[demote_idx] - 1L)
  }

  as.integer(base_squares)
}

choose_total_squares <- function(weights, max_total_squares = Inf) {
  total_weight <- as.integer(round(sum(weights)))

  if (is.infinite(max_total_squares)) {
    return(total_weight)
  }

  min(total_weight, as.integer(max_total_squares))
}

make_waffle_tiles <- function(data,
                              n_cols = 20,
                              normalized = FALSE,
                              squares_per_category = 100) {
  base_data <- data |>
    mutate(
      arxiv_category = factor(as.character(arxiv_category), levels = category_order),
      category_label = factor(as.character(category_label), levels = category_order),
      class_color = unname(class_palette[as.character(arxiv_class)]),
      class_luminance = hex_luminance(class_color)
    ) |>
    arrange(desc(total_n), arxiv_category, desc(n), class_luminance, arxiv_class) |>
    group_by(arxiv_category, category_label, total_n) |>
    mutate(
      tile_n = if (normalized) {
        allocate_squares(subclass_share, total_squares = squares_per_category)
      } else {
        n
      }
    ) |>
    ungroup()

  label_data <- base_data |>
    distinct(arxiv_category, category_label, total_n) |>
    arrange(desc(total_n), arxiv_category) |>
    mutate(
      category_label_wrapped = stringr::str_wrap(as.character(category_label), width = 26),
      panel_label = if (normalized) {
        paste0(category_label_wrapped, "\n(100-square composition)")
      } else {
        paste0(category_label_wrapped, "\n(n = ", scales::comma(total_n), ")")
      }
    )

  base_data |>
    tidyr::uncount(tile_n) |>
    left_join(label_data, by = c("arxiv_category", "category_label", "total_n")) |>
    mutate(
      panel_label = factor(panel_label, levels = label_data$panel_label)
    ) |>
    select(-class_color, -class_luminance) |>
    group_by(arxiv_category) |>
    mutate(
      tile_id = row_number(),
      x = ((tile_id - 1L) %% n_cols) + 1L,
      y = ceiling(tile_id / n_cols)
    ) |>
    ungroup()
}

make_total_normalized_waffle_tiles <- function(data,
                                               n_cols = 25,
                                               total_squares = NULL,
                                               max_total_squares = Inf) {
  if (is.null(total_squares)) {
    total_squares <- choose_total_squares(
      data$n,
      max_total_squares = max_total_squares
    )
  }

  base_data <- data |>
    mutate(
      arxiv_category = factor(as.character(arxiv_category), levels = category_order),
      category_label = factor(as.character(category_label), levels = category_order),
      class_color = unname(class_palette[as.character(arxiv_class)]),
      class_luminance = hex_luminance(class_color),
      tile_n = allocate_squares(n, total_squares = total_squares)
    ) |>
    arrange(desc(total_n), arxiv_category, desc(n), class_luminance, arxiv_class) |>
    select(-class_color, -class_luminance)

  base_data |>
    tidyr::uncount(tile_n) |>
    mutate(
      tile_id = row_number(),
      x = ((tile_id - 1L) %% n_cols) + 1L,
      y = ceiling(tile_id / n_cols)
    )
}

waffle_fill_scale <- function() {
  scale_fill_manual(
    values = class_palette,
    breaks = class_order,
    labels = class_label_map[class_order],
    drop = FALSE
  )
}

waffle_legend_guide <- function(ncol = 1) {
  guide_legend(
    ncol = ncol,
    byrow = TRUE,
    title.position = "top",
    keyheight = grid::unit(0.88, "lines"),
    keywidth = grid::unit(0.75, "lines"),
    override.aes = list(color = NA)
  )
}

waffle_plot_theme <- function(base_size = 8, show_legend = TRUE) {
  theme_minimal(base_size = base_size) +
    theme(
      panel.grid = element_blank(),
      axis.title = element_blank(),
      axis.text = element_blank(),
      axis.ticks = element_blank(),
      legend.position = if (show_legend) "right" else "none",
      legend.title = element_blank(),
      legend.text = element_text(size = rel(1.0), lineheight = 0.96),
      legend.box = "vertical",
      legend.justification = "left",
      legend.margin = margin(t = 3, l = 0),
      legend.spacing.x = grid::unit(0.10, "lines"),
      legend.spacing.y = grid::unit(0.10, "lines"),
      plot.title.position = "plot",
      plot.caption.position = "plot"
    )
}

plot_arxiv_waffle <- function(tile_data,
                              title = NULL,
                              subtitle = NULL,
                              caption = NULL,
                              ncol = 4) {
  tile_data <- tile_data |>
    mutate(panel_label = forcats::fct_rev(panel_label))

  ggplot(tile_data, aes(x = x, y = y, fill = arxiv_class)) +
    geom_tile(
      color = "white",
      linewidth = 0.05,
      width = 0.96,
      height = 0.96,
      alpha = 0.85
    ) +
    coord_equal() +
    facet_wrap(~ panel_label, ncol = ncol, scales = "fixed") +
    waffle_fill_scale() +
    scale_x_continuous(expand = expansion(mult = c(0.01, 0.01))) +
    scale_y_continuous(expand = expansion(mult = c(0.01, 0.01))) +
    labs(
      title = title,
      subtitle = subtitle,
      caption = caption,
      fill = "arXiv class"
    ) +
    waffle_plot_theme(show_legend = FALSE) +
    theme(
      strip.text = element_text(size = 9.5, lineheight = 1.0)
    )
}

plot_arxiv_single_waffle <- function(tile_data,
                                     title = NULL,
                                     subtitle = NULL,
                                     caption = NULL) {
  ggplot(tile_data, aes(x = x, y = y, fill = arxiv_class)) +
    geom_tile(
      color = "white",
      linewidth = 0.15,
      width = 0.96,
      height = 0.96,
      alpha = 0.85
    ) +
    coord_equal() +
    waffle_fill_scale() +
    scale_x_continuous(expand = expansion(mult = c(0.01, 0.01))) +
    scale_y_continuous(expand = expansion(mult = c(0.01, 0.01))) +
    labs(
      title = title,
      subtitle = subtitle,
      caption = caption,
      fill = "arXiv class"
    ) +
    waffle_plot_theme(show_legend = TRUE) +
    guides(fill = waffle_legend_guide(ncol = 1)) +
    theme(
      legend.key.height = grid::unit(0.72, "lines"),
      legend.key.width = grid::unit(0.60, "lines")
    )
}

bh_canon_pre1960 <- paper_citations |>
  filter(citing_bibcode == bh_id) |>
  distinct(bibcode) |>
  mutate(ref_year = suppressWarnings(as.integer(str_sub(bibcode, 1, 4)))) |>
  filter(!is.na(ref_year), ref_year >= 1800, ref_year <= 1960) |>
  pull(bibcode) |>
  unique()

papers_universe <- paper_metadata |>
  filter(year >= 2018) |>
  filter(doctype %in% c("article", "eprint")) |>
  filter(!is.na(arxiv_category)) |>
  transmute(
    citing_bibcode = bibcode,
    year,
    doctype,
    arxiv_category
  ) |>
  mutate(is_bh_citer = citing_bibcode %in% bh_citers$citing_bibcode)

refs_universe <- paper_citations |>
  semi_join(papers_universe |> select(citing_bibcode), by = "citing_bibcode") |>
  transmute(
    citing_bibcode,
    bibcode,
    ref_year = suppressWarnings(as.integer(str_sub(bibcode, 1, 4)))
  ) |>
  filter(!is.na(ref_year), ref_year >= 1800, ref_year <= 2025)

paper_canon_signals <- refs_universe |>
  group_by(citing_bibcode) |>
  summarise(
    n_refs_with_year = n(),
    n_pre1960 = sum(ref_year <= 1960, na.rm = TRUE),
    n_canon_pre1960 = sum(bibcode %in% bh_canon_pre1960, na.rm = TRUE),
    any_pre1960 = n_pre1960 > 0,
    any_canon_pre1960 = n_canon_pre1960 > 0,
    .groups = "drop"
  ) |>
  left_join(papers_universe, by = "citing_bibcode") |>
  mutate(
    year_bin = cut(
      year,
      breaks = c(2018, 2020, 2022, 2024, 2026),
      right = FALSE,
      labels = c("2018–2019", "2020–2021", "2022–2023", "2024–2025")
    ),
    log_refs = log1p(n_refs_with_year),
    stratum = interaction(year_bin, arxiv_category, drop = TRUE)
  )

keep_categories <- c(
  "astrophysics",
  "high-energy physics",
  "general relativity and quantum cosmology",
  "physics",
  "nuclear physics",
  "quantum physics"
)

paper_canon_signals <- paper_canon_signals |>
  filter(arxiv_category %in% keep_categories) |>
  mutate(arxiv_category = factor(arxiv_category, levels = rev(keep_categories)))

canon_model <- glm(
  any_canon_pre1960 ~ is_bh_citer + log_refs + stratum,
  data = paper_canon_signals,
  family = binomial()
)

stratum_meta <- paper_canon_signals |>
  group_by(stratum, year_bin, arxiv_category) |>
  summarise(
    mean_log_refs = mean(log_refs, na.rm = TRUE),
    n_bh = sum(is_bh_citer, na.rm = TRUE),
    n_nonbh = sum(!is_bh_citer, na.rm = TRUE),
    .groups = "drop"
  ) |>
  filter(n_bh >= 10, n_nonbh >= 100)

bh_false_predictions <- predict(
  canon_model,
  newdata = stratum_meta |> mutate(is_bh_citer = FALSE, log_refs = mean_log_refs),
  type = "response"
)

bh_true_predictions <- predict(
  canon_model,
  newdata = stratum_meta |> mutate(is_bh_citer = TRUE, log_refs = mean_log_refs),
  type = "response"
)

stratum_plot_data <- stratum_meta |>
  mutate(diff_adj = bh_true_predictions - bh_false_predictions)

# -------------------------------------------------------------------
# Step 4. Print checks
# -------------------------------------------------------------------

cat("Coverage summary:\n")
print(coverage_summary)
cat("\n")

cat("Average-style summary:\n")
print(averages_summary)
cat("\n")

cat("Data checks:\n")
cat("papers rows:", nrow(papers_data), "\n")
cat("paper_metrics_long rows:", nrow(paper_metrics_long), "\n")
cat("paper_arxiv_classes rows:", nrow(paper_arxiv_classes), "\n")
cat("paper_citations rows:", nrow(paper_citations), "\n")
cat("BH citers:", nrow(bh_citers), "\n")
cat("BH pre-1960 canon references:", length(bh_canon_pre1960), "\n")
cat("arXiv plot rows:", nrow(arxiv_plot_data), "\n")
cat("stratum plot rows:", nrow(stratum_plot_data), "\n")
cat("papers columns:", paste(names(papers_data), collapse = ", "), "\n")
cat("paper_citations columns:", paste(names(paper_citations), collapse = ", "), "\n\n")

cat("Stratum plot data preview:\n")
print(stratum_plot_data)
cat("\n")

# -------------------------------------------------------------------
# Step 5. Plot
# -------------------------------------------------------------------

two_panel_left <- 
ggplot(
  category_totals,
  aes(x = total_n, y = category_label, fill = arxiv_category)
) +
  coord_flip() +
  geom_col(width = 0.55, alpha = 0.75) +
  geom_text(
    aes(label = total_n),
    hjust = 0.5,
    vjust = 2.0,
    size = 3.6,
    color = "white"
  ) +
  geom_label(
    aes(label = stringr::str_wrap(as.character(category_label), width = 25)),
    hjust = 0.5,
    nudge_x = 12,
    lineheight = 0.95,
    size = 2.2,
    color = "black",
    fill = "white",
    border.color = "white"
  ) +
  scale_y_discrete(labels = NULL) +
  scale_x_continuous(
    labels = comma,
    breaks = c(0, 50, 100, 150, 200, 250),
    expand = expansion(mult = c(0, 0.1))
  ) +
  scale_fill_manual(values = category_palette) +
  labs(
    x = "Citations",
    y = NULL,
    title = "Category totals"
  ) +
  theme_minimal(base_family = "Helvetica") +
  theme(
    axis.title = element_text(size = 7),
    axis.ticks.y = element_blank(),
    legend.position = "none",
    panel.grid.minor.x = element_blank(),
    panel.grid.minor.y = element_blank(),
    panel.grid.major.x = element_blank(),
    plot.title = element_text(size = 10)
  )

two_panel_right <- ggplot(
  arxiv_plot_data,
  aes(x = subclass_share, y = category_label, fill = arxiv_class)
) +
  geom_col(width = 0.55, color = "white", linewidth = 0.25, alpha = 0.75) +
  scale_x_continuous(
    labels = percent_format(accuracy = 1),
    expand = expansion(mult = c(0, 0.01))
  ) +
  scale_y_discrete(labels = scales::label_wrap(15)) +
  scale_fill_manual(values = class_palette) +
  labs(
    x = "Within-category share",
    y = NULL,
    title = "Subclass composition by category",
    fill = NULL
  ) +
  theme_minimal(base_family = "Helvetica") +
  theme(
    axis.title = element_text(size = 7),
    panel.grid.minor.x = element_blank(),
    plot.title = element_text(size = 10),
    legend.position = "none"
  )


custom_legend_plot <- ggplot() +
  geom_tile(
    data = legend_plot_data,
    aes(
      x = class_position,
      y = -row_id,
      fill = fill_color
    ),
    width = 0.18,
    height = 0.55,
    show.legend = FALSE
  ) +
  geom_text(
    data = legend_plot_data,
    aes(
      x = class_position + 0.12,
      y = -row_id,
      label = class_name
    ),
    hjust = 0,
    size = 2.7
  ) +
  scale_fill_identity() +
  scale_x_continuous(
    limits = c(0.7, max_legend_columns + 1.15),
    expand = c(0, 0)
  ) +
  scale_y_continuous(
    limits = c(-length(class_palette_list) - 0.5, 0),
    expand = c(0, 0)
  ) +
  coord_cartesian(clip = "off") +
  theme_void() +
  theme(
    plot.margin = grid::unit(c(0, 0, 0, 0), "pt")
  )

two_panel_main <- two_panel_left + two_panel_right +
  plot_layout(
    axes = "collect_y",
    widths = c(1.0, 1.5)
  )

arxiv_plot <- two_panel_main / custom_legend_plot +
  plot_layout(heights = c(1, 0.34))

absolute_tiles <- make_waffle_tiles(
  arxiv_plot_data,
  n_cols = 13,
  normalized = FALSE
)

absolute_waffle_plot <- plot_arxiv_waffle(
  absolute_tiles,
  title = NULL,
  subtitle = NULL,
  caption = NULL
)

normalized_tiles <- make_total_normalized_waffle_tiles(
  arxiv_plot_data,
  n_cols = 25,
  max_total_squares = 500
)

normalized_waffle_plot <- plot_arxiv_single_waffle(
  normalized_tiles,
  title = "arXiv class resolution",
  subtitle = NULL,
  caption = NULL
)

waffle_design <- "
AAAAA
BBBB#
"

arxiv_waffle_plot <- absolute_waffle_plot / normalized_waffle_plot +
  plot_layout(
    design = waffle_design,
    heights = c(11, 16.2),
    widths = c(0.9, 1, 1, 1, 0.1),
    guides = "keep"
  )

arxiv_waffle_plot_wide <- absolute_waffle_plot + normalized_waffle_plot + guide_area() +
  plot_layout(
    heights = c(5),
    widths = c(18, 9, 3),
    guides = "collect"
  )

bar_waffle_combo <- two_panel_left + normalized_waffle_plot +
  plot_layout(widths = c(1.0, 1.25))


stratum_plot <- ggplot(
  stratum_plot_data,
  aes(x = diff_adj, y = arxiv_category, size = n_bh, color = arxiv_category)
) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.3) +
  geom_point(alpha = 0.85) +
  facet_grid(~ year_bin) +
  scale_y_discrete(labels = scales::label_wrap(15)) +
  scale_x_continuous(
    labels = percent_format(accuracy = 1),
    breaks = seq(0.0, 0.10, by = 0.02)
  ) +
  coord_cartesian(xlim = c(0.0, 0.10)) +
  scale_color_manual(values = category_palette) +
  scale_size_continuous(range = c(5, 15), name = "# BH-citing papers") +
  guides(
    color = "none",
    size = guide_legend(
      title = "# papers:",
      position = "bottom",
      title.position = "left",
      nrow = 1
    )
  ) +
  theme_minimal(base_family = "Helvetica") +
  labs(
    x = expression(Delta * Pr("cites" >= 1 ~ "BH pre-1960 canon ref | citing BH")),
    y = NULL,
    title = "Length-adjusted canon uptake among BH citers"
  ) +
  theme(
    panel.grid.minor.x = element_blank(),
    plot.title = element_text(size = 11, hjust = 0.5),
    axis.text.x = element_text(size = 8.5, hjust = 0.2),
    axis.text.y = element_text(size = 9, lineheight = 0.96),
    strip.text.x = element_text(size = 9.5, hjust = 0.5),
    strip.text.y = element_text(angle = 0),
    axis.title.x = element_text(size = 10),
    legend.title = element_text(size = 10),
    legend.text = element_text(size = 10)
  )

# -------------------------------------------------------------------
# Step 6. Display
# -------------------------------------------------------------------

print(stratum_plot)
print(arxiv_plot)
print(arxiv_waffle_plot)
print(bar_waffle_combo)

# -------------------------------------------------------------------
# Step 7. Save
# -------------------------------------------------------------------

latex_escape <- function(value) {
  value <- gsub("\\\\", "\\\\textbackslash{}", value, fixed = TRUE)
  gsub("([%&_#{}])", "\\\\\\1", value, perl = TRUE)
}

coverage_rows <- paste0(
  latex_escape(coverage_summary$Metric),
  " & ",
  latex_escape(coverage_summary$Value),
  "\\\\",
  collapse = "\n"
)

averages_rows <- paste0(
  latex_escape(averages_summary$Metric),
  " & ",
  latex_escape(averages_summary$Value),
  "\\\\",
  collapse = "\n"
)

ads_summary_latex <- paste(
  "\\begin{table}[H]",
  "\\centering",
  "\\caption{\\label{tab:tbl-table}ADS dataset summary: Counts and coverage}",
  "\\fontsize{9}{11}\\selectfont",
  "\\begin{tabular}[t]{>{\\raggedright\\arraybackslash}p{5cm}>{\\raggedleft\\arraybackslash}p{7cm}}",
  "\\toprule",
  "Metric & Value\\\\",
  "\\midrule",
  coverage_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{table}",
  "",
  "\\begin{table}[H]",
  "\\centering",
  "\\caption{\\label{tab:tbl-table-averages}ADS dataset summary: Averages}",
  "\\fontsize{9}{11}\\selectfont",
  "\\begin{tabular}[t]{>{\\raggedright\\arraybackslash}p{5cm}>{\\raggedleft\\arraybackslash}p{7cm}}",
  "\\toprule",
  "Metric & Value\\\\",
  "\\midrule",
  averages_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{table}%",
  sep = "\n"
)

writeLines(ads_summary_latex, ads_summary_tex_path, useBytes = TRUE)

grDevices::pdf(stratum_plot_pdf_path, width = 11, height = 6, onefile = FALSE)
print(stratum_plot)
grDevices::dev.off()

grDevices::pdf(arxiv_plot_pdf_path, width = 11.2, height = 4.3, onefile = FALSE)
print(bar_waffle_combo)
grDevices::dev.off()

grDevices::pdf(arxiv_waffle_plot_pdf_path, width = 6, height = 7, onefile = FALSE)
print(arxiv_waffle_plot)
grDevices::dev.off()

grDevices::pdf(arxiv_waffle_plot_wide_pdf_path, width = 13.4, height = 4, onefile = FALSE)
print(arxiv_waffle_plot_wide)
grDevices::dev.off()

grDevices::pdf(bar_waffle_combo_plot_pdf_path, width = 11.2, height = 4.3, onefile = FALSE)
print(bar_waffle_combo)
grDevices::dev.off()

sync_manuscript_asset(
  ads_summary_tex_path,
  file.path(sync_tables_dir, "ads_summary.tex"),
  c(file.path(sync_overleaf_tables_dir, "ads_summary.tex"))
)

sync_manuscript_asset(
  stratum_plot_pdf_path,
  file.path(sync_figures_dir, "fig-stratum.pdf"),
  c(file.path(sync_overleaf_figures_dir, "fig-stratum.pdf"))
)

sync_manuscript_asset(
  arxiv_plot_pdf_path,
  file.path(sync_figures_dir, "fig-arxiv.pdf"),
  c(file.path(sync_overleaf_figures_dir, "fig-arxiv.pdf"))
)

sync_manuscript_asset(
  arxiv_waffle_plot_pdf_path,
  file.path(sync_figures_dir, "fig-arxiv-waffle.pdf"),
  c(file.path(sync_overleaf_figures_dir, "fig-arxiv-waffle.pdf"))
)

sync_manuscript_asset(
  arxiv_waffle_plot_wide_pdf_path,
  file.path(sync_figures_dir, "fig-arxiv-waffle-wide.pdf"),
  c(file.path(sync_overleaf_figures_dir, "fig-arxiv-waffle-wide.pdf"))
)

sync_manuscript_asset(
  bar_waffle_combo_plot_pdf_path,
  file.path(sync_figures_dir, "fig-bar_waffle_combo_plot.pdf"),
  c(file.path(sync_overleaf_figures_dir, "fig-bar_waffle_combo_plot.pdf"))
)

sync_manuscript_asset(
  lundmark_source_path,
  file.path(sync_images_dir, "lundmark_tabell.png"),
  c(file.path(sync_overleaf_figures_dir, "lundmark_tabell.png"))
)


cat("Saved files:\n")
cat(ads_summary_tex_path, "\n")
cat(stratum_plot_pdf_path, "\n")
cat(arxiv_plot_pdf_path, "\n")
cat(arxiv_waffle_plot_pdf_path, "\n")
cat(arxiv_waffle_plot_wide_pdf_path, "\n")
cat(bar_waffle_combo_plot_pdf_path, "\n")
cat("Synced copies:\n")
cat(file.path(sync_figures_dir, "fig-stratum.pdf"), "\n")
cat(file.path(sync_overleaf_figures_dir, "fig-stratum.pdf"), "\n")

# A few plotting code paths can still trigger R's default graphics device.
# Clean it up here so the analysis root stays free of stray artifacts.
grDevices::graphics.off()
if (file.exists(rplots_path)) {
  unlink(rplots_path)
}
