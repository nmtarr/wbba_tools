# Script to add highest breeding evidence level to WBBA blocks. Results are exported to
# shapefile.


library(rgdal)
library(reshape2)
library(foreign)
library(here)


setwd(here::here("data"))

# name of output shapefile without extension
out_shp <- "evidence_by_block"

# birdpop alpha codes;
# common names are in "COMMONNAME", and 4-letter alpha codes are in "SPEC"
# source: http://www.birdpop.org/pages/birdSpeciesCodes.php
alpha <- read.dbf("LIST18.DBF", as.is = TRUE)

# arguments for readOGR are input format dependent;
# with a shapefile, the first argument is the directory containing the shp,
# and the second argument is the name of the shapefile without the extension
block_in <- readOGR("blk", "WbbaBlocks2015_v0_2")

# sample WBBA data from ebrid
sp_in <- read.csv("wbba2018.csv", as.is = TRUE)

# remove hybrid, spuh, and slash taxonomic categories
taxa <- c("species", "issf", "domestic", "form")
sp_in <- sp_in[sp_in$CATEGORY %in% taxa, ]

# add alpha codes needed later to name species columns with < 10 chars required
# for shapefile
sp_in <- merge(sp_in, alpha[, c("COMMONNAME", "SPEC")], by.x = "COMMON.NAME",
                 by.y = "COMMONNAME", all.x = TRUE, all.y = FALSE)

# check that all common names in sp_in were matched in alpha
any(is.na(sp_in$SPEC))  # should return false

# create a SpatialPointsDataFrame from "sp_in"
wgs84 <- CRS("+init=epsg:4326")  # use WGS84 as input CRS
sp_wgs <- SpatialPointsDataFrame(sp_in[, c("LONGITUDE", "LATITUDE")], sp_in,
                                 coords.nrs = c(23, 22), proj4string = wgs84)

# transform projection to match blocks
nad83 <- CRS(proj4string(block_in))  # use NAD83 from block_in
sp_nad <- spTransform(sp_wgs, nad83)

# extract blocks that overlay points;
# returns a data frame containing the same number rows as sp_nad;
# each row is a record from block that overlays the points in sp_nad
block_over <- over(sp_nad, block_in)
names(block_over)[13] <- "CO_eBird"  # COUNTY is in both data frames

# ...and join them to the bird data frame
sp <- cbind(sp_nad@data, block_over)

# add column for breeding evidence code
sp$conf <- 0

# list of lists containing the breeding codes;
# numbers are used at first instead of names to simply finding the highest
# breeding evidence
breeding_codes <- list(
  list(1, "Observed",  c("", "F")),
  list(2, "Possible",  c("H", "S")),
  list(3, "Probable",  c("S7", "M", "P", "T", "C", "N", "A", "B")),
  list(4, "Confirmed", c("PE", "CN", "NB", "DD", "UN", "ON", "FL", "CF",
                         "FY", "FS", "NE", "NY"))
)

# some of the BREEDING.BIRD.ATLAS.CODE codes have a space at the end
# and some don't - this removes the space
sp$BREEDING.BIRD.ATLAS.CODE <- trimws(sp$BREEDING.BIRD.ATLAS.CODE)

# assign numeric breeding code (1 = lowest, 4 = highest)
for (code in breeding_codes) {
  sp$conf[sp$BREEDING.BIRD.ATLAS.CODE %in% code[[3]]] <- code[[1]]
}

# function to assign breeding code name;
# for a given alpha code/block combo, all values of "conf" are passed to this
# function which returns the highest breeding evidence name
code_name <- function(x){
  code_num <- max(x)
  breeding_codes[[code_num]][[2]]
}

# this creates a data frame with BLOCK_ID as the 1st column, followed by
# columns for each alpha code, with breeding evidence name as the cell values
sp_cast <- dcast(sp, BLOCK_ID ~ SPEC, fun.aggregate = code_name,
                 fill = "", value.var = "conf")

# merge species with original blocks
block_out <- merge(block_in, sp_cast, by = "BLOCK_ID")

# write to disc as a shapefile
writeOGR(block_out, ".", "out_shp", driver = "ESRI Shapefile")