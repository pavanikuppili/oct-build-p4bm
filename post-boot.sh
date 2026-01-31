#!/usr/bin/env bash
# post-boot.sh (OCT / Ubuntu 22.04 / Vivado+Vitis 2024.2)
# Goal: Make p4c-vitisnet + run-p4bm-vitisnet work reliably on UBUNTU22-64-STD
# WITHOUT relying on /share/tools/u280/... and WITHOUT requiring Model Composer.
#
# Called from profile.py as:
#   sudo /local/repository/post-boot.sh <remoteDesktop True|False> <toolVersion e.g., 2024.2> >> /local/logs/output_log.txt

set -euo pipefail

REMOTEDESKTOP="${1:-False}"
TOOLVERSION="${2:?Missing TOOLVERSION arg (e.g., 2024.2)}"

TOOLS_ROOT="/proj/octfpga-PG0/tools"
SETTINGS_ORIG="${TOOLS_ROOT}/Xilinx/Vivado/${TOOLVERSION}/settings64.sh"
SETTINGS_LOCAL="/local/repository/settings64_${TOOLVERSION}_sanitized.sh"

# OpenSSL 1.1 compat install prefix (needed on Ubuntu 22.04 for libcrypto.so.1.1)
OPENSSL_VER="1.1.1w"
OPENSSL_PREFIX="/opt/openssl-1.1"

log() { echo "[$(date -Is)] $*"; }

require_file() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    log "ERROR: Required file not found: $f"
    exit 1
  fi
}

make_sanitized_settings64() {
  # We keep using settings64.sh semantics, but we source a local copy that:
  # - comments out Model Composer line (to prevent "No such file" failures)
  # - optionally comments out other missing components if you extend this list
  #
  # This avoids editing the shared /proj tool tree (which may be read-only).
  require_file "$SETTINGS_ORIG"

  log "Creating sanitized settings at: $SETTINGS_LOCAL"
  cp -f "$SETTINGS_ORIG" "$SETTINGS_LOCAL"

  # Always comment Model Composer source lines (safe even if already commented)
  sed -i \
    's|^[[:space:]]*source[[:space:]]\+/proj/octfpga-PG0/tools/Xilinx/Model_Composer/.*|#&|g' \
    "$SETTINGS_LOCAL"

  chmod 644 "$SETTINGS_LOCAL"
}

append_profile_source_once() {
  # Add a small /etc/profile.d snippet so interactive shells also pick up the toolchain.
  local prof="/etc/profile.d/xilinx_${TOOLVERSION}.sh"
  local line="source ${SETTINGS_LOCAL}"

  if [[ ! -f "$prof" ]] || ! grep -Fxq "$line" "$prof"; then
    log "Writing ${prof} to source sanitized settings64.sh at login"
    echo "$line" > "$prof"
    chmod 644 "$prof"
  else
    log "Profile already sources sanitized settings."
  fi
}

install_behavioral_deps() {
  log "Installing system dependencies (Boost, Python, build tools)"
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl \
    python3 python3-pip rlwrap \
    file lsof jq \
    build-essential perl make zlib1g-dev \
    libboost-system-dev libboost-iostreams-dev libboost-filesystem-dev \
    libboost-thread-dev libboost-regex-dev \
    zlib1g
}

install_openssl11_compat() {
  # On Ubuntu 22.04, libssl1.1 is not available via apt by default.
  # Vivado's p4bm-vitisnet requires libcrypto.so.1.1, so we install OpenSSL 1.1 into /opt
  # and register it with ldconfig. This does NOT replace system OpenSSL.
  if [[ -e "${OPENSSL_PREFIX}/lib/libcrypto.so.1.1" ]]; then
    log "OpenSSL 1.1 compat already present: ${OPENSSL_PREFIX}/lib/libcrypto.so.1.1"
    echo "${OPENSSL_PREFIX}/lib" > /etc/ld.so.conf.d/openssl-1.1.conf
    ldconfig
    return
  fi

  log "Installing OpenSSL ${OPENSSL_VER} compat into ${OPENSSL_PREFIX}"
  local tmp
  tmp="$(mktemp -d)"
  pushd "$tmp" >/dev/null

  local tar="openssl-${OPENSSL_VER}.tar.gz"
  local url="https://openssl-library.org/source/old/1.1.1/${tar}"

  # Prefer online fetch; fallback to local tarball if outbound network is blocked.
  if curl -fL -o "$tar" "$url"; then
    log "Downloaded ${tar}"
  else
    log "WARN: Could not download ${url}"
    log "      Fallback: place ${tar} at /local/repository/${tar} and re-run."
    if [[ -f "/local/repository/${tar}" ]]; then
      cp "/local/repository/${tar}" "./${tar}"
      log "Using local tarball: /local/repository/${tar}"
    else
      log "ERROR: No local tarball found at /local/repository/${tar}"
      popd >/dev/null
      rm -rf "$tmp"
      exit 1
    fi
  fi

  tar xzf "$tar"
  cd "openssl-${OPENSSL_VER}"

  ./config --prefix="${OPENSSL_PREFIX}" --openssldir="${OPENSSL_PREFIX}" shared zlib
  make -j"$(nproc)"
  make install_sw

  echo "${OPENSSL_PREFIX}/lib" > /etc/ld.so.conf.d/openssl-1.1.conf
  ldconfig

  popd >/dev/null
  rm -rf "$tmp"
  log "OpenSSL 1.1 compat installed."
}

install_remote_desktop_if_requested() {
  if [[ "${REMOTEDESKTOP}" == "True" ]]; then
    log "Installing remote desktop software (GNOME + TigerVNC)"
    apt-get update
    apt-get install -y ubuntu-gnome-desktop tigervnc-standalone-server
    systemctl set-default multi-user.target
    log "Remote desktop packages installed."
  else
    log "Remote desktop not requested."
  fi
}

sanity_check_tools() {
  log "Sanity checking toolchain by sourcing: ${SETTINGS_LOCAL}"
  # shellcheck disable=SC1090
  source "${SETTINGS_LOCAL}"

  log "PATH=$PATH"
  log "p4c-vitisnet => $(command -v p4c-vitisnet || echo MISSING)"
  log "run-p4bm-vitisnet => $(command -v run-p4bm-vitisnet || echo MISSING)"
  log "p4bm-vitisnet-cli => $(command -v p4bm-vitisnet-cli || echo MISSING)"

  if ! command -v p4c-vitisnet >/dev/null 2>&1; then
    log "ERROR: p4c-vitisnet not found after sourcing settings"
    exit 2
  fi
  if ! command -v run-p4bm-vitisnet >/dev/null 2>&1; then
    log "ERROR: run-p4bm-vitisnet not found after sourcing settings"
    exit 2
  fi

  local vivroot="${TOOLS_ROOT}/Xilinx/Vivado/${TOOLVERSION}"
  local p4bm_bin="${vivroot}/bin/unwrapped/lnx64.o/p4bm-vitisnet"
  local libp4c
  libp4c="$(find "${vivroot}/data/ip/xilinx" -maxdepth 4 -type f -name 'libp4c.so' 2>/dev/null | head -n 1 || true)"

  if [[ -n "${libp4c}" ]]; then
    log "ldd check: ${libp4c}"
    ldd "${libp4c}" | grep "not found" || true
  else
    log "WARN: Could not locate libp4c.so under ${vivroot}/data/ip/xilinx"
  fi

  if [[ -x "${p4bm_bin}" ]]; then
    log "ldd check: ${p4bm_bin}"
    ldd "${p4bm_bin}" | grep "not found" || true
  else
    log "WARN: Could not locate p4bm-vitisnet binary at ${p4bm_bin}"
  fi

  log "Sanity check complete."
}

main() {
  log "Starting post-boot (TOOLVERSION=${TOOLVERSION}, REMOTEDESKTOP=${REMOTEDESKTOP})"
  require_file "$SETTINGS_ORIG"

  install_behavioral_deps
  install_openssl11_compat
  make_sanitized_settings64
  append_profile_source_once
  install_remote_desktop_if_requested
  sanity_check_tools

  log "Done running post-boot.sh."
}

main "$@"
