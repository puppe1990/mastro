//// PWA assets: the web manifest, the service worker and its cache version.
////
//// The strings are pure so tests can assert the manifest contract (icons
//// split between `any` and `maskable`) and the `--bump` behaviour without
//// touching the filesystem.

import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

/// The line `--bump` rewrites.
pub const cache_version_prefix = "CACHE_VERSION = "

/// A web manifest with 192/512 `any` icons and a 512 `maskable` one.
pub fn manifest(app_name: String) -> String {
  json.object([
    #("name", json.string(app_name)),
    #("short_name", json.string(app_name)),
    #("start_url", json.string("/")),
    #("display", json.string("standalone")),
    #("background_color", json.string("#0f172a")),
    #("theme_color", json.string("#0f172a")),
    #(
      "icons",
      json.array(
        [
          icon("/static/icons/icon-192.png", "192x192", "any"),
          icon("/static/icons/icon-512.png", "512x512", "any"),
          icon("/static/icons/icon-512-maskable.png", "512x512", "maskable"),
        ],
        fn(icon) { icon },
      ),
    ),
  ])
  |> json.to_string
}

fn icon(src: String, sizes: String, purpose: String) -> json.Json {
  json.object([
    #("src", json.string(src)),
    #("sizes", json.string(sizes)),
    #("type", json.string("image/png")),
    #("purpose", json.string(purpose)),
  ])
}

/// The service worker: a shell cache, and `amarra.js` served network-first
/// so a dev edit is never answered from the cache.
pub fn service_worker(app_name: String, version: Int) -> String {
  "const CACHE_VERSION = "
  <> int.to_string(version)
  <> ";\n"
  <> "const CACHE_NAME = \""
  <> app_name
  <> "-v\" + CACHE_VERSION;\n"
  <> "const SHELL = [\"/\", \"/static/css/app.css\", \"/static/js/amarra.js\"];\n"
  <> "
self.addEventListener(\"install\", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener(\"activate\", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key)),
      ),
    ),
  );
  self.clients.claim();
});

self.addEventListener(\"fetch\", (event) => {
  const request = event.request;
  if (request.method !== \"GET\") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // amarra.js is network-first so local edits are never cached.
  if (url.pathname === \"/static/js/amarra.js\") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          return response;
        })
        .catch(() => caches.match(request)),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request)),
  );
});
"
}

/// The `CACHE_VERSION` currently in a service worker, if any.
pub fn cache_version(content: String) -> Result(Int, Nil) {
  case string.split(content, cache_version_prefix) {
    [_, rest] ->
      rest
      |> string.to_graphemes
      |> list.take_while(is_digit)
      |> string.join("")
      |> int.parse
    _ -> Error(Nil)
  }
}

/// Rewrite `CACHE_VERSION = N` to `N + 1`.
pub fn bump_cache_version(content: String) -> Result(String, Nil) {
  case cache_version(content) {
    Ok(version) ->
      Ok(string.replace(
        content,
        cache_version_prefix <> int.to_string(version),
        cache_version_prefix <> int.to_string(version + 1),
      ))
    Error(_) -> Error(Nil)
  }
}

fn is_digit(grapheme: String) -> Bool {
  int.parse(grapheme) |> result.is_ok
}
