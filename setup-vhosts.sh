#!/usr/bin/env bash

# create-vhost.sh — Interactive Laravel virtual host creation for nginx on Arch Linux
# Part of webstack-setup
#
# What this script does:
#   1. Asks for project name, local domain and public root path
#   2. Validates each input before proceeding
#   3. Displays a summary and asks for confirmation
#   4. Creates the virtual host config in sites-available
#   5. Adds the domain to /etc/hosts
#   6. Creates a symlink in sites-enabled
#   7. Validates the nginx config and reloads the service
#
# Run: sudo bash create-vhost.sh
# Safe to run multiple times for different projects.

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
label()   { echo -e "\n${BOLD}${CYAN}$1${NC}"; }
hint()    { echo -e "${YELLOW}$1${NC}"; }

# ── Root check ────────────────────────────────────────────────────────────────

[[ $EUID -ne 0 ]] && error "Run this script with sudo: sudo bash create-vhost.sh"

# ── Prerequisites ─────────────────────────────────────────────────────────────

[[ ! -d /etc/nginx/sites-available ]] && \
    error "sites-available not found. Run setup-nginx.sh first."

[[ ! -d /etc/nginx/sites-enabled ]] && \
    error "sites-enabled not found. Run setup-nginx.sh first."

! systemctl is-active --quiet nginx && \
    error "nginx is not running. Run setup-nginx.sh first."

# ── Header ────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}webstack-setup — create-vhost.sh${NC}"
echo -e "Creates a new nginx virtual host for a Laravel project."
echo -e "Answer each question and confirm before anything is written."
echo ""

# ── Question 1: Project name ──────────────────────────────────────────────────

label "1. Project name"
hint "Used to name the config file and the nginx log files."
hint "Use lowercase letters, numbers and hyphens only."
hint "Example: alma, my-api, personal-blog"
echo ""

while true; do
    read -rp "Project name: " PROJECT_NAME

    if [[ -z "${PROJECT_NAME}" ]]; then
        warn "Project name cannot be empty. Try again."
        continue
    fi

    if [[ ! "${PROJECT_NAME}" =~ ^[a-z0-9-]+$ ]]; then
        warn "Only lowercase letters, numbers and hyphens are allowed. Try again."
        continue
    fi

    CONF_FILE="/etc/nginx/sites-available/${PROJECT_NAME}.conf"
    if [[ -f "${CONF_FILE}" ]]; then
        warn "A virtual host named '${PROJECT_NAME}' already exists: ${CONF_FILE}"
        warn "Choose a different name or remove the existing file first."
        continue
    fi

    break
done

# ── Question 2: Local domain ──────────────────────────────────────────────────

label "2. Local domain"
hint "The domain nginx will respond to. Will be added to /etc/hosts automatically."
hint "The .local suffix is recommended to avoid conflicts with real domains."
hint "Example: alma.local, my-api.local, personal-blog.local"
echo ""

while true; do
    read -rp "Local domain: " DOMAIN

    if [[ -z "${DOMAIN}" ]]; then
        warn "Domain cannot be empty. Try again."
        continue
    fi

    if [[ ! "${DOMAIN}" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        warn "Domain contains invalid characters. Try again."
        continue
    fi

    if grep -qE "^\s*127\.0\.0\.1\s+${DOMAIN}\s*$" /etc/hosts; then
        warn "${DOMAIN} is already in /etc/hosts. It will not be added again."
        DOMAIN_EXISTS=true
    else
        DOMAIN_EXISTS=false
    fi

    break
done

# ── Question 3: Public root path ──────────────────────────────────────────────

label "3. Public root path"
hint "Absolute path to the Laravel project's public/ directory."
hint "nginx will serve files from this directory."
hint "Example: /home/nicholas/projects/alma/backend/public"
echo ""

while true; do
    read -rp "Root path: " ROOT_PATH

    if [[ -z "${ROOT_PATH}" ]]; then
        warn "Root path cannot be empty. Try again."
        continue
    fi

    if [[ ! "${ROOT_PATH}" = /* ]]; then
        warn "Path must be absolute (start with /). Try again."
        continue
    fi

    if [[ ! -d "${ROOT_PATH}" ]]; then
        warn "Directory not found: ${ROOT_PATH}"
        read -rp "  Proceed anyway? [y/N] " proceed_anyway
        [[ "${proceed_anyway}" != "y" && "${proceed_anyway}" != "Y" ]] && continue
    fi

    break
done

# ── Summary and confirmation ───────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Summary${NC}"
echo "  Project name : ${PROJECT_NAME}"
echo "  Domain       : ${DOMAIN}"
echo "  Root path    : ${ROOT_PATH}"
echo "  Port         : 80"
echo "  Config file  : /etc/nginx/sites-available/${PROJECT_NAME}.conf"
echo "  Symlink      : /etc/nginx/sites-enabled/${PROJECT_NAME}.conf"

if [[ "${DOMAIN_EXISTS}" == "false" ]]; then
    echo "  /etc/hosts   : 127.0.0.1  ${DOMAIN}  (will be added)"
else
    echo "  /etc/hosts   : ${DOMAIN} already present — skipping"
fi

echo ""
read -rp "Create this virtual host? [y/N] " confirm
echo ""

[[ "${confirm}" != "y" && "${confirm}" != "Y" ]] && {
    warn "Aborted. No changes made."
    exit 0
}

# ── Write virtual host config ─────────────────────────────────────────────────

info "Writing ${CONF_FILE}..."

cat > "${CONF_FILE}" << EOF
# Virtual host: ${PROJECT_NAME}
# Generated by webstack-setup/create-vhost.sh

server {
    listen 80;
    server_name ${DOMAIN};

    root ${ROOT_PATH};
    index index.php;

    # ── Security headers ──────────────────────────────────────────────────────

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # ── Laravel routing ───────────────────────────────────────────────────────

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # ── PHP-FPM ───────────────────────────────────────────────────────────────

    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;

        fastcgi_read_timeout 60;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }

    # ── Block hidden files ────────────────────────────────────────────────────

    location ~ /\.(?!well-known).* {
        deny all;
    }

    # ── Static assets ─────────────────────────────────────────────────────────

    location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff|woff2|ttf|eot|webp|avif)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # ── Logs ──────────────────────────────────────────────────────────────────

    error_log  /var/log/nginx/${PROJECT_NAME}_error.log;
    access_log /var/log/nginx/${PROJECT_NAME}_access.log;
}
EOF

success "Config written: ${CONF_FILE}"

# ── Add domain to /etc/hosts ──────────────────────────────────────────────────

if [[ "${DOMAIN_EXISTS}" == "false" ]]; then
    info "Adding ${DOMAIN} to /etc/hosts..."
    echo "127.0.0.1  ${DOMAIN}" >> /etc/hosts
    success "${DOMAIN} added to /etc/hosts"
else
    warn "${DOMAIN} already in /etc/hosts — skipping"
fi

# ── Create symlink in sites-enabled ──────────────────────────────────────────

SYMLINK="/etc/nginx/sites-enabled/${PROJECT_NAME}.conf"

if [[ -L "${SYMLINK}" ]]; then
    warn "Symlink already exists: ${SYMLINK} — skipping"
else
    info "Creating symlink in sites-enabled..."
    ln -s "${CONF_FILE}" "${SYMLINK}"
    success "Symlink created: ${SYMLINK}"
fi

# ── Validate and reload nginx ─────────────────────────────────────────────────

info "Validating nginx configuration..."
nginx -t || error "nginx config validation failed. Check the output above."

info "Reloading nginx..."
systemctl reload nginx
success "nginx reloaded."

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}─────────────────────────────────────────────────────${NC}"
success "Virtual host '${PROJECT_NAME}' is active."
echo ""
echo "  URL    : http://${DOMAIN}"
echo "  Config : ${CONF_FILE}"
echo "  Logs   : /var/log/nginx/${PROJECT_NAME}_*.log"
echo -e "${GREEN}─────────────────────────────────────────────────────${NC}"
