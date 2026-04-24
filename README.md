# webstack-setup

Automated PHP + PHP-FPM + nginx setup scripts for Arch Linux, built for local development.

Each script covers a distinct concern and can be run independently, as long as the recommended order is followed.

---

## What's included

| Script            | What it does                                                                                                                                       |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `setup-php.sh`    | Installs PHP and extensions, activates them in `php.ini` and `conf.d`, configures OPcache, starts PHP-FPM                                          |
| `setup-fpm.sh`    | Calculates and applies PHP-FPM pool parameters based on available hardware                                                                         |
| `setup-nginx.sh`  | Installs nginx, writes an optimized `nginx.conf`, creates the virtual host directory structure, and provides a Laravel-ready virtual host template |
| `create-vhost.sh` | Interactively creates and activates a new nginx virtual host for a Laravel project                                                                 |

---

## Requirements

- Arch Linux
- `sudo` access
- Internet connection (scripts use `pacman` to install packages)

---

## Usage

Run the scripts in order. Each one is idempotent — safe to run multiple times.

```bash
sudo bash setup-php.sh
sudo bash setup-fpm.sh
sudo bash setup-nginx.sh
```

---

## What each script does

### setup-php.sh

Installs the following packages via `pacman`:

- `php`, `php-fpm`
- `php-gd`, `php-intl`, `php-pgsql`, `php-sqlite`, `php-xsl`
- `php-redis`, `php-igbinary`

After installation, it:

- Uncomments the required extensions in `/etc/php/php.ini`
- Activates extensions in `/etc/php/conf.d/` (redis, igbinary)
- Writes a tuned `opcache.ini` to `/etc/php/conf.d/`, with `memory_consumption` scaled to available RAM
- Adjusts key `php.ini` settings: `memory_limit`, `upload_max_filesize`, `post_max_size`, `max_execution_time`, `date.timezone`
- Enables and starts the `php-fpm` systemd service

**OPcache memory allocation by RAM:**

| Total RAM | opcache.memory_consumption |
| --------- | -------------------------- |
| ≥ 16 GB   | 256 MB                     |
| ≥ 8 GB    | 128 MB                     |
| < 8 GB    | 64 MB                      |

> **Note:** OPcache is configured with `validate_timestamps=1` for local development — PHP checks whether files have changed on each request. In production, set `validate_timestamps=0` for maximum performance.

---

### setup-fpm.sh

Calculates PHP-FPM pool parameters based on detected hardware and prompts for confirmation before applying.

**Assumptions:**

- Average PHP-FPM worker memory (Laravel): ~50 MB
- 20% of total RAM is reserved for the OS and other processes

**Calculated parameters:**

| Parameter              | Formula                                                  |
| ---------------------- | -------------------------------------------------------- |
| `pm.max_children`      | `(RAM × 80%) ÷ 50MB`                                     |
| `pm.start_servers`     | `max_children ÷ 4`                                       |
| `pm.min_spare_servers` | `max_children ÷ 4`                                       |
| `pm.max_spare_servers` | `max_children ÷ 2`                                       |
| `pm.max_requests`      | `500` (fixed — recycles workers to prevent memory leaks) |

A timestamped backup of `www.conf` is created before any change is applied.

---

### setup-nginx.sh

Installs nginx and writes a new `/etc/nginx/nginx.conf` with:

- `worker_processes` set to the number of detected CPU cores
- `worker_connections 1024`
- Gzip compression enabled for common text and asset types
- `client_max_body_size 64M` (matches `upload_max_filesize` in `php.ini`)
- `include /etc/nginx/sites-enabled/*.conf` for virtual host management

Creates the `sites-available` and `sites-enabled` directories and writes a documented Laravel virtual host template to `/etc/nginx/sites-available/laravel.conf.example`.

**To activate a virtual host:**

```bash
# 1. Copy the template
cp /etc/nginx/sites-available/laravel.conf.example \
   /etc/nginx/sites-available/myproject.conf

# 2. Edit server_name and root in the copied file

# 3. Add the domain to /etc/hosts (if using a .local domain)
echo "127.0.0.1  myproject.local" | sudo tee -a /etc/hosts

# 4. Enable the virtual host
ln -s /etc/nginx/sites-available/myproject.conf \
      /etc/nginx/sites-enabled/

# 5. Validate and reload
nginx -t && systemctl reload nginx
```

---

### create-vhost.sh

Interactively creates a new nginx virtual host for a Laravel project. Run once per project, any time after `setup-nginx.sh`.

```bash
sudo bash create-vhost.sh
```

The script asks three questions, displaying a short explanation and an example for each:

| Question     | What it expects                                                                            |
| ------------ | ------------------------------------------------------------------------------------------ |
| Project name | Lowercase letters, numbers and hyphens. Used for the config filename and nginx logs.       |
| Local domain | The domain nginx will respond to (e.g. `alma.local`). Added to `/etc/hosts` automatically. |
| Root path    | Absolute path to the Laravel project's `public/` directory.                                |

After confirmation, it:

- Writes the virtual host config to `/etc/nginx/sites-available/<project>.conf`
- Adds the domain to `/etc/hosts` (skips if already present)
- Creates a symlink in `/etc/nginx/sites-enabled/`
- Runs `nginx -t` to validate the configuration
- Reloads nginx

All virtual hosts are created on port 80.

---

## PHP-FPM socket path

The Laravel virtual host template uses the Arch Linux default socket:

```
unix:/run/php-fpm/php-fpm.sock
```

If your setup uses a different socket or a TCP port, update the `fastcgi_pass` directive in your virtual host configuration accordingly.

---

## Other distributions

These scripts are written specifically for Arch Linux. Package names, file paths (`/etc/php/`, `/etc/nginx/`), and the user nginx runs as (`http`) differ across distributions. Support for other distros may be added in the future.

---

## Related

- [pg-setup](https://github.com/nicholasleite/pg-setup) — PostgreSQL installation and project setup scripts for Arch Linux
