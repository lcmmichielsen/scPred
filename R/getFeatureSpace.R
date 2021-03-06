#' @title Get informative principal components
#' @description Given a prediction variable, finds a feature set of class-informative principal components. 
#' A Wilcoxon rank sum test is used to determine a difference between the score distributions of cell classes from the prediction variable.
#' @param object An \code{scPred} or \code{seurat} object
#' @param pVar Prediction variable corresponding to a column in \code{metadata} slot
#' @param varLim Threshold to filter principal components based on variance explained.
#' @param correction Multiple testing correction method. Default: false discovery rate. See \code{p.adjust} function 
#' @param sig Significance level to determine principal components explaining class identity
#' @return An \code{scPred} object with two additional filled slots:
#' \itemize{
#' \item \code{features}: A data frame with significant principal components the following information:
#' \itemize{
#' \item PC: Principal component
#' \item pValue: p-value obtained from Mann-Whitney test
#' \item pValueAdj: Adjusted p-value according to \code{correction} parameter
#' \item expVar: Explained variance by the principal component
#' \item cumExpVar: All principal components are ranked accoriding to their frequency of ocurrence and their variance explained. 
#' This column contains the cumulative variance explained across the ranked principal components
#' }
#' \item \code{pVar}: Column name from metadata to use as the variable to predict using
#' the informative principal components. Informative principal components are selected based on this variable.
#' }
#' @keywords informative, significant, features
#' @importFrom methods is
#' @importFrom tidyr gather
#' @importFrom magrittr "%>%"
#' @importFrom dplyr mutate arrange filter
#' @importFrom pbapply pblapply
#' @export
#' @author
#' José Alquicira Hernández
#' 
#' @examples 
#' 
#' # Assign cell information to scPred object
#' # Cell information must be a data.frame with rownames as cell ids matching the eigendecomposed 
#' gene expression matrix rownames.
#' 
#' metadata(object) <- cellInfo
#' 
#' # Get feature space for column "cellType" in metadata slot
#' 
#' object <- getFeatureSpace(object = object, pVar = "cellType")
#' 




getFeatureSpace <- function(object, pVar, varLim = 0.01, correction = "fdr", sig = 0.05){
  
  
  # Validations -------------------------------------------------------------
  
  if(!is(object, "scPred") & !is(object, "Seurat")){
    stop("Invalid class for object: must be 'scPred' or 'Seurat'")
  }
  
  if(!any(correction %in% stats::p.adjust.methods)){
    stop("Invalid multiple testing correction method. See ?p.adjust function")
  }
  
  if(is(object, "scPred")){
    classes <- metadata(object)[[pVar]]
  }else{
    classes <- object[[pVar, drop = TRUE]]
  }
  
  if(is.null(classes)){
    stop("Prediction variable is not stored in metadata slot")
  }
  
  if(!is.factor(classes)){
    message("Transforming prediction variable to factor object...")
    classes <- as.factor(classes)
  }

  # Filter principal components by variance ---------------------------------
  
  if(is(object, "scPred")){ # scPred object
    
    # Get PCA
    i <- object@expVar > varLim
    pca <- getPCA(object)[,i]
    
    # Get variance explained
    expVar <- object@expVar
    
  }else{ # seurat object
    
    # Check if a PCA has been computed
    if(!("pca" %in% names(object@reductions))){
      stop("No PCA has been computet yet. See RunPCA() function")
    }
    
    # Check if available was normalized
    
    assay <- DefaultAssay(object)
    cellEmbeddings <- Embeddings(object)
    
    
    # Subset PCA
    expVar <- Stdev(object)**2/sum(Stdev(object)**2)
    names(expVar) <- colnames(Embeddings(object))
    i <-  expVar > varLim
    
    # Create scPred object
    pca <- Embeddings(object)[,i]
    
    
  }
  
  
  
  
  uniqueClasses <- unique(classes)
  isValidName <- uniqueClasses == make.names(uniqueClasses)
  
  if(!all(isValidName)){
    
    invalidClasses <- paste0(uniqueClasses[!isValidName], collapse = "\n")
    message("Not all the classes are valid R variable names\n")
    message("The following classes are renamed: \n", invalidClasses)
    classes <- make.names(classes)
    classes <- factor(classes, levels = unique(classes))
    newPvar <- paste0(pVar, ".valid")
    if(is(object, "scPred")){
      object@metadata[[newPvar]] <- classes
    }else{
      object@meta.data[[newPvar]] <- classes
    }
    message("\nSee new classes in '", pVar, ".valid' column in metadata:")
    message(paste0(levels(classes)[!isValidName], collapse = "\n"), "\n")
    pVar <- newPvar
  }
  
  
  
  
  # Select informative principal components
  # If only 2 classes are present in prediction variable, train one model for the positive class
  # The positive class will be the first level of the factor variable
  
  if(length(levels(classes)) == 2){
    
    message("First factor level in '", pVar, "' metadata column considered as positive class")
    res <- .getFeatures(levels(classes)[1], expVar, classes, pca, correction, sig)
    res <- list(res)
    names(res) <- levels(classes)[1]
    
  }else{
    
    res <- pblapply(levels(classes), .getFeatures, expVar, classes, pca, correction, sig)
    names(res) <- levels(classes)
    
  }
  

  nFeatures <- unlist(lapply(res, nrow))
  
  noFeatures <- nFeatures == 0
  
  if(any(noFeatures)){
    
    warning("\nWarning: No features were found for classes:\n",
            paste0(names(res)[noFeatures], collapse = "\n"), "\n")
    res[[names(res)[noFeatures]]] <- NULL
 
  }
  
  message("\nDONE!")
  
  
  # Assign feature space to `features` slot
  if(inherits(object, "Seurat")){
    
    # Create scPred object
    scPredObject <- list(expVar = expVar,
                  features = res,
                  pVar = pVar,
                  pseudo = FALSE)
    
    object@misc <- list(scPred = scPredObject)
    
  }else{
  
  
  object@features <- res
  object@pVar <- pVar
  }
  
  object
  
}

.getFeatures <- function(positiveClass, expVar, classes, pca, correction, sig){
  
  # Set non-positive classes to "other"
  i <- classes != positiveClass
  newClasses <- as.character(classes)
  newClasses[i] <- "other"
  newClasses <- factor(newClasses, levels = c(positiveClass, "other"))
  
  # Get indices for positive and negative class cells
  positiveCells <- newClasses == positiveClass
  negativeCells <- newClasses == "other"
  
  # Get informative features
  apply(pca, 2, function(pc) wilcox.test(pc[positiveCells], pc[negativeCells])) %>%
    lapply('[[', "p.value") %>% # Extract p-values
    as.data.frame() %>% 
    gather(key = "PC", value = "pValue") %>%
    mutate(pValueAdj = p.adjust(pValue, method = correction, n = nrow(.))) %>% # Perform multiple test correction
    arrange(pValueAdj) %>% 
    filter(pValueAdj < sig) %>% # Filter significant features by p-value
    mutate(expVar = expVar[match(PC, names(expVar))]) %>% # Get explained variance for each feature
    mutate(PC = factor(PC, levels = PC), cumExpVar = cumsum(expVar)) -> sigPCs
  
  sigPCs
}

