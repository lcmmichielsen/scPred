% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/scPredSeurat.R
\name{.getThreshold}
\alias{.getThreshold}
\title{Get thresholds from training models}
\usage{
.getThreshold(cellType, reference)
}
\arguments{
\item{cellType}{Cell type of interest}

\item{reference}{A \code{Seurat} object used as reference to perform predictions}
}
\description{
Calculates the threshold to classify a cell type.
}
