//// `GET /health`: a small JSON body a phone (or a load balancer) can use
//// to find the dev server on the LAN.
////
//// `lan_urls` comes straight from the machine's interfaces — never
//// concatenate `APP_URL` and a port, which produces a URL that does not
//// answer from a device on the network.

import gleam/json
import mastro/net
import wisp.{type Response}

pub fn json(port: Int) -> String {
  json.object([
    #("status", json.string("ok")),
    #("lan_urls", json.array(net.lan_urls(port), json.string)),
  ])
  |> json.to_string
}

pub fn respond(port: Int) -> Response {
  wisp.json_response(json(port), 200)
}
