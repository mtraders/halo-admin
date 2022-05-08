#!/bin/bash
script_dir=$(cd $(dirname $0);pwd)
pnpm build
rm -rf ../halo/src/main/resources/admin/*
cp -r dist/* ../halo/src/main/resources/admin/
