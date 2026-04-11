# alfredo · pi kiosk

Web dashboard running on pihub.local, displayed on a ROADOM 7" 1024×600 touchscreen via Chromium kiosk mode.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Main kiosk dashboard UI |
| `settings.html` | Settings/layout editor — open from Mac at `http://pihub.local:8430/settings.html` |
| `serve.py` | Python HTTP server on :8430, proxies health/iCloud/tailscale/presence checks |

## Deploy to Pi

```bash
# From Mac project root, after pulling latest
rsync -av pi-kiosk/ pihub.local:~/alfredo-kiosk/
ssh pihub.local 'sudo systemctl restart alfredo-kiosk-web'
```

## Reload kiosk after deploy

```bash
ssh pihub.local 'curl -s -X POST http://localhost:8430/reload-kiosk'
```

## URLs

- Kiosk: `http://pihub.local:8430/`
- Settings: `http://pihub.local:8430/settings.html`
