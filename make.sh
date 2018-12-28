# Set up directories
rm -rf tmp && \
rm -rf final && \

mkdir -p tmp && \
mkdir -p final && \
cd data &&

# Declare helper variables for text writing later

# Lookup table from GOES-16 days to English language days. NOTE: Gotta adjust
# these for time zones too.
declare -a days=( \
  ["360"]="Dec. 26" \
  ["361"]="Dec. 27" \
  ["362"]="Dec. 28" \
  ["363"]="Dec. 29") \

# Hours. The #10 are so those values aren't interpreted as octal. This also
# handles the time zone conversion because input times are in UTC. Values are
# in Central time. NOTE: Double-check daylight savings time here.
declare -a hours=( \
  ["00"]="6 p.m." \
  ["01"]="7 p.m." \
  ["02"]="8 p.m." \
  ["03"]="9 p.m." \
  ["04"]="10 p.m." \
  ["05"]="11 p.m." \
  ["06"]="12 a.m." \
  ["07"]="1 a.m." \
  [10#"08"]="2 a.m." \
  [10#"09"]="3 a.m." \
  ["10"]="4 a.m." \
  ["11"]="5 a.m." \
  ["12"]="6 a.m." \
  ["13"]="7 a.m." \
  ["14"]="8 a.m." \
  ["15"]="9 a.m." \
  ["16"]="10 a.m." \
  ["17"]="11 a.m." \
  ["18"]="12 p.m." \
  ["19"]="1 p.m." \
  ["20"]="2 p.m." \
  ["21"]="3 p.m." \
  ["22"]="4 p.m." \
  ["23"]="5 p.m.")

# For testing
# declare -a arr=("OR_ABI-L2-MCMIPC-M3_G16_s20183590012148_e20183590014521_c20183590015021.nc")

x=0
for i in *.nc; do

  # echo $i

  # Get day/time values from filenames for use later
  day_raw=${i:61:3}
  hour_raw=${i:64:2}
  minute=${i:66:2}

  hour_display=$(echo ${hours[10#$hour_raw]}} | cut -d" " -f1)
  am_pm=$(echo ${hours[10#${i:64:2}]} | cut -d" " -f2)

  # Horrible hack to deal with timezone change issue with dates. This is specific
  # to Central time (GMT-6)
  tmp=$day_raw
  if [[ 10#$hour_raw -lt "06" ]] && [[ 10#$hour_raw -ge "00" ]]; then
    tmp=$(( $day_raw - 1 ))
  fi
  
  day_display=${days[tmp]}
  
  # Build composite images
  python ../_plot_image.py $i ../tmp/$x.tmp.tif &&
  
  # Clip to Midwesty angle (-te param), the bounds of which I estimated by hand in QGIS
  gdalwarp \
    -q \
    -te -3023718 2458757 -37262 4560300 \
    -ts 0 900 \
    -dstalpha \
    -r bilinear \
    ../tmp/$x.tmp.tif ../tmp/$x.clipped.tmp.tif
  
  # Reproject lines file (for testing)
  # ogr2ogr -s_srs "+proj=longlat +datum=NAD83" -t_srs "+proj=geos +lon_0=-75 +lat_0=35 +h=35786023 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs +sweep=x" -skipfailures ../vector/states-geos.shp ../vector/cb_2017_us_state_500k.shp &&
  # mapshaper ../vector/states-geos.shp -lines -o ../vector/states-lines.shp

  # Burn boundary lines in black (0, 0, 0) from pre-projected vector files
  gdal_rasterize \
    -b 1 -b 2 -b 3 \
    -burn 0 -burn 0 -burn 0 \
    -l states-lines ../vector/states-lines.shp ../tmp/$x.clipped.tmp.tif

  # Convert to png and move to final
  sips -s format png ../tmp/$x.clipped.tmp.tif --out ../final/color.$x.png

  # Apply day, time and sourcing labels using ImageMagick
  convert ../final/color.$x.png \
    -font Helvetica-Bold \
      -size 165x70 \
      -pointsize 60 \
      -fill '#dfdfdf' \
      -weight 1000 \
      -gravity SouthWest \
      -annotate +25+60 "$day_display" \
    -font Helvetica-Bold \
      -size 165x70 \
      -pointsize 28 \
      -fill '#dfdfdf' \
      -weight 1000 \
      -gravity SouthWest \
      -annotate +25+20 "$hour_display:$minute $am_pm (CST)" \
    -font Helvetica-Bold \
      -pointsize 14 \
      -fill '#dfdfdf' \
      -weight 1000 \
      -gravity SouthEast \
      -annotate +25+15 "Source: NASA GOES-16 satellite, via the Open Commons Consortium" \
    ../final/color.$x.png

  # Clean up
  rm ../tmp/*

  # Open test file directly in Preview (for testing)
  # open -a Preview ../final/color.$x.png

  x=$((x+1))
done

# Convert to mp4. Stole this from Nat Lash.
# https://github.com/lashback/GOES-16-scripts
cd ../final && \
ffmpeg \
  -r 18 \
  -f image2 \
  -i color.%d.png \
  -vcodec libx264 \
  -crf 25 \
  -aspect 16:9 \
  -vf "scale=1280:trunc(ih/2)*2" \
  -pix_fmt yuv420p output.mp4
# rm ./*.png
