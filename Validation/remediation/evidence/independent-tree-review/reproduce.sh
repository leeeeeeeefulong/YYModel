#!/bin/zsh
set -eu
stage=/tmp/yymodel-remediation-integrated-20261005-8
artifact=/tmp/yymodel-independent-tree-review-20261005
swiftc -swift-version 6 -I "$stage" -L "$stage" -lYYModelSwift -Xlinker -rpath -Xlinker "$stage" "$artifact/HookConsumer.swift" -o "$artifact/HookConsumer" -parse-as-library
"$artifact/HookConsumer" "$artifact/hook-results.json"
