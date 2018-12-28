# Gets GOES-16 multiband satellite data files

mkdir -p data && \

# Day IDs that GOES-16 recognizes
DAY_START=360 # 12/26/2018
DAY_END=362 # 12/29/2018

# Days
for i in $(seq -f "%03g" $DAY_START $DAY_END); do

  # Hours
  for j in $(seq -f "%02g" 0 23); do
    echo 'Cloning' https://noaa-goes16.s3.amazonaws.com/ABI-L2-MCMIPC/2018/$i/$j/ '...' &&

    # Only get data from 15-minute intervals using janky regex adapted from here: https://rclone.org/filtering/
    rclone copy --include '*{00,15,30,45}[0-9][0-9][0-9].nc' publicAWS:noaa-goes16/ABI-L2-MCMIPC/2018/$i/$j/ ./data
  done
done
