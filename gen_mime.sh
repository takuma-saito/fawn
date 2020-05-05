#!/bin/bash -e
urls=`cat <<EOF
https://www.iana.org/assignments/media-types/video.csv
https://www.iana.org/assignments/media-types/application.csv
https://www.iana.org/assignments/media-types/font.csv
https://www.iana.org/assignments/media-types/text.csv
https://www.iana.org/assignments/media-types/image.csv
EOF`
echo $urls | tr ' ' '\n' | gxargs -I@ curl @ | awk -F',' '$2 != NULL {types[$1] = $2} END {for(ext in types) {print ext, types[ext]}}' |
    grep -v -E 'Name' |
    while read ext type; do
        echo "\"${ext}\": \"${type}\","
    done
