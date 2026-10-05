#!/bin/zsh
set -eu
review_dir=/tmp/yymodel-review-independent
snapshot_dir=/tmp/yymodel-remediation-integrated-20261005-7
for consumer in Probe RelatedPaths NegativeZero NullCollision; do
 swiftc -O -parse-as-library -swift-version 6 -I "$snapshot_dir" -L "$snapshot_dir" -lYYModelSwift -Xlinker -rpath -Xlinker "$snapshot_dir" "$review_dir/$consumer.swift" -o "$review_dir/$consumer"
done
"$review_dir/Probe" > "$review_dir/observations.log"
"$review_dir/RelatedPaths" "$review_dir/related-observations.json"
"$review_dir/NegativeZero" > "$review_dir/negativezero-observations.log"
"$review_dir/NullCollision" > "$review_dir/nullcollision-observations.log"
