#!/usr/bin/env bash
set -euo pipefail

TOOLVERSION=$2

VIVADO_ROOT="/proj/octfpga-PG0/tools/Xilinx/Vivado/${TOOLVERSION}"

echo "Using Vivado from: $VIVADO_ROOT"

# 1) system deps for p4c-vitisnet + p4bm-vitisnet
sudo apt-get update
sudo apt-get install -y \
  libboost-system-dev libboost-iostreams-dev libboost-filesystem-dev \
  libssl1.1 ca-certificates python3 python3-pip

# 2) put Vivado env in /etc/profile for future logins
# Use Vivado-only settings to avoid Model Composer issues.
sudo bash -c "echo 'source ${VIVADO_ROOT}/.settings64-Vivado.sh' >> /etc/profile"

# 3) quick sanity checks
source "${VIVADO_ROOT}/.settings64-Vivado.sh"
command -v p4c-vitisnet
command -v run-p4bm-vitisnet
echo "Vivado+VitisNetP4 CLI OK."

echo "Done."
