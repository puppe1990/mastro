//// Page metadata: canonical URL, Open Graph and Twitter tags.
////
//// A `Site` is built from the app name and `APP_URL` (`site_from`), then
//// narrowed to a request (`for_request`) so a page always has an absolute
//// URL even in development. `og:image` is made absolute against the site
//// URL, which is why `APP_URL` matters in production.

import gleam/http
import gleam/http/request
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type Site {
  Site(
    name: String,
    url: Option(String),
    description: Option(String),
    image: Option(String),
  )
}

/// Build a site from the app name and an optional absolute URL.
pub fn site_from(name: String, url: Option(String)) -> Site {
  Site(name: name, url: url, description: None, image: Some("/static/og.png"))
}

/// A site with no configured URL yet; `for_request` fills it from the host.
pub fn site(name: String) -> Site {
  site_from(name, None)
}

pub fn with_description(site: Site, description: String) -> Site {
  Site(..site, description: Some(description))
}

pub fn with_image(site: Site, image: String) -> Site {
  Site(..site, image: Some(image))
}

/// Fill in the URL from the request when the operator did not set
/// `APP_URL` (development, mostly), so canonical/OG tags are still absolute.
pub fn for_request(site: Site, req: request.Request(a)) -> Site {
  case site.url {
    Some(_) -> site
    None -> Site(..site, url: Some(request_url(req)))
  }
}

/// The absolute `og:image`, or the relative image when the site has no URL.
pub fn image_url(site: Site) -> Option(String) {
  case site.image, site.url {
    Some(image), Some(base) ->
      case string.starts_with(image, "/") {
        True -> Some(base <> image)
        False -> Some(image)
      }
    Some(image), None -> Some(image)
    None, _ -> None
  }
}

/// The `<meta>` tags for `<head>`, as Lustre elements.
pub fn head_elements(site: Site) -> List(Element(Nil)) {
  list.flatten([
    [
      meta_property("og:title", site.name),
      meta_property("og:type", "website"),
    ],
    case site.url {
      Some(url) -> [meta_property("og:url", url)]
      None -> []
    },
    case site.description {
      Some(description) -> [
        meta_property("og:description", description),
        meta_name("description", description),
      ]
      None -> []
    },
    case image_url(site) {
      Some(image) -> [
        meta_property("og:image", image),
        meta_name("twitter:image", image),
      ]
      None -> []
    },
    [
      meta_name("twitter:card", case image_url(site) {
        Some(_) -> "summary_large_image"
        None -> "summary"
      }),
      meta_name("twitter:title", site.name),
    ],
  ])
}

/// The same tags as an HTML string, for string-based layouts and tests.
pub fn preview_html(site: Site) -> String {
  site
  |> head_elements
  |> list.map(element.to_string)
  |> string.join("")
}

fn meta_property(property: String, content: String) -> Element(Nil) {
  html.meta([
    attribute.attribute("property", property),
    attribute.content(content),
  ])
}

fn meta_name(name: String, content: String) -> Element(Nil) {
  html.meta([attribute.name(name), attribute.content(content)])
}

fn request_url(req: request.Request(a)) -> String {
  let scheme = case req.scheme {
    http.Http -> "http"
    http.Https -> "https"
  }

  case request.get_header(req, "host") {
    Ok(host) if host != "" -> scheme <> "://" <> host
    _ -> scheme <> "://localhost"
  }
}
