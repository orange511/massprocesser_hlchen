# ##-------------------------------------------------
# #output EIC of specific peaks
# setwd(masstools::get_project_wd())
# setwd("test_data/mzxml/")
# load("Result/intermediate_data/xdata3")
# targeted_table <- readxl::read_xlsx("is.xlsx")
# targeted_table =
#   targeted_table %>%
#   dplyr::rename(variable_id = name)
#
#
#
# extract_eic(
#   targeted_table = targeted_table,
#   object = xdata3,
#   mz_tolerance = 10,
#   rt_tolerance = 30,
#   threads = 5,
#   polarity = "positive",
#   add_point = TRUE,
#   path = ".",
#   group_for_figure = c("Subject", "QC")
# )


#' @title extract_eic
#' @description Extract EICs of some features from some samples.
#' @author Xiaotao Shen
#' \email{shenxt1990@@outlook.com}
#' @param targeted_table A data.frame contains the variable_id,
#' mz and rt of features to extract.
#' @param object object from xcms. If you use massprocesser,
#' this should be the xdata3.
#' @param polarity positive or negative.
#' @param mz_tolerance default is 15 ppm.
#' @param rt_tolerance default is 30 ppm.
#' @param threads Number of threads.
#' @param add_point aad points in the EIC or not.
#' @param path Work directory.
#' @param group_for_figure what samples groups are used to extract EICs
#' @param feature_type png of pdf
#' @param width figure width
#' @param height height width
#' @param device Device to use.
#' Can either be a device function (e.g. png),
#' or one of "eps", "ps", "tex" (pictex), "pdf", "
#' jpeg", "tiff", "png", "bmp", "svg" or "wmf" (windows only).
#' @return EICs.
#' @export

extract_eic <-
  function(targeted_table,
           object,
           polarity = c("positive", "negative"),
           mz_tolerance = 15,
           rt_tolerance = 30,
           threads = 5,
           add_point = FALSE,
           path = ".",
           group_for_figure = "QC",
           feature_type = c("pdf", "png"),
           width = 10,
           height = 6,
           device = NULL) {
    if (!group_for_figure %in% object@phenoData@data$sample_group) {
      stop(
        group_for_figure,
        " is not in the sample_group. Try to set group_for_figure as one of these: ",
        paste(unique(object@phenoData@data$sample_group), collapse = ", ")
      )
      
    }
    
    if (missing(object)) {
      stop("No object provided, which should be from the xcms.")
    }
    
    dir.create(path, showWarnings = FALSE)
    
    feature_type <- match.arg(feature_type)
    polarity <- match.arg(polarity)
    
    peak_name <- xcms::groupnames(object)
    peak_name <-
      paste(peak_name, ifelse(polarity == "positive", "POS", "NEG"), sep = "_")
    definition <- xcms::featureDefinitions(object = object)
    definition <- definition[, -ncol(definition)]
    definition <-
      definition[names(definition) != "peakidx"]
    definition <-
      definition@listData %>%
      dplyr::bind_rows()
    peak_table <- data.frame(
      variable_id = peak_name,
      definition %>% dplyr::select(mz = mzmed, rt = rtmed),
      stringsAsFactors = FALSE
    )
    rownames(peak_table) <- NULL
    
    if (missing(targeted_table)) {
      message(
        crayon::yellow(
          "No targeted_table is provided,
        all the features' EICs will be outputted."
        )
      )
      targeted_table <- peak_table
      mz_tolerance <- 0.0001
      rt_tolerance <- 0.0001
    }
    
    check_targeted_table(targeted_table = targeted_table)
    
    match_result <-
      masstools::mz_rt_match(
        data1 = as.matrix(targeted_table[, c(2, 3)]),
        data2 = as.matrix(definition[, c("mzmed", "rtmed")]),
        mz.tol = mz_tolerance,
        rt.tol = rt_tolerance,
        rt.error.type = "abs"
      )
    
    if (is.null(match_result) | nrow(match_result) == 0) {
      stop("No features are in the object.")
    }
    
    message(crayon::green("Outputting peak EICs..."))
    feature_EIC_path <- file.path(path, "feature_EIC")
    dir.create(feature_EIC_path, showWarnings = FALSE)
    
    index2 <- sort(unique(match_result[, 2]))
    metabolite_name <-
      targeted_table$variable_id[match_result[match(index2, match_result[, 2]), 1]]
    
    if (masstools::get_os() == "windows") {
      bpparam <-
        BiocParallel::SnowParam(workers = threads,
                                progressbar = TRUE)
    } else{
      bpparam <- BiocParallel::MulticoreParam(workers = threads,
                                              progressbar = TRUE)
    }
    
    feature_eic <-
      tryCatch(
        xcms::featureChromatograms(
          object,
          features = index2,
          expandRt = 0,
          BPPARAM = bpparam
        ),
        error = function(x) {
          NULL
        }
      )
    
    if (is.null(feature_eic)) {
      if (masstools::get_os() != "windows") {
        bpparam <-
          BiocParallel::SnowParam(workers = threads,
                                  progressbar = TRUE)
      } else{
        bpparam <- BiocParallel::MulticoreParam(workers = threads,
                                                progressbar = TRUE)
      }
      feature_eic <-
        tryCatch(
          xcms::featureChromatograms(
            object,
            features = index2,
            expandRt = 0,
            BPPARAM = bpparam
          ),
          error = function(x) {
            NULL
          }
        )
    }
    
    feature_eic_data <-
      feature_eic@.Data %>%
      apply(1, function(y) {
        y <- lapply(y, function(x) {
          if (is(x, class2 = "XChromatogram")) {
            if (nrow(x@chromPeaks) == 0) {
              data.frame(
                rt.med = NA,
                rt.min = NA,
                rt.max = NA,
                rt = NA,
                min.intensity = 0,
                max.intensity = NA,
                intensity = NA,
                stringsAsFactors = FALSE
              )
            } else{
              if (nrow(x@chromPeaks) > 1) {
                x@chromPeaks <-
                  as.data.frame(x@chromPeaks) %>%
                  dplyr::filter(maxo == max(maxo)) %>%
                  as.matrix()
              }
              data.frame(
                rt.med = x@chromPeaks[, 4],
                rt.min = x@chromPeaks[, 5],
                rt.max = x@chromPeaks[, 6],
                rt = x@rtime,
                min.intensity = 0,
                max.intensity = x@chromPeaks[, "maxo"],
                intensity = x@intensity,
                stringsAsFactors = FALSE
              )
            }
          } else{
            
          }
        })
        y <-
          mapply(
            function(y, sample.group, sample.name) {
              data.frame(
                y,
                sample_group = sample.group,
                sample_name = sample.name,
                stringsAsFactors = FALSE
              ) %>%
                list()
            },
            y = y,
            sample.group = feature_eic@phenoData@data$sample_group,
            sample.name = feature_eic@phenoData@data$sample_name
          )
        
        y <- do.call(rbind, y)
        y
      })
    
    feature_eic_data <-
      feature_eic_data %>%
      lapply(function(x) {
        x <-
          x %>%
          dplyr::filter(sample_group %in% group_for_figure)
        
        if (length(unique(x$sample_name)) > 18) {
          idx <-
            which(x$sample_name %in% sort(sample(unique(
              x$sample_name
            ), 18))) %>%
            sort()
          x <- x[idx, , drop = FALSE]
        }
        x
      })
    
    purrr::walk(
      .x = seq_along(index2),
      .f = function(i) {
        message(i)
        peak.name <- peak_name[index2][i]
        plot.name <- paste("", peak.name, sep = "")
        metabolite.name <- metabolite_name[i]
        temp_feature_eic_data <-
          feature_eic_data[[i]]
        
        rt_range <-
          c(
            min(temp_feature_eic_data$rt, na.rm = TRUE),
            max(temp_feature_eic_data$rt, na.rm = TRUE)
          )
        
        if (nrow(temp_feature_eic_data) != 0) {
          plot <-
            ggplot2::ggplot(temp_feature_eic_data,
                            ggplot2::aes(rt, intensity, group = sample_name)) +
            ggplot2::geom_line(ggplot2::aes(color = sample_name)) +
            # ggplot2::geom_point(ggplot2::aes(color = sample_name)) +
            # ggsci::scale_color_lancet() +
            ggplot2::labs(
              x = "Retention time (second)",
              title = paste(
                "RT range:",
                round(rt_range[1], 3),
                round(rt_range[2], 3),
                metabolite.name,
                sep = "_"
              ),
              y = "Intensity"
            ) +
            ggplot2::theme_bw()
          
          if (add_point) {
            plot <-
              plot +
              ggplot2::geom_point(ggplot2::aes(color = sample_name))
          }
          
          ggplot2::ggsave(
            plot,
            file = file.path(
              feature_EIC_path,
              paste(plot.name,
                    feature_type,
                    sep = ".")
            ),
            width = width,
            height = height,
            device
          )
        } else{
          message("No data")
        }
      }
    )
    
    message(crayon::red("OK"))
    
  }
