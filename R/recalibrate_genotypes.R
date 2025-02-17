
#' PCA and Procrustes analysis
#'
#' @param studyGeno A matrix of genotypes of study samples. Provide probes as rows and samples as columns. Include all SNP probes, type I probes, and type II probes if available.
#' @param plotPCA To plot the projection of study samples in reference ancestry space.
#' @param cpu Number of CPU.
#' @param platform EPIC or 450K.
#' @return A list containing
#' \item{refPC}{Top PCs in the reference}
#' \item{studyPC}{Top PCs in study samples}
#' @export
projection <- function(studyGeno, plotPCA=TRUE, cpu=1, platform="EPIC"){
  print(paste(Sys.time(), "Running projection."))
  ## Filter SNPs for PCA: MAF>0.1 and R2>0.9
  AF <- rowMeans(studyGeno, na.rm=TRUE) / 2
  R2 <- apply(studyGeno, 1, function(x) var(x, na.rm=TRUE)) / (2 * AF * (1 - AF))
  studyGeno <- studyGeno[AF>0.1 & AF<0.9 & R2>0.9,]
  if(platform=="EPIC"){
    data(cpg2snp)
  }else{
    data(cpg2snp_450K); cpg2snp <- cpg2snp_450K
  }
  rownames(studyGeno) <- cpg2snp[rownames(studyGeno)]
  
  ## PCA and Procrustes analysis
  data(refGeno_1KGP3)
  pc <- TRACE(refGeno_1KGP3, studyGeno, cpu=cpu)
  
  ## Plot PCA
  if(plotPCA){
    plot_PCA(pc$refPC, pc$studyPC)
  }
  
  pc
}

#' Calculate individual-specific AFs
#'
#' @param snpvec A vector of SNP IDs.
#' @param refPC Top PCs in the reference.
#' @param studyPC Top PCs in study samples.
#' @return A matrix of individual-specific AFs.
#' @export
get_indAF <- function(snpvec, refPC, studyPC){
  print(paste(Sys.time(), "Modeling genotypes and PCs on reference samples."))
  betas <- list()
  for(snp in snpvec){
    betas[[snp]] <- coefficients(lm(refGeno_1KGP3[snp,] ~ refPC))
  }
  betas <- do.call(rbind, betas)
  colnames(betas) <- c("Intercept", paste0("RefPC", 1:4))
  
  print(paste(Sys.time(), "Calculating individual-specific AFs."))
  studyPC <- cbind(Intercept=1, studyPC)
  indAF <- betas %*% t(studyPC) / 2
  indAF[indAF<0.001] <- 0.001 # constrain AFs to avoid out of boundary values
  indAF[indAF>0.999] <- 0.999
  indAF
}

#' Recalibrate genotypes for samples of mixed population
#'
#' @param genotypes A list returned by either `callGeno_snp`, `callGeno_typeI`, or `callGeno_typeII` function.
#' @param type One of snp_probe, typeI_probe, and typeII_probe.
#' @param indAF A matrix of individual-specific AFs. Provide SNPs as rows and samples as columns.
#' @param platform EPIC or 450K.
#' @param GP_cutoff When calculating missing rate, genotypes with the highest genotype probability < GP_cutoff will be treated as missing.
#' @param outlier_cutoff "max" or a number ranging from 0 to 1. If outlier_cutoff="max", genotypes with outlier probability larger than all of the three genotype probabilities will be set as missing. If outlier_cutoff is a number, genotypes with outlier probability > outlier_cutoff will be set as missing.
#' @param missing_cutoff Missing rate cutoff to filter variants. Note that for VCF output, variants with missing rate above the cutoff will be marked in the `FILTER` column. For the returned dosage matrix, variants with missing rate above the cutoff will be removed.
#' @param R2_cutoff_up,R2_cutoff_down R-square cutoffs to filter variants (Variants with R-square > R2_cutoff_up or < R2_cutoff_down should be removed). Note that for VCF output, variants with R-square outside this range will be marked in the `FILTER` column. For the returned dosage matrix, variants with R-square outside this range will be removed.
#' @param MAF_cutoff A MAF cutoff to filter variants. Note that for VCF output, variants with MAF below the cutoff will be marked in the `FILTER` column. For the returned dosage matrix, variants with MAF below the cutoff will be removed.
#' @param HWE_cutoff HWE p value cutoff to filter variants. Note that for VCF output, variants with HWE p value below the cutoff will be marked in the `FILTER` column. For the returned dosage matrix, variants with HWE p value below the cutoff will be removed.
#' @return A list of recalibrated genotypes containing
#' \item{dosage}{A matrix of genotype calls. Variants with R2s, HWE p values, MAFs, or missing rates beyond the cutoffs are removed.}
#' \item{genotypes}{A list containing RAI, shapes of the mixed beta distributions, prior probabilities that the RAI values belong to one of the three genotypes, proportion of RAI values being outlier (U), and genotype probability (GP)}
#' \item{indAF}{A matrix of individual-specific AFs.}
#' @export
recal_Geno <- function(genotypes, type, indAF, platform="EPIC", GP_cutoff=0.9, outlier_cutoff="max", missing_cutoff=0.1, 
                       R2_cutoff_up=1.1, R2_cutoff_down=0.75, MAF_cutoff=0.01, HWE_cutoff=1e-6){
  if(platform=="EPIC"){
    data(snp2cpg)
  }else{
    data(snp2cpg_450K); snp2cpg <- snp2cpg_450K
  }
  rownames(indAF) <- snp2cpg[rownames(indAF)]
  indAF <- indAF[rownames(genotypes$genotypes$GP$pAA), colnames(genotypes$genotypes$GP$pAA)]
  
  ## Recalibrate posterior genotype probabilities
  print(paste(Sys.time(), "Recalibrating posterior genotype probabilities."))
  GP <- get_GP_bayesian(genotypes$genotypes$GP$pAA, genotypes$genotypes$GP$pAB, genotypes$genotypes$GP$pBB, indAF)
  genotypes_recal <- list(genotypes = genotypes$genotypes, indAF=indAF)
  genotypes_recal$genotypes$GP <- GP
  genotypes_recal$genotypes$RAI <- genotypes_recal$genotypes$RAI[rownames(GP$pAA), colnames(GP$pAA)]
  genotypes_recal$dosage <- format_genotypes(genotypes_recal$genotypes, vcf=T, GP_cutoff=GP_cutoff,
                                             vcfName=paste0("genotypes.recal.", type, ".vcf"),
                                             R2_cutoff_up=R2_cutoff_up, R2_cutoff_down=R2_cutoff_down, 
                                             MAF_cutoff=MAF_cutoff, HWE_cutoff=HWE_cutoff, 
                                             outlier_cutoff=outlier_cutoff, missing_cutoff=missing_cutoff,
                                             type=type, plotAF=FALSE, platform=platform)
  genotypes_recal
}

#' To plot the projection of study samples in reference ancestry space
#'
#' @param refPC Top PCs in the reference
#' @param studyPC Top PCs in study samples
#' @export
plot_PCA <- function(refPC, studyPC){
  data(sam2pop)
  refPC <- data.frame(refPC, popID=sam2pop[rownames(refPC)])
  studyPC <- data.frame(studyPC, popID="Study")
  p1 <- ggplot(refPC) +
    geom_point(aes(x=PC1, y=PC2, color=popID), size=3, alpha=0.6) +
    scale_color_brewer(palette="Set2")+
    geom_point(aes(x=PC1, y=PC2, shape=popID), size=3, alpha=0.6, data=studyPC) +
    scale_shape_manual(values=c("Study"=1))+
    theme_bw()
  p2 <- ggplot(refPC) +
    geom_point(aes(x=PC3, y=PC4, color=popID), size=3, alpha=0.6) +
    scale_color_brewer(palette="Set2")+
    geom_point(aes(x=PC3, y=PC4, shape=popID), size=3, alpha=0.6, data=studyPC) +
    scale_shape_manual(values=c("Study"=1))+
    theme_bw()
  p <- ggarrange(p1, p2, nrow=1, ncol=2)
  ggsave(filename="trace.pca.pdf", plot=p, width=7, height=3, units="in", scale=2)
}
