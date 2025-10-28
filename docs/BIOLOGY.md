# Biology and Bioinformatics Support

Omarchy now includes optional support for computational biology and bioinformatics workflows. This addition brings together common tools for genomics, proteomics, and data analysis in a way that follows Omarchy's conventions for development environments.

## Overview

If you work with biological data, you typically need a mix of command-line tools, Python libraries, and R packages. This module handles the installation of these components, using Omarchy's existing development environment infrastructure where appropriate.

The installation covers three main areas:

**System tools** include aligners like bowtie2 and bwa, format converters like samtools and bcftools, and utilities for genomic intervals such as bedtools. Quality control tools like fastqc and trimmomatic are included, along with multiple sequence alignment programs like mafft and muscle. Visualization tools like igv and pymol round out the system packages.

**Python packages** build on Omarchy's Python development environment. The scientific computing stack includes numpy, scipy, pandas, matplotlib, and seaborn. Biology-specific libraries like biopython, pysam, and scikit-bio handle common file formats and algorithms. For single-cell analysis, scanpy and anndata are included. Interactive work is supported through jupyter and jupyterlab, while napari provides image analysis capabilities.

**R packages** focus on Bioconductor and the tidyverse. Core packages like Biostrings and GenomicRanges handle sequence data, while DESeq2, edgeR, and limma support differential expression analysis. Single-cell analysis uses Seurat and related packages. The phyloseq package handles microbiome data, and the full tidyverse is included for data manipulation and visualization.

The biology tools can be installed at any time, either during initial Omarchy setup or later. Python and R are installed automatically using Omarchy's development environment system if they are not already present.

## Installation

### Complete Installation

To install all biology tools on an existing Omarchy system:

```bash
source ~/.local/share/omarchy/install/helpers/all.sh
run_logged ~/.local/share/omarchy/install/packaging/bio-all.sh
```

This will install system packages, Python libraries, and R packages in sequence. If Python or R are not already set up, they will be installed automatically using the standard Omarchy development environment tooling.

### Installing During Initial Setup

To include biology support when first installing Omarchy, edit `~/.local/share/omarchy/install/packaging/all.sh` and add this line at the end:

```bash
run_logged $OMARCHY_INSTALL/packaging/bio-all.sh
```

### Partial Installation

You can install individual components separately. For system packages only:

```bash
source ~/.local/share/omarchy/install/helpers/all.sh
run_logged ~/.local/share/omarchy/install/packaging/bio.sh
```

For Python packages only:

```bash
bash ~/.local/share/omarchy/install/packaging/python-bio.sh
```

For R packages only:

```bash
bash ~/.local/share/omarchy/install/packaging/r-bio.sh
```

## Customization

The package lists are simple text files that can be edited before installation. System packages are listed in `install/omarchy-bio.packages`, Python packages in `install/python-bio.txt`, and R packages in `install/r-bio.txt`. Comments are ignored, and blank lines are skipped.

## Additional Tools

Some biology tools are only available through the AUR. If you need tools like STAR, GATK, or FIJI, install them separately:

```bash
yay -S star-aligner gatk raxml iqtree chimerax fiji
```

## Alternative Approaches

While this module uses system Python and R managed by mise, you might prefer Conda for certain workflows. Conda provides better isolation and reproducibility for complex dependency chains. Bioconda has extensive coverage of bioinformatics tools:

```bash
curl -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh

conda config --add channels bioconda
conda config --add channels conda-forge
conda create -n analysis samtools bwa bowtie2 star salmon
```

The two approaches can coexist. System tools are available globally, while Conda environments provide project-specific isolation.
