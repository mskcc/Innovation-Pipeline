#! /usr/bin/env Rscript

##################################################
# Innovation Laboratory
# Center For Molecular Oncology
# Memorial Sloan Kettering Cancer Research Center
# Maintainer: Ian Johnson (johnsoni@mskcc.org)
##################################################

library(grid)
library(scales)
library(gridBase)
library(gridExtra)
library(lattice)
library(ggplot2)
library('getopt');
library(reshape2)
suppressMessages(library(dplyr))
suppressMessages(library(ggrepel))


# Set terminal display width, error tracebacks
options(width=1000)
options(show.error.locations = TRUE)
options(error = quote({dump.frames(to.file=TRUE); q()}))
options(error=function()traceback(2))

# Util for putting commas in scale labels
format_comma <- function(x, ...) {
  format(x, ..., big.mark = ',', scientific = FALSE, trim = TRUE)
}

# Define our global plots theme
MY_THEME = theme(text = element_text(size=14),
  axis.text.x = element_text(angle = 45, hjust = 1, face='bold'),
  plot.margin = unit(c(.1, .1, .1, 1), 'in'))

# Some title file columns will not be printed
DROP_COLS = c('Pool_input', 'Barcode_index', 'PatientName', 'MAccession', 'Extracted_DNA_Yield')
# Levels and sort order for collapsing methods
LEVEL_C = c('TotalCoverage', 'All Unique', 'Simplex-Duplex', 'Duplex')

# Optional distinctive color palette
#' @param n Number of distinct colors to be returned
#' @return List of distinct colors (hue, luminance, contrast)?
gg_color_hue <- function(n) {
  hues = seq(15, 375, length = n + 1)
  lums = seq(0, 100, length = n + 1)
  hcl(h = hues, l = 65, c = 100)[1:n]
}

#' Util function to sort data by arbitrary list
#' @param df The data.frame to be sorted 
#' @param sort_column String - column to sort on
#' @param sort_list Vector of strings ordered in desired sort order for @df
sort_df = function(df, sort_column, sort_list) {
  sort_list = unique(unlist(sort_list))
  sort_list = as.factor(sort_list)
  df[[sort_column]] <- factor(df[[sort_column]], levels=sort_list)
  df = df[order(df[[sort_column]]),]
  df[[sort_column]] <- factor(df[[sort_column]], levels=unique(as.character(df[[sort_column]])) )
  return(df)
}


#' Function to read inputs
#' @param args Arguments from argv
#' @return Parsed list of (
#'   tables_output_dir_location,
#'   output_dir_for_plots,
#'   title_file_path
#' )
readInputs = function(args) {
  spec = matrix(c(
    'tablesOutputDir', 'i', 1, 'character',
    'plotsOutputDir', 'o', 1, 'character',
    'titleFilePath', 't', 2, 'character'
  ), byrow=TRUE, ncol=4);
  
  opts = getopt(spec);
  return(opts)
}


#' Count of read pairs per sample
#' @param data data.frame with Sample and total_reads columns
plotReadPairsCount = function(data) {
  data = data %>% mutate(read_pairs = TotalReads / 2)
  # Because the values for read counts are the same for both Pool A and Pool B, we just pick one
  data = filter(data, pool == 'A Targets')
  
  ggplot(data, aes(x = Sample, y = read_pairs)) + 
    geom_bar(stat='identity') + 
    ggtitle('Read Pairs') +
    scale_y_continuous('Count', label=format_comma) +
    MY_THEME
}


#' Function to plot number of reads that aligned to the reference genome
#' @param data data.frame with the usual columns
plotAlignGenome = function(data) {
  data$AlignFrac = as.numeric(data$AlignFrac)
  if ('Class' %in% colnames(data)) {
    fill_var = 'Class'
  } else {
    fill_var = 'Sample'
  }
 
  # Todo: is this 'on target' or 'aligned to human genome'?
  ggplot(data, aes(x=Sample, y=AlignFrac)) +
    geom_bar(position='dodge', stat='identity', aes_string(fill=fill_var)) +
    ggtitle('Fraction of Total Reads that Align to the Human Genome') +
    scale_y_continuous('Fraction of Reads', label=format_comma) + 
    coord_cartesian(ylim=c(0.8, 1)) +
    MY_THEME
}


#' Plot average coverage for each sample,
#' for each collapsing method
#' @param data data.frame with the usual columns
plotMeanCov = function(data) {
  data = filter(data, method %in% LEVEL_C)
  data = transform(data, method=factor(method, levels=LEVEL_C))
  data = transform(data, pool=factor(pool, levels=c('A Targets', 'B Targets')))
  data$total_or_collapsed = factor(ifelse(data$method == 'TotalCoverage', 'Total', 'Collapsed'), levels=c('Total', 'Collapsed'))
  data = data %>% arrange(total_or_collapsed, method)
  
  g = ggplot(data, aes(x=Sample, y=average_coverage)) +
    facet_grid(pool + total_or_collapsed ~ . , scales='free') +
    geom_bar(position='dodge', stat='identity', aes_string(fill='method')) +
    ggtitle('Average Coverage per Sample') +
    scale_y_continuous('Average Coverage', label=format_comma) +
    MY_THEME
  
  layout(matrix(c(1,2,2,2), nrow=4, ncol=2, byrow=TRUE))
  par(mfrow=c(2, 1))
  tt = ttheme_default(base_size=12)
  
  avg_cov_df = data %>% 
    group_by(Class, pool, method) %>% 
    summarise_at(vars(average_coverage), funs(mean(., na.rm=TRUE)))
  
  # Round to one decimal place
  avg_cov_df$average_coverage = round(avg_cov_df$average_coverage, 1)
  
  avg_cov_df = dcast(avg_cov_df, Class + pool ~ method, value.var='average_coverage')
  avg_cov_tbl = tableGrob(avg_cov_df, theme=tt, rows = NULL)
  grid.arrange(avg_cov_tbl, g, nrow=2, as.table=TRUE, heights=c(1,3))
}


#' Plot on target rate
#' (usually a metric for standard bams)
#' @param data data.frame with the usual columns
plotOnTarget = function(data) {
  ggplot(data, aes(x = Sample, y = TotalOnTargetFraction)) +
    geom_bar(position=position_stack(reverse=TRUE), stat='identity', aes(fill=pool)) +
    ggtitle('Fraction of On Target Reads') +
    scale_y_continuous('Fraction of Reads', label=format_comma, limits=c(0,1)) +
    MY_THEME
}


#' Plot Coverage vs %GC content, averaged over all samples 
#' (for each collapsing method)
#' @param data data.frame with the usual columns
plotGCwithCovAllSamples = function(data) {
  data = filter(data, method %in% LEVEL_C)
  data = transform(data, method=factor(method, levels=LEVEL_C))
  
  ggplot(data, aes(x=gc_bin, y=coverage, color=method, group=method)) +
    geom_line() +
    ggtitle('Average Coverage versus GC bias') +
    scale_y_continuous('Average Coverage (all samples)', label=format_comma) +
    xlab('GC bias') +
    MY_THEME
}


#' Plot Coverage vs %GC content, separately for each sample 
#' (for each collapsing method)
#' @param data data.frame with the usual columns
plotGCwithCovEachSample = function(data, sort_order) {
  data = data[complete.cases(data[, 'coverage']),]

  data = dplyr::filter(data, method %in% LEVEL_C)
  data = transform(data, method=factor(method, levels=LEVEL_C))
  data = transform(data, Sample=factor(Sample))

  ggplot(data, aes(x=gc_bin, y=coverage, group=Sample, color=Sample)) +
    facet_grid(method ~ ., scales='free') +
    geom_line() +
    ggtitle('Average Coverage versus GC bias') +
    scale_y_continuous('Average Coverage', label=format_comma) +
    xlab('GC Bias') +
    MY_THEME
}


#' Plot the distribution of insert sizes (a.k.a. fragment lengths),
#' as well as most frequent insert sizes
#' @param insertSizes data.frame of Sample, FragmentSize, TotalFrequency, UniqueFrequency
plotInsertSizeDistribution = function(insertSizes) {
  insertSizes = insertSizes %>%
    group_by(Sample) %>%
    mutate(total_frequency_fraction = TotalFrequency / sum(TotalFrequency)) %>%
    ungroup()
  
  peaks = insertSizes %>% 
    group_by(Sample) %>%
    filter(TotalFrequency == max(TotalFrequency))

  ggplot(insertSizes, aes(x=FragmentSize, y=total_frequency_fraction, colour=Sample)) +
    stat_smooth(size=.5, n=200, span=0.05, se=FALSE, method='loess', level=.01) +
    ggtitle('Insert Size Distribution') +
    xlab('Insert Size') +
    ylab('Frequency (%)') +
    theme(legend.position = c(.75, .35)) +
    MY_THEME + 
    
    geom_text_repel(
      data=peaks,
      size=5,
      force=1,
      direction='y',
      show.legend=FALSE,
      segment.color='transparent',
      aes(x=Inf, y=Inf, label=paste(Sample, 'peak insert size:', FragmentSize)))
}


#' Distribution of coverage across targets (total and unique)
#' Function to plot histogram of coverage per target interval distribution
#' Coverage values are scaled by the mean of the distribution
plotCovDistPerIntervalLine = function(data) {
  data = data %>%
    group_by(Sample) %>%
    mutate(coverage_scaled = coverage / median(coverage))
  
  ggplot(data) +
    geom_line(aes(x=coverage_scaled, colour=Sample), stat='density') +
    ggtitle('Distribution of Coverages per Target Interval') +
    scale_y_continuous('Frequency', label=format_comma) +
    scale_x_continuous('Coverage (median scaled)') + 
    coord_cartesian(xlim=c(0, 3)) +
    theme(legend.position = c(.75, .35)) +
    MY_THEME
}


cleanup_sample_names_2 = function(data) {
  data = data %>% mutate(Sample = gsub('_md', '', Sample))
  data = data %>% mutate(Sample = gsub('-md', '', Sample))
  data = data %>% mutate(Sample = gsub('.bam', '', Sample))
  data = data %>% mutate(Sample = gsub('_IGO.*', '', Sample))
  data = data %>% mutate(Sample = gsub('-IGO.*', '', Sample))
  data = data %>% mutate(Sample = gsub('_bc.*', '', Sample))
  
  # Ex: ZS-msi-4506-pl-T01_IGO_05500_EF_41_S41
  #                                       ^^^^
  # data = data %>% mutate(Sample = gsub('_.\\d\\d$', '', Sample))
  data
}


#' Print the title file to our PDF
#' @param title_df
printTitle = function(title_df, coverage_df) {
  mytheme <- gridExtra::ttheme_default(
    base_size=18,
    core = list(
      fg_params=list(cex = .6),
      padding=unit(c(5, 3), "mm")),
    colhead = list(fg_params=list(cex = 0.5)),
    rowhead = list(fg_params=list(cex = 0.5))
  )
  
  # Round to one decimal place
  coverage_df$average_coverage = format(round(coverage_df$average_coverage, 1), nsmall = 1)
  # Cast the coverage values
  coverage_df = dcast(coverage_df, Sample ~ method + pool, value.var='average_coverage')
  coverage_df = coverage_df[,c('Sample', 'TotalCoverage_A Targets', 'TotalCoverage_B Targets', 'Duplex_A Targets')]
  colnames(coverage_df) = c('Sample', 'RawCoverage_A', 'RawCoverage_B', 'DuplexCoverage_A')
  
  # Merge in coverage data
  title_df = inner_join(title_df, coverage_df, by='Sample')
  # Remove some columns
  title_df = title_df[, !(names(title_df) %in% DROP_COLS)]
  # Clean Sample names for printing
  title_df = cleanup_sample_names_2(title_df)
  title_grob <- tableGrob(title_df, rows=NULL, theme=mytheme)

  title = textGrob(label = 'MSK-ACCESS QC Report', gp=gpar(fontsize=20, col='black'))
  date = format(Sys.time(), '%a %b %d %Y %H:%M')
  sub_header = paste(title_df[1, 'Pool'], date, sep=' - ')
  sub_header = textGrob(label = sub_header, gp=gpar(fontsize=20, col='black'))
  line = linesGrob(
    unit(c(0.05, 0.95), 'npc'),
    unit(1, 'npc'),
    gp=gpar(col='lightgrey', lwd=4))
  
  lay <- matrix(c(1,2,3,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4), byrow=TRUE)
  gs = list(title, sub_header, line, title_grob)
  grid.arrange(grobs=gs, layout_matrix=lay)
}


#' % Family Types Graph 
#' @param data data.frame with Sample, Type, and Count columns
plot_family_types <- function(family_types_A, family_types_B) {
  family_types_A$Count = as.numeric(family_types_A$Count)
  family_types_A$Pool = 'A Targets'
  
  family_types_B$Count = as.numeric(family_types_B$Count)
  family_types_B$Pool = 'B Targets'
  family_types_all = bind_rows(family_types_A, family_types_B)
  family_types_all[is.na(family_types_all)] <- 0
  
  family_types_all$Sample = factor(family_types_all$Sample)
  family_types_all$Type = factor(family_types_all$Type, levels=c('Duplex', 'Simplex', 'Sub-Simplex', 'Singletons'))
  family_types_all = family_types_all %>% mutate(Sample = gsub('_IGO.*', '', Sample))
  family_types_all = family_types_all %>% mutate(Sample = gsub('-IGO.*', '', Sample))
  family_types_all = cleanup_sample_names_2(family_types_all)
  
  # Convert to % family sizes
  family_types_all = family_types_all %>%
    group_by(Pool, Sample) %>%
    mutate(CountPercent = Count / sum(Count))
  
  ggplot(family_types_all, aes(x=Sample, y=CountPercent)) +
    geom_bar(position=position_fill(reverse = TRUE), stat='identity', aes(fill=Type)) + 
    facet_grid(Pool ~ ., scales='free') +
    scale_y_continuous('UMI Family Proportion', labels = percent_format()) +
    MY_THEME
}


#' Family sizes curves
#' @param data data.frame with Sample, FamilySize, and Frequency columns
plot_family_curves <- function(data) {
  data$Sample = factor(data$Sample)
  data = cleanup_sample_names_2(data)
  # Only plot the Plasma samples
  data = data %>% filter(Sample_type=='Plasma')
  
  g = ggplot(filter(data, FamilyType=='All'), aes(FamilySize, Frequency, color=Sample)) + 
    geom_point(size=.5) + 
    geom_line() + 
    ggtitle('All Unique Family Sizes') +
    xlab('Family Size') + 
    scale_y_continuous('Frequency', label=format_comma) +
    coord_cartesian(xlim = c(0, 40)) +
    MY_THEME
  print(g)
  
  g = ggplot(filter(data, FamilyType=='Simplex'), aes(FamilySize, Frequency, color=Sample)) + 
    geom_point(size=.5) + 
    geom_line() + 
    ggtitle('Simplex Family Sizes') +
    xlab('Family Size') + 
    scale_y_continuous('Frequency', label=format_comma) +
    coord_cartesian(xlim = c(0, 40)) +
    MY_THEME
  print(g)
  
  g = ggplot(filter(data, FamilyType=='Duplex'), aes(FamilySize, Frequency, color=Sample)) + 
    geom_point(size=.5) + 
    geom_line() + 
    ggtitle('Duplex Family Sizes') +
    xlab('Family Size') + 
    scale_y_continuous('Frequency', label=format_comma) +
    coord_cartesian(xlim = c(0, 40)) +
    MY_THEME
  print(g)
}



#' Util function to merge various computed tables with original experiment title file
#' @param data data.frame to be used
#' @param title_df The title file as a data.frame
mergeInTitleFileData = function(data, title_df) {
  merged = merge(data, title_df, by.x='Sample', by.y='Sample')
  merged
}


#' Read in the sort_order file, which looks like:
#' sample_id
#' sample_id
#' sample_id
#' ...
#' @param groups_file Path to groups file
#' @deprecated?
parse_sort_order = function(groups_file) {
  sort_order = read.table(groups_file, sep='\t', fill=FALSE, strip.white=TRUE)
  sort_order = unlist(sort_order)
  return(sort_order)
}


# Extract actual sample names from full filenames
#' Ex: sample_names = c('test_patient_T', 'test_patient_N')
#' test_patient_T_001_aln_srt_MD_IR_FX_BR --> test_patient_T
#' Todo: this will fail for sample_1, sample_10   !!!!!
cleanup_sample_names = function(data, sample_names) {
  find.string <- paste(unlist(sample_names), collapse = "|")
  find.string <- paste0('.*(', find.string, ').*', collapse='', sep='')
  data = data %>% mutate(Sample = gsub(find.string, '\\1', Sample))
  data
}


#' Read in all tables for plots
#' @param inDirTables location of tables from python tables_module
read_tables = function(inDirTables) {
  readCountsDataTotal = read.table(paste(inDirTables, 'read-counts-total.txt', sep='/'), sep='\t', head=TRUE)
  covPerInterval = read.table(paste(inDirTables, 'coverage-per-interval.txt', sep='/'), sep='\t', head=TRUE)
  insertSizes = read.table(paste(inDirTables, 'fragment-sizes.txt', sep='/'), sep='\t', head=TRUE)
  meanCovData = read.table(paste(inDirTables, 'coverage-agg.txt', sep='/'), sep='\t', head=TRUE)
  gcAllSamples = read.table(paste(inDirTables, 'GC-bias-with-coverage-averages-over-all-samples.txt', sep='/'), sep='\t', head=TRUE)
  gcEachSample = read.table(paste(inDirTables, 'GC-bias-with-coverage-averages-over-each-sample.txt', sep='/'), sep='\t', head=TRUE)
  
  # Todo: We are using initialWorkDirRequirement to put these in the current dir, for now
  family_types_A = read.table('family-types-A.txt', sep = "\t", header = TRUE, colClasses = c('character', 'character', 'numeric'))
  family_types_B = read.table('family-types-B.txt', sep = "\t", header = TRUE, colClasses = c('character', 'character', 'numeric'))
  families = read.table('family-sizes.txt', sep = '\t', header = TRUE, colClasses = c('numeric', 'character', 'numeric', 'character'))
  
  list(readCountsDataTotal, covPerInterval, insertSizes, meanCovData, gcEachSample, family_types_A, family_types_B, families)
}


# Main function that will provide all of the desired plots
main = function(args) {
  # Read arguments specifying where the required tables are
  # as well as where the plots should be put
  # todo - should return an object or named list, instead of this indexed list 
  args = readInputs(args)
  inDirTables = args$tablesOutputDir
  outDir = args$plotsOutputDir
  title_file = args$titleFilePath

  title_df = read.table(title_file, sep='\t', header=TRUE)
  # Use only two class labels
  # Todo: We need to handle "Primary", "Metastasis", "Normal", and "Normal Pool"
  title_df$Class = ifelse(title_df$Class == 'Normal', 'Normal', 'Tumor')
  title_df = cleanup_sample_names_2(title_df)
  # Title file sample colunn is used as sort order
  sort_order = unlist(title_df$Sample)
  print("Title dataframe:")
  print(title_df)
  
  # Read in tables
  df_list = read_tables(inDirTables)
  printhead = function(x) {print(head(x))}
  print("Dataframes:")
  lapply(df_list, printhead)
  
  # Fix sample names,
  # optionally sort by ordering in the title file,
  # merge in the title file data by sample id
  df_list = lapply(df_list, cleanup_sample_names, sort_order)
  #df_list = lapply(df_list, sort_df, 'Sample', sort_order)
  df_list = lapply(df_list, mergeInTitleFileData, title_df)
  
  # We have had problems here with sample names not matching between files and title_file entries
  print("Dataframes after processing:")
  lapply(df_list, printhead)
  
  readCountsDataTotal = df_list[[1]]
  covPerInterval = df_list[[2]]
  insertSizes = df_list[[3]]
  meanCovData = df_list[[4]]
  gcEachSample = df_list[[5]]
  family_types_A = df_list[[6]]
  family_types_B = df_list[[7]]
  families = df_list[[8]]
  
  # Define the output PDF file
  date = format(Sys.time(), '%a-%b-%d-%Y_%H-%M')
  final_filename = paste('qc_results', gsub('[:|/]', '-', date), 'pdf', sep='.')
  pdf(file = final_filename, height=11, width=18, onefile=TRUE)
  
  # Put title file on first page of PDF
  printTitle(title_df, meanCovData)
  
  # Choose the plots that we want to run
  print(plotReadPairsCount(readCountsDataTotal))
  print(plotAlignGenome(readCountsDataTotal))
  print(plotOnTarget(readCountsDataTotal))
  print(plotInsertSizeDistribution(insertSizes))
  print(plotCovDistPerIntervalLine(covPerInterval))
  print(plotMeanCov(meanCovData))
  print(plotGCwithCovEachSample(gcEachSample, sort_order))
  print(plot_family_types(family_types_A, family_types_B))
  plot_family_curves(families)
  
  dev.off()
}


# Parse arguments
argv = commandArgs(trailingOnly=TRUE)
# Run main()
main(argv)
# Show warnings after running
warnings()
