# SETUP ###############################################################
rms <- ls()[ls() != "trees"]
rm(list=rms)
source("~/Documents/workflows/bird_trait_networks/setup.R")
setwd(input.folder) #googledrive/bird trait networks/inputs/data

# PACKAGES & FUNCTIONS ###############################################################

library(caper)
library(geiger)
library(PHYLOGR)
library(rnetcarto)

source(paste(script.folder, "functions.R", sep = ""))
source('~/Documents/workflows/Sex Roles in Birds/birds/bird app/app_output_functions.R', 
       chdir = TRUE)

# produce named vector of variable data to use for phyloCor analysis
getNamedVector <- function(var, data){
  x <- as.vector(as.numeric(data[,var]))
  names(x) <- data$species
  return(x)
}

# Produce new phylo.matrix for subset of species
subsetPhylomat <- function(spp, phylomat, match.dat = NULL){
  
  nsps <- length(spp) 
  vmat <- matrix(NA, nrow = nsps, ncol = nsps, dimnames = list(spp, spp))
  
  m.id <- cbind(rep(spp, times = nsps), rep(spp, each = nsps))
  
  if(is.null(match.dat)){
    if(all(spp %in% unlist(dimnames(phylomat)))){p.id <- m.id}else{
      stop("data species names do not match phylogeny tip names. correct or provide match.dat data.frame")}
  }else{
    p.id <- cbind(rep(match.dat$synonyms[match(spp, match.dat$species)], times = nsps), 
                  rep(match.dat$synonyms[match(spp, match.dat$species)], each = nsps))}
  
  vmat[m.id] <- phylomat[p.id]
  
  return(vmat)
}

phylo.mean <- function(x, phylomat){
  mean <-colSums(phylomat%*%x)/sum(phylomat)}

phylo.var <- function(x, mean, phylomat, nsps){
  var.x <-t(x-mean) %*% phylomat%*%(x-mean)/(nsps-1)
}

getPhyloCor <- function(x, y, phylomat, nsps){
  
  if(any(names(x) != names(y))){stop("vector species names mismatch")}
  if(dim(phylomat)[1] != dim(phylomat)[2]){stop("phylomat not square")}
  if(any(dimnames(phylomat)[[1]] != dimnames(phylomat)[[2]])){stop("phylomat dimnames mismatch")}
  if(any(names(x) != dimnames(phylomat)[[1]], names(x) != dimnames(phylomat)[[2]])){stop("x and phylomat name mismatch")}
  if(any(names(y) != dimnames(phylomat)[[1]], names(y) != dimnames(phylomat)[[2]])){stop("y and phylomat name mismatch")}
  
  
  mean.x <- phylo.mean(x, phylomat)
  mean.y <- phylo.mean(y, phylomat)
  
  var.x <- phylo.var(x, mean.x, phylomat, nsps = nsps)
  var.y <- phylo.var(y, mean.y, phylomat, nsps = nsps)
  
  cor.xy <- as.vector((t(x-mean.x) %*% phylomat%*%(y-mean.x)/(nsps-1))/sqrt(var.x*var.y))
  
  return(cor.xy)
}

calcTraitPairN <- function(data){
  
  vars <- names(data)[!names(data) %in% c("species", "synonyms")]
  
  var.grid <- expand.grid(vars, vars, stringsAsFactors = F)
  var.grid <- var.grid[var.grid[,1] != var.grid[,2],]
  
  indx <- !duplicated(t(apply(var.grid, 1, sort))) # finds non - duplicates in sorted rows
  var.grid <- var.grid[indx, ]
  
  countN <- function(x, data){sum(complete.cases(data[,c(x[1], x[2])]))}
  
  var.grid <- data.frame(var.grid, n = apply(var.grid, 1, FUN = countN, data = data))
  
}

comparePhyloCor <- function(x, data, phylomat, match.dat, tree){
  
  var1 <- unlist(x[1])
  var2 <- unlist(x[2])
  
  data <- data[, c("species", "synonyms", var1, var2)] 
  data <- data[complete.cases(data),]
  
  spp <- data$species
  nsps <- length(spp)
  
  x <- getNamedVector(var1, data = data)
  y <- getNamedVector(var2, data = data)
  
  # Std. correlation
  
  cor <- cor(x, y)
  
  
  #METHOD 1 using phylogenetic relatedness matrix:
  #----------------------------------------------------
  
  #sub.phymat <- subsetPhylomat(spp, phylomat, match.dat)
  
  sub.tree <- drop.tip(tree, tip = tree$tip.label[!tree$tip.label %in% match.dat$synonyms[match(spp, match.dat$species)]])
  sub.phymat <-solve(vcv.phylo(sub.tree))
  spp.m <- match.dat$species[match(sub.tree$tip.label, match.dat$synonyms)]
  x <- x[match(spp.m, names(x))]
  y <- y[match(spp.m, names(y))]
  
  dimnames(sub.phymat) <- list(spp.m, spp.m)
  
  phylocor1 <- getPhyloCor(x, y, phylomat = sub.phymat, nsps = nsps)
  
  
  
  ################################################################################
  
  #METHOD 2 extracting from a PGLS
  #----------------------------------------------------
  
  cd <- comparative.data(phy = tree, data = data, names.col = "synonyms")
  result.pgls <- try(pgls(as.formula(paste(var1, "~", var2, sep = "")), data = cd), silent = T)
  if(class(result.pgls) == "try-error"){phylocor2 <- NA}else{
    
    t <- summary(result.pgls)$coefficients[var2,3]
    df <- as.vector(summary(result.pgls)$fstatistic["dendf"])
    phylocor2 <- sqrt((t*t)/((t*t)+df))*sign(summary(result.pgls)$coefficients[var2,1])
  }
  
  
  return(data.frame(var1 = var1, var2 = var2, cor = cor, phylocor1 = phylocor1, 
                    phylocor2 = phylocor2, n = nsps))
}

pglsPhyloCor <- function(x, data, match.dat, tree, log.vars){
  
  var1 <- unlist(x[1])
  var2 <- unlist(x[2])
  
  data <- data[, c("species", "synonyms", var1, var2)] 
  data <- data[complete.cases(data),]
  
  spp <- data$species
  nsps <- length(spp)
  
  if(var1 %in% log.vars & all(data[,var1] > 0)){
    data[,var1] <- log(data[,var1])
    names(data)[names(data) == var1] <- paste("log", var1, sep = "_")
    var1 <- paste("log", var1, sep = "_")

  }
  if(var2 %in% log.vars & all(data[,var2] > 0)){
    data[,var2] <- log(data[,var2])
    names(data)[names(data) == var2] <- paste("log", var2, sep = "_")
    var2 <- paste("log", var2, sep = "_")
  }
  
  # Std. correlation
  cor <- cor(data[,var1], data[,var2])
  
  
  #METHOD 2 extracting from a PGLS
  #----------------------------------------------------
  
  cd <- comparative.data(phy = tree, data = data, names.col = "synonyms", vcv=F)

  result.pgls <- try(pgls(as.formula(paste(var1, "~", var2, sep = "")), data = cd, lambda="ML"), 
                     silent = T)

  
  if(class(result.pgls) == "try-error"){
    phylocor2 <- NA
    lambda <- NA
    aicc <- NA
  }else{
    
    t <- summary(result.pgls)$coefficients[var2,3]
    df <- as.vector(summary(result.pgls)$fstatistic["dendf"])
    phylocor2 <- sqrt((t*t)/((t*t)+df))*sign(summary(result.pgls)$coefficients[var2,1])
    lambda <- result.pgls$param["lambda"]
    aicc <- result.pgls$aicc
  }
  
  
  return(data.frame(var1 = var1, var2 = var2, cor = cor, phylocor = phylocor2, n = nsps,
                    lambda = lambda, aicc = aicc))
}






# SETTINGS ###############################################################

# dir.create(paste(output.folder, "data/phylocors/", sep = ""))
# dir.create(paste(output.folder, "data/networks/", sep = ""))

qcmnames = c("qc", "observer", "ref", "n", "notes")
taxo.var <- c("species", "order","family", "subspp", "parent.spp")
var.var <- c("var", "value", "data")
var.omit <- c("no_sex_maturity_d", "adult_svl_cm", "male_maturity_d")
an.ID <- "100spp"
log <- T
if(log){log.vars <- metadata$master.vname[as.logical(metadata$log)]}else{log.vars <- ""}


# FILES ##################################################################

master <- read.csv(file ="csv/master.csv", fileEncoding = "mac")
spp100 <- unlist(read.csv(file ="csv/100spp.csv"))

spp.list <- data.frame(species = unique(master$species))
synonyms  <- read.csv("r data/synonyms.csv", stringsAsFactors=FALSE)
r.synonyms <- read.csv("r data/bird_species_names.csv", stringsAsFactors=FALSE)
m.synonyms <- read.csv("r data/match data/tree mmatched.csv", stringsAsFactors=FALSE)

# trees <- read.tree(file = "tree/Stage2_MayrAll_Hackett_set10_decisive.tre")
# tree <- trees[[1]]
# save(tree, file = "tree/tree.RData")
load(file = "tree/tree.RData")

# WORKFLOW ###############################################################


################################################################################
## Match tree species names to master species list
treespp <- data.frame(species = tree$tip.label)

dl <- processDat(file = NULL, dat = treespp, label = F, taxo.dat, var.omit, input.folder,
           observer = NULL, qc = NULL, ref = "Hackett", n = NULL, notes = NULL,
           master.vname = "master.vname")

m <- matchObj(data.ID = "tree", spp.list = spp.list, data = dl$data, 
              status = "unmatched", 
                          sub = "spp.list",
                          qcref = dl$qcref)

unmatched <- m$spp.list$species[!m$spp.list$species %in% m$data$species]

m <- dataSppMatch(m, unmatched, ignore.unmatched = T, synonyms = r.synonyms, trim.dat = F, 
                  retain.dup = F)

unmatched <- m$spp.list$species[!m$spp.list$species %in% m$data$species]

m <- dataSppMatch(m, unmatched, ignore.unmatched = T, synonyms = synonyms, 
                  trim.dat = F, retain.dup = F)


unmatched <- m$spp.list$species[!m$spp.list$species %in% m$data$species]

m <- dataSppMatch(m, unmatched, ignore.unmatched = F, synonyms = m.synonyms, 
                  trim.dat = F, retain.dup = F)

save(m, file = "r data/match data/tree m.RData")

################################################################################

#load match data
load(file = "r data/match data/tree m.RData")
match.dat <- m$data

# Create wide dataset:
wide <- widenMaster(vars = unique(master$var), species = unique(master$species), 
                    master = master, metadata = metadata)

# separate numeric variables
num.var <- metadata$master.vname[metadata$type %in% c("Int", "Con")]
num.dat <- wide[,c("species", names(wide)[names(wide) %in% num.var])]

#Remove duplicate species matching to the same species on the tree
num.dat <- num.dat[num.dat$species %in% match.dat$species[match.dat$data.status != "duplicate"],]

# add synonym column to data 
num.dat$synonyms <- match.dat$species[match(num.dat$species, match.dat$species)]


# SUBSET TO 100 SPECIES #####################################################################

if(an.ID == "100spp"){
num.dat <- num.dat[num.dat$species %in% spp100,]}


# VARIABLES #################################################################################

## Create grid of unique variable combinations, calculate data availability for each and sort
var.grid <- calcTraitPairN(num.dat)
var.grid <- var.grid[var.grid$n > 3,]
var.grid <- var.grid[order(var.grid$n, decreasing = T),]

#Prepare phylogenetic relatedness matrix

# phylomat <-solve(vcv.phylo(tree))  #REALLY TIME CONSUMING
# save(phylomat, file = "tree/phylomat.RData")
# load(file = "tree/phylomat.RData")




res <- NULL
for(i in 1:dim(var.grid)[1]){
  
  res <- rbind(res, pglsPhyloCor(var.grid[i,1:2], data = num.dat, 
               match.dat = match.dat, tree = tree, log.vars = log.vars))
  print(i)
}


res <- res[order(abs(res$phylocor), decreasing = T),]

write.csv(res, paste(output.folder, "data/phylocors/", an.ID," phylocor", if(log){" log"},".csv", sep = ""),
          row.names = F)


## NETWORK ANALYSIS ####################################################################

library(rnetcarto)
net.d <- res[!is.na(res$phylocor), c("var1", "var2", "phylocor")]
net.list <- as.list(net.d)
net <- netcarto(web = net.list, seed = 1)


write.csv(cbind(net[[1]], modularity = net[[2]]), paste(output.folder, "data/networks/", an.ID," network", if(log){" log"},".csv", sep = ""),
          row.names = F)





# RCytoscape ###############################################################################

#source('http://bioconductor.org/biocLite.R')
biocLite ('RCytoscape')

