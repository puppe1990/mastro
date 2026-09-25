# Security Headers and the Production Gate

Two things run before your handlers see a request: the hardening headers
every response leaves with, and the boot gate that stops a production app
that is missing a value it cannot invent.

## Headers

`mastro/security` sets them right after crash recovery, so static files
leave with the same headers as pages:

```gleam
fn middleware(ctx: Context, req: Request, next: fn(Request) -> Response) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- dev_error.rescue(req)
  use <- security.headers(security.defaults(config.is_production(ctx.config)))
  // ...
}
```

| Header | Value |
|--------|-------|
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `SAMEORIGIN` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | `camera=(), geolocation=(), microphone=()` |
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains` — production only |
| `Content-Security-Policy` | see below |

A header the handler already set is left alone, so a route can override a
default on purpose. `security.with_csp(options, csp)` replaces the whole
policy for an app that loads a CDN:

```gleam
let options =
  security.defaults(production)
  |> security.with_csp("default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.example")
```

### Why `unsafe-inline` is still there

The theme FOUC snippet and the Drive boot are inline scripts, so the
default policy keeps `script-src 'self' 'unsafe-inline'`. Escaping stays
the primary defence. A per-request nonce or SRI hashes are the roadmap to
dropping it — the default is a starting point, not the ceiling.

## Production gate

`config.load()` reads the environment; `config.validate/1` refuses to boot
a production app that is missing `APP_URL`, or `ADMIN_TOKEN` when the app
serves bearer admin routes:

```gleam
pub fn main() {
  wisp.configure_logger()
  let cfg = config.load()

  case config.validate(cfg) {
    Ok(_) -> Nil
    Error(errors) -> panic as security.describe(errors)
  }
  // ...
}
```

| Variable | Required | Why |
|----------|----------|-----|
| `APP_ENV` | no | `prod` turns on HSTS and the gate |
| `APP_URL` | in production | absolute URLs (og:image, links in e-mail) cannot be guessed |
| `ADMIN_TOKEN` | in production, with admin routes | bearer token for `AdminAuth` routes |
| `TRUSTED_PROXIES` | no | comma-separated addresses allowed to set `X-Forwarded-For` |

Development and test boot with none of them set. Flip `admin_routes` to
`True` in `config.validate/1` once the app serves admin routes.

## Client address

`security.client_ip/3` returns the address a request should be attributed
to. `X-Forwarded-For` is only read when the peer is a listed proxy, or when
the list contains `"*"` for a platform that always sits behind its own
edge — otherwise a client could spoof the header:

```gleam
security.client_ip(req, peer_ip, cfg.trusted_proxies)
// trusted peer: X-Forwarded-For "203.0.113.7, 10.0.0.1" -> "203.0.113.7"
// anyone else:  the peer address, or "unknown"
```

`x-real-ip` is the fallback when a proxy sets it instead of the list.
