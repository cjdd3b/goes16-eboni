#!/usr/bin/env python

# FWIW, this is basically a mildly juiced-up version of the code written here:
# https://github.com/occ-data/goes16-play
# I would have have no idea how to create clean IR masks, etc., if not for that code.

import sys
import os.path
import numpy as np
from osgeo import gdal, osr
from netCDF4 import Dataset

########## HELPER FUNCTIONS ##########

def mask_and_normalize(arr, mask=None):
    '''
    Normalizes the data for geotiff export and applies an optional mask.
    '''
    if mask.any():
        arr = np.maximum(arr, mask)

    # Normalize the data according to instructions here:
    # https://gis.stackexchange.com/questions/273686/convert-aws-goes-data-to-geotiff
    arr.data[arr.data == 65535] = -1
    normalized = arr.data * 255
    normalized[normalized == -255] = 255

    # Return data represented as 8-bit integer
    return normalized.astype('uint8')

########## MAIN ##########

# Turn it into a command-line thing so we can run it from make.sh
if len(sys.argv) < 2:
    print "Usage: ./plot.py <MCMIP netcdf file> <output.png>"
    sys.exit()

infile = sys.argv[1]
outfile = sys.argv[2]

# Don't overwrite anything that already exists
if os.path.isfile(outfile) == False:
    print "making %s plot " % outfile

    # Open the NetCDF File
    g16nc = Dataset(infile, 'r')

    # Get the Blue, Red, and Veggie bands + gamma correct
    blue_band = np.ma.array(np.sqrt(g16nc.variables['CMI_C01'][:]))
    red_band = np.ma.array(np.sqrt(g16nc.variables['CMI_C02'][:]))
    veggie_band = np.ma.array(np.sqrt(g16nc.variables['CMI_C03'][:]))

    # Create an actual green band, per the calculation here: http://edc.occ-data.org/goes16/python/
    # More info here: https://www.star.nesdis.noaa.gov/GOES/documents/ABIQuickGuide_CIMSSRGB_v2.pdf
    green_band = (0.48358168 * red_band) + (0.45706946 * blue_band) + (0.06038137 * veggie_band)

    # Prepare the Clean IR band (13) by converting brightness temperatures to grayscale values. Honestly I
    # have no idea what this is doing. I just stole it from here: https://github.com/occ-data/goes16-play
    # Ultimately it is used to create a nighttime mask so that night clouds appear black and white.
    cleanir = g16nc.variables['CMI_C13'][:]
    cir_min = 90.0
    cir_max = 313.0
    cleanir_c = (cleanir - cir_min) / (cir_max - cir_min)
    cleanir_c = np.maximum(cleanir_c, 0.0)
    cleanir_c = np.minimum(cleanir_c, 1.0)
    cleanir_c = 1.0 - np.float64(cleanir_c)

    # Here's where it gets ugly. Some of the following values are hard-coded based on a previously
    # converted GeoTIFF that I know works. There must be a better way to do this them. The command
    # to get the original tifs is:
    # gdal_translate -ot float32 -unscale -CO COMPRESS=deflate NETCDF:"$i":CMI_C01 ../tmp/c01.tmp.tif

    # Width, height of the resulting output tif
    width = 2500
    height = 1500

    # Hard-coded bounds (in meters) from the geostationary satellite projection
    # TODO: Detect this from input files somehow
    xmin, ymin, xmax, ymax = [-3627271.341, 1583173.792, 1382771.948, 4589199.765]

    # The x and y resolution
    xres = (xmax - xmin) / float(width)
    yres = (ymax - ymin) / float(height)

    # Prepare the geotransform, again stealing from here:
    # https://gis.stackexchange.com/questions/273686/convert-aws-goes-data-to-geotiff
    geotransform = (xmin, xres, 0, ymax, 0, -yres)

    # Absurdly, the rest of this is required to create a geotiff. 3 is the number of bands being output.
    dst_ds = gdal.GetDriverByName('GTiff').Create(outfile, width, height, 3, gdal.GDT_Byte)

    # Specify coords
    dst_ds.SetGeoTransform(geotransform)   

    # Establish encoding
    srs = osr.SpatialReference() 

    # Set output projection. Again, stole this from the input file. We should be able to not
    # hard code this. That said, you can vary the +lon_0 param to move the center of the image.      
    srs.ImportFromProj4('+proj=geos +lon_0=-75 +lat_0=45 +h=35786023 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs +sweep=x')  
    dst_ds.SetProjection(srs.ExportToWkt()) # Export coords to file

    # Write the three bands: R, G and B
    dst_ds.GetRasterBand(1).WriteArray(mask_and_normalize(red_band, cleanir_c))
    dst_ds.GetRasterBand(2).WriteArray(mask_and_normalize(green_band, cleanir_c))
    dst_ds.GetRasterBand(3).WriteArray(mask_and_normalize(blue_band, cleanir_c))

    # Write to disk
    dst_ds.FlushCache()
