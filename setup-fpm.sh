#!/usr/bin/env bash

# setup-fpm.sh — PHP-FPM pool fine-tuning for Arch Linux
# Part of webstack-setup
#
# What this script does:
#   1. Detects available RAM and CPU cores
#   2. Calculates optimal PHP-FPM pool parameters
#   3. Displays the calculated values and asks for confirmation
#   4. Applies the settings to /etc/php/php-fpm.d/www.conf
#   5. Restarts php-fpm
#
# Assumptions:
#   - Average PHP-FPM process memory (Laravel): ~50MB
#   - 20% of RAM is reserved for the OS and other processes
#
# Run: sudo bash setup-fpm.sh
# Idempotent: safe to run multiple times. Creates a backup before applying.

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# ── Root check ────────────────────────────────────────────────────────────────

[[ $EUID -ne 0 ]] && error "Run this script with sudo: sudo bash setup-fpm.sh"

# ── Prerequisites ─────────────────────────────────────────────────────────────

POOL_CONF="/etc/php/php-fpm.d/www.conf"

[[ ! -f "${POOL_CONF}" ]] && error "Pool config not found: ${POOL_CONF}
  Make sure setup-php.sh has been run first."

! systemctl is-active --quiet php-fpm &&
    error "php-fpm is not running. Run setup-php.sh first."

# ── Hardware detection ────────────────────────────────────────────────────────

TOTAL_RAM_MB=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
CPU_CORES=$(nproc)

# ── Parameter calculation ─────────────────────────────────────────────────────
#
# pm.max_children
#   How many PHP-FPM worker processes can run simultaneously.
#   Formula: (80% of total RAM) / average process size
#
# pm.start_servers
#   How many workers to spawn when php-fpm starts.
#   Formula: max_children / 4
#
# pm.min_spare_servers
#   Minimum idle workers kept alive waiting for requests.
#   Formula: max_children / 4
#
# pm.max_spare_servers
#   Maximum idle workers before php-fpm starts killing them.
#   Formula: max_children / 2
#
# pm.max_requests
#   How many requests a worker handles before being recycled.
#   Prevents slow memory leaks from accumulating indefinitely.

AVG_PROCESS_MB=50
AVAILABLE_MB=$((TOTAL_RAM_MB * 80 / 100))
MAX_CHILDREN=$((AVAILABLE_MB / AVG_PROCESS_MB))

# Clamp to reasonable bounds for a local dev machine
[[ ${MAX_CHILDREN} -lt 4 ]] && MAX_CHILDREN=4
[[ ${MAX_CHILDREN} -gt 200 ]] && MAX_CHILDREN=200

START_SERVERS=$((MAX_CHILDREN / 4))
[[ ${START_SERVERS} -lt 2 ]] && START_SERVERS=2

MIN_SPARE=$((MAX_CHILDREN / 4))
[[ ${MIN_SPARE} -lt 2 ]] && MIN_SPARE=2

MAX_SPARE=$((MAX_CHILDREN / 2))
[[ ${MAX_SPARE} -lt 4 ]] && MAX_SPARE=4

MAX_REQUESTS=500

# ── Display and confirm ───────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}Hardware detected:${NC}"
echo "  Total RAM : ${TOTAL_RAM_MB} MB"
echo "  CPU cores : ${CPU_CORES}"
echo "  Available : ~${AVAILABLE_MB} MB (80% of total RAM)"
echo ""
echo -e "${BLUE}Calculated PHP-FPM pool parameters:${NC}"
echo "  pm                   = dynamic"
echo "  pm.max_children      = ${MAX_CHILDREN}  (${AVAILABLE_MB}MB / ${AVG_PROCESS_MB}MB per process)"
echo "  pm.start_servers     = ${START_SERVERS}  (max_children / 4)"
echo "  pm.min_spare_servers = ${MIN_SPARE}  (max_children / 4)"
echo "  pm.max_spare_servers = ${MAX_SPARE}  (max_children / 2)"
echo "  pm.max_requests      = ${MAX_REQUESTS}"
echo ""

read -rp "Apply these settings to ${POOL_CONF}? [y/N] " confirm
echo ""

[[ "${confirm}" != "y" && "${confirm}" != "Y" ]] && {
    warn "Aborted. No changes made."
    exit 0
}

# ── Backup ────────────────────────────────────────────────────────────────────

BACKUP="${POOL_CONF}.bak.$(date +%Y%m%d%H%M%S)"
cp "${POOL_CONF}" "${BACKUP}"
success "Backup saved: ${BACKUP}"

# ── Apply settings ────────────────────────────────────────────────────────────

info "Applying pool settings..."

# Replaces commented or active key = value pairs.
# Falls back to appending if the key is not found in the file.
set_pool() {
    local key="$1"
    local value="$2"

    if grep -qE "^;?\s*${key}\s*=" "${POOL_CONF}"; then
        sed -i "s|^;*\s*${key}\s*=.*|${key} = ${value}|" "${POOL_CONF}"
    else
        echo "${key} = ${value}" >>"${POOL_CONF}"
    fi

    success "  ${key} = ${value}"
}

set_pool "pm" "dynamic"
set_pool "pm.max_children" "${MAX_CHILDREN}"
set_pool "pm.start_servers" "${START_SERVERS}"
set_pool "pm.min_spare_servers" "${MIN_SPARE}"
set_pool "pm.max_spare_servers" "${MAX_SPARE}"
set_pool "pm.max_requests" "${MAX_REQUESTS}"

echo ""

# ── Restart php-fpm ───────────────────────────────────────────────────────────

info "Restarting php-fpm..."
systemctl restart php-fpm
success "php-fpm restarted."

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}─────────────────────────────────────────────────────${NC}"
success "PHP-FPM fine-tuning complete."
echo ""
echo "  Pool config : ${POOL_CONF}"
echo "  Backup      : ${BACKUP}"
echo ""
echo -e "${YELLOW}Next step: sudo bash setup-nginx.sh${NC}"
echo -e "${GREEN}─────────────────────────────────────────────────────${NC}"
