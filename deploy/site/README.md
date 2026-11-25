# Site hosting

The site was gitgaze.alexheffernan.dev until the app became Stoke; that host now redirects. The
`gitgaze-site` names for the directory, timer and tunnel are unchanged.

stoke.alexheffernan.dev runs on the Raspberry Pi (`alexs-pi`, user `alexh`) in `~/gitgaze-site`:

- `repo/` is a clone of this repository on `main`. nginx serves `repo/site` read-only.
- A dedicated Cloudflare tunnel (`gitgaze-site`) carries public traffic to nginx; its
  `tunnel-config.yml` and `tunnel-credentials.json` (0600) sit beside `repo/` and are not committed.
- The user timer `gitgaze-site-update.timer` runs `update.sh` every minute. It fast-forwards
  `repo/` to `origin/main`, so merged site changes are live within about a minute, and restarts
  the stack only when `deploy/site` changed. There is no build step or image registry.

```sh
cd ~/gitgaze-site
docker compose -f repo/deploy/site/compose.yaml --project-directory . up -d   # start
journalctl --user -u gitgaze-site-update.service                               # deploy log
```

`tunnel-config.yml`:

```yaml
tunnel: <tunnel id>
credentials-file: /etc/cloudflared/credentials.json
ingress:
  - hostname: stoke.alexheffernan.dev
    service: http://web:80
  - hostname: gitgaze.alexheffernan.dev   # nginx redirects it to stoke.alexheffernan.dev
    service: http://web:80
  - service: http_status:404
```
