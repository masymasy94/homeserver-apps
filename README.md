# Docker Apps Infrastructure

Deploy and manage isolated Docker Compose applications on the homeserver. Each app gets full isolation — no port conflicts, no shared infrastructure.

## Quick Start

```bash
# 1. Initial setup (creates network, installs yq, connects NPM)
./infrastructure/setup-network.sh

# 2. Start infrastructure services (registry)
docker compose -f infrastructure/docker-compose.yml up -d registry

# 3. Deploy an app
./scripts/deploy.sh https://github.com/user/myapp.git myapp

# 4. Add DNS on client devices (/etc/hosts)
# <SERVER_IP>  myapp.local
```

## Commands

| Command | Description |
|---------|-------------|
| `./scripts/deploy.sh <repo-url> <name>` | Deploy a new app |
| `./scripts/update.sh <name>` | Pull latest + rebuild |
| `./scripts/stop.sh <name>` | Stop app containers |
| `./scripts/start.sh <name>` | Start stopped app |
| `./scripts/remove.sh <name>` | Full cleanup (containers, volumes, NPM, registry) |
| `./scripts/status.sh` | Show all apps with status |
| `./scripts/logs.sh <name> [service] [-f]` | View app logs |

## How It Works

1. **deploy.sh** clones the repo into `deployments/<name>/`
2. Auto-detects the frontend service (traefik, nginx, web, etc.)
3. Generates `docker-compose.deploy.yml` — strips all ports, adds proxy network
4. Starts containers with `docker compose -p <name>`
5. Registers `<name>.local` in Nginx Proxy Manager

Traffic flows: **Client** → **NPM** (port 80) → **apps-proxy network** → **frontend container**

## Frontend Auto-Detection

deploy.sh scans the compose file to find the entry point:

1. Service with port 80 or 443 exposed
2. Service named: `traefik`, `nginx`, `gateway`, `frontend`, `web`, `proxy`, `caddy`, `httpd`, `app`
3. First service in the file

Override by placing `.apps-deploy.yml` in your repo root:

```yaml
frontend_service: traefik
frontend_port: 80
```

## CI/CD with GitHub Actions

1. Configure the self-hosted runner (set `RUNNER_TOKEN` and `REPO_URL` in infrastructure `.env`)
2. Start: `docker compose -f infrastructure/docker-compose.yml --profile runner up -d`
3. Copy `templates/github-workflow.yml` to your repo at `.github/workflows/deploy.yml`

On push to `main`, the runner calls `update.sh` to pull and rebuild automatically.

## Network Architecture

### WiFi Mode (default)
- Apps run as isolated Docker Compose projects
- No ports exposed to host — zero conflicts
- Shared `apps-proxy` bridge network connects NPM to each app's frontend
- Access via NPM domain names: `http://myapp.local`

### IP Alias Mode
- Each app gets a dedicated LAN IP (e.g. 192.168.x.200+)
- Set `IP_ALIAS_ENABLED=true` in `config/settings.conf`
- IPs are assigned via NetworkManager on the WiFi interface

### Macvlan Mode (requires Ethernet)
- Each app gets a dedicated LAN IP via macvlan
- Set `NETWORK_MODE=macvlan` in `config/settings.conf`
- Re-run `./infrastructure/setup-network.sh`

## DNS Setup

Add entries to `/etc/hosts` on each client device:

```
<SERVER_IP>  myapp.local
<SERVER_IP>  another-app.local
```

Or configure your router to resolve `*.local` → your server IP.

## Configuration

- `config/settings.conf` — NPM API credentials, network mode, server IP
- `config/apps.conf` — App registry (managed by scripts, don't edit manually)
- `config/secrets/<app-name>/` — Secret files copied into app directory on deploy

## Troubleshooting

**App not accessible via domain:**
- Check NPM is running: `docker ps | grep nginx-proxy-manager`
- Check NPM is on apps-proxy: `docker network inspect apps-proxy`
- Check app frontend is on apps-proxy: `docker inspect <app>-<frontend>-1 --format='{{json .NetworkSettings.Networks}}'`
- Verify DNS/hosts entry on client

**deploy.sh fails "No docker-compose.yml found":**
- Ensure the repo has `docker-compose.yml` or `compose.yml` at the root

**NPM registration fails:**
- Update `NPM_API_EMAIL` and `NPM_API_PASSWORD` in `config/settings.conf`
- Default NPM credentials: `admin@example.com` / `changeme`
- Register manually at `http://<SERVER_IP>:81`

**Containers start but app doesn't work:**
- Check logs: `./scripts/logs.sh <name> -f`
- Verify `.env` file has correct values
- Check internal networking: `docker compose -p <name> exec <service> ping <other-service>`
