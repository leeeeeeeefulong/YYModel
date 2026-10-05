#!/bin/zsh
set -eu
stage=/tmp/yymodel-remediation-integrated-20261005-8
artifact=/tmp/yymodel-independent-tree-review-20261005
swiftc -swift-version 6 -I "$stage" -L "$stage" -lYYModelSwift -Xlinker -rpath -Xlinker "$stage" "$artifact/RepeatedCompatibilityConsumer.swift" -o "$artifact/RepeatedCompatibilityConsumer" -parse-as-library
"$artifact/RepeatedCompatibilityConsumer" "$artifact/repeated-compatibility-results.json"
