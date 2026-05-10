# CONSORT plotting helpers for CohortPipeline.
#
# Kept in a separate file from the class definition so the plotting code
# is easy to locate and test. The public entry point is the class method
# CohortPipeline$draw_consort_panels(); these functions implement it.
#
# Read-only access to the internal node store is passed in as the `nodes`
# argument, so this file does not depend on R6 private state.

#' @keywords internal
.draw_consort_panels_impl <- function(panels, nodes, file = NULL,
                                      ncol = NULL, width = NULL, height = NULL,
                                      text_width = 40, title_fontsize = 14) {
  if (!is.list(panels) || length(panels) == 0L) {
    stop("draw_consort_panels: 'panels' must be a non-empty list.",
      call. = FALSE)
  }

  panel_grobs <- lapply(seq_along(panels), function(i) {
    spec  <- panels[[i]]
    title <- names(panels)[i] %||% sprintf("Panel %d", i)
    if (is.list(spec) && !is.null(spec$flow)) {
      flow <- spec$flow
      sb   <- spec$side_branches %||% list()
    } else {
      flow <- spec
      sb   <- list()
    }
    body <- .build_consort_obj(flow, sb, nodes, text_width)
    body_grob <- grid::grid.grabExpr(plot(body, grViz = FALSE), warn = 0)
    grid::gTree(children = grid::gList(
      grid::textGrob(
        title, x = 0.5, y = 0.985, hjust = 0.5, vjust = 1,
        gp = grid::gpar(fontsize = title_fontsize, fontface = "bold")
      ),
      grid::editGrob(body_grob, vp = grid::viewport(
        x = 0.5, y = 0.95, width = 0.86, height = 0.93,
        just = c("center", "top")
      ))
    ))
  })

  ncol_use <- ncol %||% length(panels)
  nrow_use <- ceiling(length(panels) / ncol_use)
  width_use <- width %||% (6 * ncol_use)

  content_rows <- vapply(panels, function(p) {
    fl <- if (is.list(p) && !is.null(p$flow)) p$flow else p
    cohort_rows <- length(fl) + 1L
    bullet_rows <- sum(vapply(unname(fl), function(co) {
      nd <- nodes[[co]]
      if (is.null(nd)) 0L else .own_log_n(nd)
    }, integer(1L)))
    cohort_rows + bullet_rows
  }, integer(1L))
  height_use <- height %||% max(9, 2 + 0.55 * max(content_rows) * nrow_use)

  if (!is.null(file)) {
    ext <- tools::file_ext(file)
    if (identical(ext, "pdf")) {
      grDevices::pdf(file, width = width_use, height = height_use)
    } else if (identical(ext, "png")) {
      grDevices::png(file, width = width_use, height = height_use,
        units = "in", res = 150)
    } else {
      stop("draw_consort_panels: unsupported file extension: .", ext,
        call. = FALSE)
    }
    on.exit(grDevices::dev.off(), add = TRUE)
  }

  gridExtra::grid.arrange(grobs = panel_grobs, ncol = ncol_use)
  invisible(panel_grobs)
}

# Number of own (non-inherited) log entries on a node.
#' @keywords internal
.own_log_n <- function(node) {
  length(node$log_entries) - (node$branched_at_log_len %||% 0L)
}

# Return the node's own (non-inherited) log entries as a data.table.
#' @keywords internal
.own_log <- function(node) {
  start <- (node$branched_at_log_len %||% 0L) + 1L
  end   <- length(node$log_entries)
  if (end < start) {
    return(data.table::data.table(
      step        = integer(),
      reason      = character(),
      n_excluded  = integer(),
      n_remaining = integer()
    ))
  }
  data.table::rbindlist(lapply(node$log_entries[start:end], function(e) {
    data.table::data.table(
      step        = e$step,
      reason      = e$reason,
      n_excluded  = e$n_excluded,
      n_remaining = e$n_remaining
    )
  }))
}

# Build a `consort` object from a flow specification. Walks `flow`
# (named character vector of cohort names), lumps consecutive
# exclusions into bullet blocks, and supports identity-only side
# branches that merge into the main spine.
#' @keywords internal
.build_consort_obj <- function(flow, side_branches, nodes, text_width = 40) {
  fmt <- function(n) format(n, big.mark = ",")
  split_label <- function(label, n_val) {
    n_line <- sprintf("(n = %s)", fmt(n_val))
    idx <- regexpr(" \\(", label)
    if (idx[[1L]] > 0L) {
      name <- substr(label, 1L, idx[[1L]] - 1L)
      desc <- substr(label, idx[[1L]] + 1L, nchar(label))
      paste(c(name, desc, n_line), collapse = "\n")
    } else {
      paste(c(label, n_line), collapse = "\n")
    }
  }

  identity_merges <- list()
  for (i in seq_along(side_branches)) {
    sb_label <- side_branches[[i]]
    sb <- nodes[[sb_label]]
    if (is.null(sb)) next
    if (.own_log_n(sb) > 0L) {
      stop("draw_consort_panels supports identity side branches only; '",
        sb_label, "' has its own exclusions.", call. = FALSE)
    }
    attach_n <- as.character(sb$branched_at_n %||% length(sb$status))
    identity_merges[[attach_n]] <- list(
      name = names(side_branches)[i],
      n    = sum(sb$status == 0L)
    )
  }
  attach_keys <- names(identity_merges)

  g <- NULL
  add_main <- function(lbl) {
    if (is.null(g)) g <<- consort::add_box(txt = lbl)
    else            g <<- consort::add_box(prev_box = g, txt = lbl)
  }
  add_side <- function(lbl) {
    g <<- consort::add_side_box(prev_box = g, txt = lbl)
  }

  for (fi in seq_along(flow)) {
    br_name    <- flow[fi]
    br_label   <- names(flow)[fi]
    node       <- nodes[[br_name]]
    if (is.null(node)) {
      stop("draw_consort_panels: unknown cohort '", br_name,
        "' in flow.", call. = FALSE)
    }
    log_       <- .own_log(node)
    br_n_final <- sum(node$status == 0L)
    if (fi == 1L) {
      n_total <- if (is.na(node$parent)) length(node$status) else node$branched_at_n
      tot_merge <- identity_merges[[as.character(n_total)]]
      lbl <- split_label("Cohort participants", n_total)
      if (!is.null(tot_merge)) lbl <- paste0(lbl, "\n", tot_merge$name)
      add_main(lbl)
    }
    if (nrow(log_) > 0L) {
      chunk_boundaries <- c(
        which(as.character(log_$n_remaining) %in% attach_keys),
        nrow(log_)
      )
      chunk_boundaries <- sort(unique(chunk_boundaries))
      chunk_start <- 1L
      for (ck in seq_along(chunk_boundaries)) {
        chunk_end   <- chunk_boundaries[ck]
        chunk       <- log_[chunk_start:chunk_end]
        chunk_start <- chunk_end + 1L
        is_last     <- ck == length(chunk_boundaries)
        final_n     <- chunk$n_remaining[nrow(chunk)]
        merge_      <- identity_merges[[as.character(final_n)]]
        reasons <- vapply(seq_len(nrow(chunk)), function(j) {
          sprintf("- %s (n = %s)", chunk$reason[j], fmt(chunk$n_excluded[j]))
        }, character(1L))
        excl_lbl <- sprintf("Excluded (n = %s):\n%s",
          fmt(sum(chunk$n_excluded)),
          paste(reasons, collapse = "\n"))
        add_side(excl_lbl)
        if (is_last) {
          main_lbl <- split_label(br_label, br_n_final)
        } else if (!is.null(merge_)) {
          main_lbl <- split_label(merge_$name, final_n)
        } else {
          main_lbl <- sprintf("n = %s", fmt(final_n))
        }
        add_main(main_lbl)
      }
    } else if (fi > 1L) {
      add_main(split_label(br_label, br_n_final))
    }
  }
  g
}
