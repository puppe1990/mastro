# PWA and mobile

`mastro pwa` installs the assets an app needs to be installable on a phone
and to load `amarra.js` offline. `GET /health` tells a device on the same
network where the dev server is.

## Installing the assets

```bash
mastro pwa
mastro pwa --bump
mastro pwa --force
```

| Flag | Effect |
|------|--------|
| (none) | Writes anything missing: `amarra.js`, `manifest.webmanifest`, `sw.js`, the placeholder icons and `og.png`. Existing files are left alone. |
| `--bump` | Increments `CACHE_VERSION` in `priv/static/js/sw.js`. |
| `--force` | Resets every asset, including the brand and the cache version. |

Without `--force` your brand survives: a `manifest.webmanifest` or icon you
edited is never overwritten.

## Files

```
priv/static/
  js/amarra.js              the Amarra runtime
  js/sw.js                  service worker
  manifest.webmanifest
  icons/icon-192.png        any
  icons/icon-512.png        any
  icons/icon-512-maskable.png  maskable
  og.png                    social preview placeholder
```

The manifest separates the `any` icons (192 and 512) from the 512
`maskable` one, so Android does not crop the logo into a circle by
accident.

The service worker caches the shell and serves `/static/js/amarra.js`
**network-first**, so a local edit is never answered from the cache. In
development `mastro dev` bumps `CACHE_VERSION` on every boot when `sw.js`
exists; in production bump it yourself (or in CI) when you deploy.

The icons and `og.png` are neutral placeholders. Replace them before
launch — `mastro doctor` keeps warning until you do.

## Health check

Every app scaffolded by `mastro new` has:

```
GET /health
```

```json
{"status":"ok","lan_urls":["http://192.168.1.20:4000"]}
```

`lan_urls` comes from `net.lan_urls/1`, which reads the machine's real
interfaces. Never build it by concatenating `APP_URL` and a port: that URL
will not answer from a device on the network. When the preferred port is
busy the dev server takes the next free one and reports the resolved port
in `ctx.config.port`, so `/health` always names the URL that answers.

Point a phone at one of the `lan_urls` to test on-device, then run
`mastro doctor --mobile` to check the mobile-specific guards (flash inside
`#amarra-main`, no blocked font origins, network-first `amarra.js`, the
`#chat-messages` container).
