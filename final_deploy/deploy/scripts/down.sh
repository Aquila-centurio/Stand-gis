#!/bin/sh
# Остановка и полная очистка стенда (включая lab-каталог clab-gis).
set -eu
cd "$(dirname "$0")/.."
sudo containerlab destroy -t topology.clab.yml --cleanup
