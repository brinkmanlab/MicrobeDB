#!/usr/bin/env bash
SRCDIR="$(realpath $(dirname "$0"))"
module load python/3.9.6
virtualenv --no-download --system-site-packages venv
wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O venv/bin/jq
chmod +x venv/bin/jq
pip install yq biopython.convert
# TODO install entrez