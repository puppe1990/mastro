import gleam/string
import gleeunit/should
import mastro/net

pub fn pick_port_keeps_the_preferred_when_free_test() {
  let assert Ok(#(socket, port)) = net.listen_random()
  net.close(socket)

  // The port we just released should be free again, so it is kept.
  net.pick_port(port, 5) |> should.equal(port)
}

pub fn pick_port_skips_a_busy_port_test() {
  let assert Ok(#(socket, port)) = net.listen_random()
  net.port_available(port) |> should.be_false

  let picked = net.pick_port(port, 20)

  // Release before asserting availability so a failure cannot leak a socket.
  net.close(socket)

  should.not_equal(picked, port)
  net.port_available(picked) |> should.be_true
}

pub fn pick_port_falls_back_to_preferred_when_exhausted_test() {
  let assert Ok(#(socket, port)) = net.listen_random()

  // Zero attempts never probes, and reports the port the caller meant.
  net.pick_port(port, 0) |> should.equal(port)
  net.pick_port(port, -1) |> should.equal(port)

  net.close(socket)
}

pub fn urls_for_formats_every_address_test() {
  net.urls_for(["192.168.0.10", "10.0.0.4"], 4000)
  |> should.equal(["http://192.168.0.10:4000", "http://10.0.0.4:4000"])
}

pub fn urls_for_is_empty_without_addresses_test() {
  net.urls_for([], 4000) |> should.equal([])
}

pub fn banner_names_the_app_and_the_local_url_test() {
  let banner = net.banner("my_app", 4321)

  banner |> string.contains("my_app dev server") |> should.be_true
  banner |> string.contains("http://localhost:4321") |> should.be_true
}

pub fn now_ms_is_monotonic_test() {
  let first = net.now_ms()
  let second = net.now_ms()
  { second >= first } |> should.be_true
}
