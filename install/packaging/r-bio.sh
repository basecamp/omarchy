# Install R packages for biology at user level
# Uses R installed via Omarchy's dev environment

# Check if R is installed, if not, install via Omarchy
if ! command -v R &> /dev/null; then
  echo "R not found. Installing via Omarchy..."
  omarchy-install-dev-env r
fi

mkdir -p "$HOME/R/library"

R --quiet --no-save << 'RSCRIPT'
lib_path <- Sys.getenv("R_LIBS_USER", "~/R/library")
dir.create(lib_path, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib_path, .libPaths()))

install_safe <- function(pkg, bioc = FALSE) {
  tryCatch({
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
      if (bioc) {
        if (!requireNamespace("BiocManager", quietly = TRUE)) {
          install.packages("BiocManager", repos = "https://cloud.r-project.org", quiet = TRUE)
        }
        BiocManager::install(pkg, update = FALSE, ask = FALSE)
      } else {
        install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
      }
    }
  }, error = function(e) {
    cat(paste("Warning:", pkg, "failed\n"))
  })
}

bioc_packages <- c("Biostrings", "GenomicRanges", "GenomicFeatures", "rtracklayer",
                   "IRanges", "BSgenome", "SummarizedExperiment", "VariantAnnotation",
                   "DESeq2", "edgeR", "limma", "tximport", "sva", "fgsea", "fishpond",
                   "SingleCellExperiment", "scater", "phyloseq", "ComplexHeatmap",
                   "clusterProfiler", "ChIPseeker")

packages <- c("BiocManager", "tidyverse", "ggplot2", "dplyr", "tidyr", "readr",
              "stringr", "Seurat", "monocle3", "vegan", "devtools", "knitr", "rmarkdown", "data.table")

for (pkg in packages) {
  if (pkg %in% bioc_packages) {
    install_safe(pkg, bioc = TRUE)
  } else {
    install_safe(pkg, bioc = FALSE)
  }
}

for (pkg in bioc_packages) {
  if (!(pkg %in% packages)) {
    install_safe(pkg, bioc = TRUE)
  }
}
RSCRIPT
