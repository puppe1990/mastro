//// Network helpers for the dev server: LAN discovery, port picking and
//// the boot banner.
////
//// The socket work — probing a port, listing interfaces — lives in
//// `mastro_net_ffi`. This module keeps the policy (which port to take,
//// what to print) in Gleam so it can be tested without binding a port
//// the test does not own.

import gleam/int
import gleam/list
import gleam/string

/// A held TCP listener. Only tests need it: they take a port on purpose so
/// `pick_port` has something to skip.
pub type Socket

@external(erlang, "mastro_net_ffi", "port_available")
pub fn port_available(port: Int) -> Bool

@external(erlang, "mastro_net_ffi", "listen_random")
pub fn listen_random() -> Result(#(Socket, Int), Nil)

@external(erlang, "mastro_net_ffi", "close")
pub fn close(socket: Socket) -> Nil

@external(erlang, "mastro_net_ffi", "lan_addresses")
pub fn lan_addresses() -> List(String)

@external(erlang, "mastro_net_ffi", "now_ms")
pub fn now_ms() -> Int

/// The first free port at or after `preferred`, probing at most `attempts`
/// ports. When every candidate is taken, `preferred` comes back unchanged:
/// the caller reports the port it meant to use instead of a mystery number.
pub fn pick_port(preferred: Int, attempts: Int) -> Int {
  pick_from(preferred, preferred, attempts)
}

fn pick_from(port: Int, preferred: Int, attempts: Int) -> Int {
  case attempts <= 0 {
    True -> preferred
    False ->
      case port_available(port) {
        True -> port
        False -> pick_from(port + 1, preferred, attempts - 1)
      }
  }
}

/// `http://<lan-address>:<port>` for every address the LAN can reach. The
/// list is empty on a machine with no usable interface — the caller should
/// fall back to the localhost URL rather than inventing one.
pub fn lan_urls(port: Int) -> List(String) {
  urls_for(lan_addresses(), port)
}

/// The pure half of `lan_urls`: format addresses that were already read.
pub fn urls_for(addresses: List(String), port: Int) -> List(String) {
  let suffix = ":" <> int.to_string(port)
  addresses
  |> list.map(fn(address) { "http://" <> address <> suffix })
}

/// The boot banner: where the app is listening locally, and on which LAN
/// addresses a phone on the same network can reach it.
pub fn banner(app_name: String, port: Int) -> String {
  let port_string = int.to_string(port)
  let network = case lan_urls(port) {
    [] -> []
    urls -> ["  Network: " <> string.join(urls, ", ")]
  }

  let lines = [
    "",
    "  " <> app_name <> " dev server",
    "  Local:   http://localhost:" <> port_string,
    ..network
  ]

  string.join(list.append(lines, [""]), "\n")
}
