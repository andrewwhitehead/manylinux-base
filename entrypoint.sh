#!/bin/sh -l
set -eux

# hack, move home to $HOME(/github/home)
ln -s /root/.cargo $HOME/.cargo
ln -s /root/.rustup $HOME/.rustup

# go to the repo root
export WORKSPACE="${GITHUB_WORKSPACE:-$HOME}"
cd $WORKSPACE
export CARGO_TARGET_DIR="$WORKSPACE/target"

if [ -z "$*" ]; then
    bash
else
    sh -c "$*"
fi
