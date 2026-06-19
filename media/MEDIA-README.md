# mediastack

Self-hosted media server on Ubuntu / Proxmox.  
**Services:** Immich (photos) · Jellyfin (video/music) · *ARR suite (ready to enable)

---

## Quick Start

```bash
# 1. Run bootstrap.sh to install all required services
sudo bash bootstrap.sh

# 2. Setup Tailscale by connecting the VM to your Tailnet
sudo tailscale up

# 3. Edit .env — set your password and timezone at minimum
vi ~/mediastack/.env

# 4. Run setup (takes ~5 min first time — pulls Docker images)
cd ~/mediastack
vi bash setup.sh
```

---

## Directory Layout

After setup, everything lives under `/opt/mediastack` (configurable via `MEDIASTACK_ROOT` in `.env`):

```
/opt/mediastack/
├── immich/
│   ├── library/       ← photo/video uploads
│   ├── data/          ← ML model cache
│   └── db/            ← Postgres data
├── jellyfin/
│   ├── config/        ← Jellyfin settings
│   └── cache/         ← transcoding cache
└── media/
    ├── movies/        ← your movie files
    ├── tvshows/       ← your TV files
    └── music/         ← your music files
```

> **Tip:** If your media lives on a separate disk or NFS share, just update the `MEDIA_*` paths in `.env` to point there before running setup.

---

## Services & Ports

| Service      | URL                          | Default Port |
|--------------|------------------------------|--------------|
| Immich       | `http://YOUR_VM_IP:2283`     | 2283         |
| Jellyfin     | `http://YOUR_VM_IP:8096`     | 8096         |

---

## First-Run Setup

### Immich
1. Open `http://YOUR_VM_IP:2283`
2. Create your admin account
3. Install the mobile app and point it at your server URL

### Jellyfin
1. Open `http://YOUR_VM_IP:8096`
2. Complete the setup wizard
3. Add libraries pointing to:
   - Movies  → `/media/movies`
   - TV Shows → `/media/tvshows`
   - Music   → `/media/music`

---

## Adding the *ARR Suite

When you're ready for automated downloads, uncomment the relevant services in `docker-compose.yml` and their corresponding vars in `.env`.

**Recommended order:**
1. **Prowlarr** — set up your indexers here first
2. **Radarr** — add Prowlarr as an indexer, configure quality profiles
3. **Sonarr** — same as Radarr but for TV
4. **qBittorrent** — add as the download client in Radarr & Sonarr

> **Note:** When the *ARR suite is active, remove `:ro` from Jellyfin's movie/tvshow volume mounts — Radarr/Sonarr need write access to move completed downloads.

Then restart:
```bash
cd ~/mediastack
docker compose --env-file .env up -d
```

---

## Useful Commands

```bash
# View running containers
docker compose ps

# Live logs (all services)
docker compose logs -f

# Logs for one service
docker compose logs -f jellyfin

# Stop everything
docker compose down

# Update all images
docker compose pull && docker compose up -d

# Restart a single service
docker compose restart immich-server
```

---

## Hardware Transcoding (Optional)

Edit `docker-compose.yml` and uncomment the relevant block under the `jellyfin` service:

- **Intel iGPU (Quick Sync):** uncomment the `devices` block
- **NVIDIA GPU:** uncomment the `runtime: nvidia` block and install the NVIDIA Container Toolkit first

---

## Updating

```bash
cd ~/mediastack
docker compose pull
docker compose up -d
```

Immich in particular releases frequently — check their [GitHub releases](https://github.com/immich-app/immich/releases) for breaking changes before updating.

---

## Backups

At minimum, back up:
- `~/mediastack/.env` — your config
- `/opt/mediastack/immich/db/` — Postgres database (stop the DB container first)
- `/opt/mediastack/jellyfin/config/` — Jellyfin settings
- `/opt/mediastack/immich/library/` — your photos (if not backed up elsewhere)

Immich also has a built-in backup job for its database — enable it in **Administration → Jobs**.
