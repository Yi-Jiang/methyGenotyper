# MethylGenotyper: Call genotypes from Illumina methylation array data

#### Yi Jiang, Minghan Qu, Chaolong Wang

The `MethylGenotyper` package provides functions to infer genotypes (produce a VCF file) for specific probes and on Illumina methylation array (EPIC or 450K). Three types of probes capable of calling genotypes were used, including SNP probe, Type I probe with color-channel-switching (CCS) SNP at the extension base, and Type II probe with SNP at the extension base. We defined RAI as the Ratio of Alternative allele Intensity to total intensity and calculated RAI for each probe and sample.

-   **SNP probe:** There are 59 SNP probes (started with "rs") on EPIC array and 65 SNP probes on 450K array. Probes on sex chromosomes (six in EPIC and eight on 450K) were removed. We aligned each probe sequence to reference genome and calculated RAI, which is defined as the proportion of probe signals supporting alternative allele.
-   **Type I probe:** We focus on Type I probes with CCS SNPs (A,T \<-\> C,G mutation) at the extension bases. The signals for probes with CCS SNPs are called out-of-band signals. The RAI is defined as the proportion of out-of-band signals over total signals.
-   **Type II probe:** We focus on Type II probes with SNPs at the extension bases (CpG target sites). The alternative allele of SNP can be either A/T (CCS SNP) or G (SNP not switching color channel). Please refer to the manuscript for details in calculating RAI.

The RAI values are usually distributed with three peaks, representing the three genotypes (reference homozygous, heterozygous, and alternative homozygous). To call genotypes from the RAI values, we fit a mixture of three beta distributions for the three genotypes and a uniform distribution for outliers based on the Expectation--maximization (EM) algorithm. Probe-specific weights derived from allele frequencies (AFs) were used in the EM algorithm. A VCF file containing dosage genotype ($\hat{D}_{ij}$), AF ($\hat{q}_i$), and $\hat{R}_i^2$ will be produced.

For samples of mixed population, we provided an option to infer population structure and calculate individual-specific AFs, which can improve the accuracy of estimating kinship coefficients.

We also provided functions to estimate kinship coefficients and sample contamination.

## Installation:

``` r
library(devtools)
install_github("Yi-Jiang/MethylGenotyper", auth_token="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")
```

## Recommended workflow

### Load the MethylGenotyper package

This package has the following dependencies: `minfi`, `tidyverse`, `foreach`, `doParallel`, `HardyWeinberg`, `multimode`, `rlist`, `stats4`, `ggplot2`, `ggpubr`.

```{r MethylGenotyper, eval=TRUE, message=FALSE, warning=FALSE}
library(MethylGenotyper)
```

### Read IDAT files and perform noob and dye-bias correction

Read IDAT file list. Here is an example of processing three IDAT files from `minfiDataEPIC`. Note that this is just an exemplification of how this tool works. We strongly recommend to use a larger sample size to test the code, such as [GSE112179](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE112179). Your may process your own data by specifying your target file list. Required collumns: Sample_Name, Basename.

```{r rgSet, eval=TRUE, warning=FALSE, message=TRUE}
target <- get_target(platform="EPIC")
head(target)
#>   Sample_Name          Basename
#> 1     sample1  /path/to/sample1
#> 2     sample2  /path/to/sample2
#> 3     sample3  /path/to/sample3
```

With the following code, the IDAT files listed in `target` will be read one-by-one. For each sample, a noob background correction and dye-bias correction will be conducted. You can specify the number of CPUs to enable parallel processing. After that, a list of four elements will be returned, including corrected signals of probe A and probe B for the two color channels.

```{r correct_noob_dye, eval=FALSE, warning=FALSE, message=FALSE}
rgData <- correct_noob_dye(target, platform="EPIC", cpu=3)
```

### Call genotypes

The genotype-calling procedure can be done for SNP probes, Type I probes, and Type II probes, separately. You should specify the correct population (One of EAS, AMR, AFR, EUR, SAS, and ALL) for your samples to get accurate genotype calls. If you have samples of mixed population, please specify the population with the largest sample size.

You can plot the distribution of the RAI values and produce a VCF file of the inferred genotypes by specifying `plotBeta=TRUE` and `vcf=TRUE`.

You can also specify cutoffs of $R^2$, MAF, HWE, and missing rate to filter variants. Note that for VCF output, variants beyond the cutoffs will be marked in the `FILTER` column.

We noted that in the example data, most of variants have $R^2$=0. This is because we only used three samples here. We strongly recommend to use a larger sample size to test the code, such as [GSE112179](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE112179).

```{r callGeno, eval=FALSE, warning=FALSE, message=FALSE}
# Call genotypes for SNP probes, Type I probes, and Type II probes
genotype_snp <- callGeno_snp(rgData, input="raw", vcf=TRUE, pop="EAS", platform="EPIC")
genotype_typeI <- callGeno_typeI(rgData, vcf=TRUE, pop="EAS", platform="EPIC")
genotype_typeII <- callGeno_typeII(rgData, input="raw", vcf=TRUE, pop="EAS", platform="EPIC")

# Combine genotypes inferred from the three probe types
dosage <- rbind(genotype_snp$dosage, genotype_typeI$dosage, genotype_typeII$dosage)
```

As an alternative option, you can input a matrix of beta values or M values, with each row indicates a probe and each column indicates a sample. This option only works for SNP probes and Type II probes. Here are the examples of calling genotypes from beta values. For input of M values, please specify `input="mval"`. Remember to conduct background correction and dye-bias correction before running the following code. Also be noted that other correction should NOT be conducted, like BMIQ, as it flattens the peaks through a scale transformation.

```{r callGeno2, eval=FALSE, warning=FALSE, message=FALSE}
# Call genotypes for SNP probes and Type II probes
genotype_snp <- callGeno_snp(beta_matrix, input="beta", vcf=TRUE, pop="EAS", platform="EPIC")
genotype_typeII <- callGeno_typeII(beta_matrix, input="beta", vcf=TRUE, pop="EAS", platform="EPIC")

# Combine genotypes inferred from the three probe types
dosage <- rbind(genotype_snp$dosage, genotype_typeII$dosage)
```

### Infer population structure and individual-specific AFs for mixed population

**Project the study samples to reference ancestral space:** Principal Components Analyses (PCA) are conducted in 1KGP individuals (the ancestral space) and a combination of 1KGP individuals and each study sample. Projection Procrustes analyses are then conducted to project each study sample to reference ancestral space. This step was originally implemented by the TRACE software and we have adapted it in R ([Wang et al. Nat Genet 2014](https://www.nature.com/articles/ng.2924), [Wang et al. Am J Hum Genet 2015](http://dx.doi.org/10.1016/j.ajhg.2015.04.018)).

```{r projection, eval=FALSE, warning=FALSE, message=FALSE}
# PCA and Procrustes analysis, based on genotypes of all probes passing QC
pc <- projection(dosage, plotPCA=TRUE, cpu=3, platform="EPIC")
```

**Estimate individual-specific AFs:** For each SNP, we model genotypes of the reference individuals as a linear function of top four PCs ($v_\cdot$): $G\sim\beta_0+\beta_1v_1+\beta_2v_2+\beta_3v_3+\beta_4v_4$. Then, the individual AF ($q$) for each SNP and each sample can be obtained by: $\hat{q}=\frac{1}{2}(\hat{\beta_0}+\hat{\beta_1}\hat{v_1}+\hat{\beta_2}\hat{v_2}+\hat{\beta_3}\hat{v_3}+\hat{\beta_4}\hat{v_4})$, where $\hat{v}_\cdot$ are top four PCs in study samples. ([Dou et al. PLoS Genet 2017](https://journals.plos.org/plosgenetics/article?id=10.1371/journal.pgen.1007021))

```{r indAF, eval=FALSE, warning=FALSE, message=FALSE}
data(cpg2snp)
snpvec <- cpg2snp[c(rownames(genotype_snp$genotypes$RAI), rownames(genotype_typeI$genotypes$RAI), rownames(genotype_typeII$genotypes$RAI))]
indAF <- get_indAF(snpvec, pc$refPC, pc$studyPC)
```

<!-- **Recalibrate genotype probabilities based on individual-specific AFs: ** This step is based on the Bayesian approach, which can be implemented by using the `get_GP_bayesian` function. -->

<!-- ```{r recal_geno, eval=FALSE, warning=FALSE, message=FALSE} -->

<!-- # Recalibrate genotypes for SNP probes, Type I probes, and Type II probes -->

<!-- genotype_snp_recal <- recal_Geno(genotype_snp, type="snp_probe", indAF=indAF, platform="EPIC") -->

<!-- genotype_typeI_recal <- recal_Geno(genotype_typeI, type="typeI_probe", indAF=indAF, platform="EPIC") -->

<!-- genotype_typeII_recal <- recal_Geno(genotype_typeII, type="typeII_probe", indAF=indAF, platform="EPIC") -->

<!-- # Combine genotypes inferred from the three probe types -->

<!-- dosage_recal <- rbind(genotype_snp_recal$dosage, genotype_typeI_recal$dosage, genotype_typeII_recal$dosage) -->

<!-- ``` -->

### Estimate sample relationships and sample contamination

With the inferred genotypes, you can estimate sample relationships and sample contamination using the `getKinship` function. The output of this function is a list of two elements: 1) a data frame containing kinship coefficient ($\phi$) and sample relationships between each two samples; 2) a vector of inbreeding coefficients, which can be used to infer sample contamination.

Kinship coefficient is calculated according to the SEEKIN software ([Dou et al. PLoS Genet 2017](https://journals.plos.org/plosgenetics/article?id=10.1371/journal.pgen.1007021)): $$2\phi_{ij} = \frac{\sum_m(G_{im}-2p_m)(G_{jm}-2p_m)}{2p_m(1-p_m)(R^2)^2}$$ where $\phi_{ij}$ denotes the kinship coefficient between $i$-th and $j$-th sample. $G_{im}$ and $G_{jm}$ denotes genotypes of $m$-th SNP for $i$-th and $j$-th sample. $p_m$ denotes allele frequency of $m$-th SNP. $R^2$ is calculated as $R^2 = \frac{Var(D)}{2q(1-q)}$, where $D$ is the dosage genotype. We classified sample pairs as k-degree related if $2^{-k-1.5} < \phi_{ij} < 2^{-k-0.5}$ ([Manichaikul et al. Bioinformatics 2010](https://academic.oup.com/bioinformatics/article/26/22/2867/228512)). A zero-degree related pair means monozygotic twins (MZ) or duplicates. Sample pairs more distant than 3rd degree are treated as unrelated.

Inbreeding coefficients are calculated as: $F=2\phi_{ii}-1$, where $\phi_{ii}$ is the self-kinship coefficient for sample $i$.

```{r getKinship, eval=FALSE, warning=FALSE, message=FALSE}
res <- getKinship(dosage)
kinship <- res$kinship # kinship coefficients
inbreed <- res$inbreed # inbreeding coefficients
```
