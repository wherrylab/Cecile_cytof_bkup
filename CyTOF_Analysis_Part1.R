## The purpose of this script is to perform multiple regression analysis on data extracted from FlowJo analysis of CyTOF-normalized fcs files

## For a matter of clarity,provided here is an example where the association of a given treatment with CyTOF-generated immunophenotypes is investigated
## For doing this,normalized fcs files are imported into a predefined FlowJo_T.wspt template
## After carefully reviewing the gates,the pre-defined table  is exported as a .csv file, and loaded here in this script

## The steps described below will allow us to run  multiple linear regression analysis, where (i) Group is the treatment (= 'treated versus control' = predictor), 
## (ii) CyTOF is the response, (iii) age, gender, tabac, BMI,..., and batch variables can be included as Control/covariates
## This is meant to answer the question: ??For example can any significant association of treatment with features of T cells in circulation can be detected? ?? 

## For ease of organization,creating a CyTOF Folder with the following subfolders is recommended: 
# CyTOF_Normalized_Files
# CyTOF_Tables
# CyTOF_Subset_Files
# CyTOF_cytofkit
# CyTOF_plots

#### Set wd and useful packages ---------------------------------------------------------------
setwd(".")
library(dplyr)
library(rio)
library(ggplot2)
library(RColorBrewer)
library(stringr)
library(scales)
library(ggthemes)

brewer.set <- "Set1"
brewer.colours.treated <- brewer_pal(palette = brewer.set)(5)[c(5,1)]
font_family="Helvetica"

#### Set up 4 Functions: CreateModelList, GetLmNames, FitLinearModels2, SelectSignificantTests, and PlotResult --------
CreateModelList <- function(models.2.fit, controls){
  CreateModelSubList <- function(models.2.fit, controls){
    lapply(1:nrow(models.2.fit), function(i) list(model = c(models.2.fit[i, -1]), 
                                                  treatments = models.2.fit[i, "treatment"],
                                                  response = models.2.fit[i, "response"]))
  }
  controls <- c("Control")
  models.2.fit <- as.matrix(models.2.fit)
  models.2.fit <- CreateModelSubList(models.2.fit, controls)
}


GetLmNames <- function(frame){
  levels.4.frame <- lapply(frame, levels)
  Reduce(c, lapply(names(levels.4.frame), function(x) paste0(x, levels.4.frame[[x]][-1])))
}

FitLinearModels2 <- function(model.list, variable.frame){
  FitSpecifiedModel <- function(model, variable.frame){
    treatments.lm.names <- GetLmNames(variable.frame[model$treatments])
    data_in<-data.frame(y = variable.frame[[model$response]], variable.frame[model$model])
    
    fit_level<-function(ref_group,model,data_in){
      
      lm_Res<-data.frame(summary(lm(y ~ relevel(Group,ref=ref_group) ,data = data_in ,
                                    singular.ok = FALSE, na.action = na.omit))$coefficients[-c(1),,drop = FALSE])
      lm_Res$Comp_group<-rownames(lm_Res)
      lm_Res$Comp_group <- gsub("relevel(Group, ref = ref_group)", "",lm_Res$Comp_group)
      data.frame(response = model$response, treatment = model$treatments,Ref_group=ref_group,lm_Res , row.names = NULL)
    }
    groups<-as.character(unique(data_in$Group))
    result.frame <- as.data.frame(Reduce(rbind, lapply(groups, fit_level,model=model, data_in=data_in)))
  }
  result.frame <- as.data.frame(Reduce(rbind, lapply(model.list, FitSpecifiedModel, variable.frame = variable.frame)))
  names(result.frame)[4:7] <- c("estimate", "se", "t", "p")
  result.frame$fdr <- p.adjust(result.frame$p, method = "fdr" )
  result.frame
}

# here in sign.levels, you can set the threshold for significance = threshold/2, ie here 0.025 means a threshold at P=0.05
SelectSignificantTests <- function(inference.results, sign.measure = "p", sign.level = 0.025){
  is.significant <- inference.results[,sign.measure] <= sign.level*2
  number.of.significant.tests <- sum(is.significant)
  alpha <- number.of.significant.tests/nrow(inference.results)*sign.level/2
  prob.thresh <- qnorm(1-alpha)
  sign.effects <- inference.results[is.significant,]
  sign.effects.plot.frame <- data.frame(sign.effects[,c("treatment", "response", "Ref_group","Comp_group")], 
                                        mean = sign.effects$estimate,
                                        lower = sign.effects$estimate-prob.thresh*sign.effects$se,
                                        higher = sign.effects$estimate+prob.thresh*sign.effects$se, stringsAsFactors = FALSE)
  sign.effects.plot.frame$legend <- factor(sign.effects.plot.frame$response)
  sign.effects.plot.frame
}

PlotResult <- function(sign.effects.plot.frame){
  path <- file.path(".", "Plots")
  ifelse(!dir.exists(path), dir.create(path), FALSE)
  sign.treatments <- unique(sign.effects.plot.frame$treatment)
  for(j in seq_along(sign.treatments)){
    sign.treatment <- sign.treatments[j]
    plt.vars <- sign.effects.plot.frame %>% filter(treatment == sign.treatment)
    plt <- ggplot(plt.vars, aes(x = reorder(legend, desc(mean)), y = mean, ymin = lower, ymax = higher))
    plt <- plt+geom_point(size = 1, shape=21, fill="purple") + geom_errorbar(width=0.7, position=position_dodge(0.05), color="purple")
    plt <- plt+coord_flip()+ggtitle(sign.treatment)
    plt <- plt+xlab("")+theme_par(base_size = 40) + theme(plot.title=element_text(size=12, face="bold"), panel.grid.major = element_line(colour = "gray80"), axis.text =element_text(size = font.size, face="bold"), axis.title = element_text(size =font.size, face="bold"), legend.title = element_text(size = font.size, face="bold"),axis.title.x = element_text(face="bold", size=20),
                                                          axis.text.x  = element_text(size=16),axis.title.y = element_text(face="bold", size=20),
                                                          axis.text.y  = element_text(size=16))
    plt <- plt+ylab("Effect size") +  guides(colour = guide_legend(title = "Significant (FDR < 0.05)"))
    plt <- plt+facet_grid(.~Comparison)
    ggsave(filename = file.path(path, paste0(sign.treatment, ".pdf")), plt, width = plot.width, height = plot.height)
  }  
}

#### Define graphical parameters ---------------------------------------------------------------
font.size=14
plot.width <- 20
plot.height <- 14

#### Upload 2 dataframes ---------------------------------------------------------------
# (i) the Demo, a table where each line is a donor identified by an ID, and in columns you will have included your "treatment" variables in "Group", as well as all other needed "Control" covariates, 
# In our example, the ID column header is coded as SUBJID, the Group column contains information about the status (Control versus Treated) of the donors, and the Control column indicates the experiment number
# and (ii) the "response" dataframe - here the csv file exported from FlowJo 

Demo = read.csv("Table.csv", header=TRUE, stringsAsFactors = F,row.names = 1)
#Ignore the last two rows which are the Mean and SD for each exported column from FlowJo
#make sure your treatment variables are factors
Demo = Demo[-c((nrow(Demo)),(nrow(Demo)-1)),]

#Create the group column accordingly
n1=4
Demo$Group=as.factor(c(rep("Control",n1),rep("Treated",(nrow(Demo)-n1))))

# make sure your response immunophenotypes are numeric values
Demo[,1:(ncol(Demo)-1)]  <- lapply(Demo[,1:(ncol(Demo)-1)], function(x) {
  if(is.integer(x)) as.numeric(as.character(x)) else x
})
#### Identify the treatment variables you want to explore - for example here CMV serostatus, but you may choose several ones ---------------------------------------------------------------
# you need to keep SUBJID column herein
Demo$SUBJID=rownames(Demo)
treatment = Demo %>% select(Group, SUBJID)

#### Identify the dataset with your response variables = the CyTOF-based FlowJo-exported .csv dataet, and normalize MFIs ---------------------------------------------------------------
CyTOF = Demo[,1:(ncol(Demo)-2)]
is.mfi <- grepl("^MFI.", colnames(CyTOF))
is.percentage <- grepl("^Percentage", colnames(CyTOF))
#MFI values are normalized using log10 transformation
CyTOF=cbind(CyTOF[,is.percentage],log10(CyTOF[,is.mfi]))

# you need to include SUBJID column herein
CyTOF_SUBJID = select(Demo, SUBJID)
CyTOF= bind_cols(CyTOF, CyTOF_SUBJID)

# Approach for imputing missing NA values
# Normalization by the mean as in below is recommended:

# count NA values in each column
sapply(CyTOF, function(x) sum(is.na(x)))
# impute NA values in each column with mean
for(i in 1:ncol(CyTOF)){
  CyTOF[is.na(CyTOF[,i]), i] <- mean(CyTOF[,i], na.rm = TRUE)
}

#### Merge your CyTOF and treatment dataets ---------------------------------------------------------------
CyTOF = semi_join(CyTOF, treatment, by="SUBJID")
# remove SUBJID
CyTOF = CyTOF %>% select(-SUBJID)

#### Isolate covariates you need as Control in the regression ---------------------------------------------------------------
cova = Demo %>% select(SUBJID, Group)
# merge your cova and treatment dataets
cova = semi_join(cova, treatment, by="SUBJID")
# remove SUBJID from both dataframes
cova = cova %>% select(-SUBJID)
treatment = treatment %>% select(-SUBJID)

#### Run the regression analysis ---------------------------------------------------------------
# Build a single processed dataframe
variable.frame <- cbind(treatment, cova, CyTOF)
# Create Model List
models.2.fit <- expand.grid(response = names(CyTOF), treatment = names(treatment), stringsAsFactors = FALSE)
model.list <- CreateModelList(models.2.fit)
# Fit Linear Models
inference.results <- FitLinearModels2(model.list, variable.frame)
inference.results$Comp_group <- gsub("\\(", "",inference.results$Comp_group)
inference.results$Comp_group <- gsub("\\)", "",inference.results$Comp_group)
inference.results$Comp_group <- gsub("relevelGroup, ref = ref_group", "",inference.results$Comp_group)
# Export the inference results on a csv file
export(inference.results, "inference_results.csv")
# SelectSignificantTests
inference.frame <- SelectSignificantTests(inference.results)
inference.frame$Comparison=paste0(inference.frame$Comp_group,"-",inference.frame$Ref_group)

# PlotResult
inference.plots <- PlotResult(inference.frame)


###### Marker wise MFI plot in each subset
var=colnames(Demo)[1:(ncol(Demo)-3)]
for (variable in var) {
  a <- ggplot(data=Demo, aes(x=Group, y=get(variable), fill=Group))
  a <- a + geom_boxplot(colour="black", width=0.3, fatten=1, alpha=0.6, size=0.8, outlier.shape=NA)
  a <- a + geom_jitter(width=0.1, size=3, alpha=1)
  a <- a + scale_fill_manual(values = brewer.colours.treated)
  a <- a + theme_bw()
  a <- a + ylab(paste0("%", variable))
  a <- a + theme(legend.title=element_blank()) 
  a <- a + theme(legend.position="none")
  a <- a + theme(axis.text=element_text(size=12, face="bold"), axis.text.x=element_text(vjust=17, size=12, face="bold"))
  a <- a + theme(panel.border = element_rect(linetype = "solid", size=1, colour = "black"))
  a <- a + theme(axis.title=element_text(size=12, face="bold"),axis.ticks=element_line(size=1))
  a
  ggsave(filename=paste0(variable, ".pdf"), plot=a, device="pdf", path=file.path(".", "Plots"), width=5, height=3)
}

