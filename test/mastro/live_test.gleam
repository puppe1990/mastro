import gleam/erlang/process
import gleam/string
import gleeunit/should
import lustre/element
import mastro/live
import mastro/stream

fn hub(max_pending: Int) -> live.Hub {
  let assert Ok(hub) = live.start(max_pending: max_pending)
  hub
}

pub fn join_broadcast_test() {
  let hub = hub(10)
  let a = process.new_subject()
  let b = process.new_subject()
  live.register(hub, "chat", a)
  live.register(hub, "chat", b)

  live.broadcast(hub, "chat", live.patch("messages", "<p>hi</p>"))

  let assert Ok(ma) = process.receive(a, 100)
  let assert Ok(mb) = process.receive(b, 100)
  should.equal(ma, live.patch("messages", "<p>hi</p>"))
  should.equal(mb, ma)
}

pub fn broadcast_only_reaches_view_test() {
  let hub = hub(10)
  let chat = process.new_subject()
  let other = process.new_subject()
  live.register(hub, "chat", chat)
  live.register(hub, "dashboard", other)

  live.broadcast(hub, "chat", live.patch("messages", "x"))

  let assert Ok(_) = process.receive(chat, 100)
  should.equal(process.receive(other, 50), Error(Nil))
}

pub fn slow_client_drops_test() {
  let hub = hub(1)
  let client = process.new_subject()
  live.register(hub, "chat", client)

  live.broadcast(hub, "chat", live.patch("m", "1"))
  live.broadcast(hub, "chat", live.patch("m", "2"))

  let assert Ok(first) = process.receive(client, 100)
  should.equal(first, live.patch("m", "1"))
  should.equal(process.receive(client, 50), Error(Nil))
  should.equal(live.dropped(hub), 1)
}

pub fn ack_resumes_delivery_test() {
  let hub = hub(1)
  let client = process.new_subject()
  let id = live.register(hub, "chat", client)

  live.broadcast(hub, "chat", live.patch("m", "1"))
  let assert Ok(_) = process.receive(client, 100)
  live.ack(hub, id)
  live.broadcast(hub, "chat", live.patch("m", "2"))

  let assert Ok(second) = process.receive(client, 100)
  should.equal(second, live.patch("m", "2"))
  should.equal(live.dropped(hub), 0)
}

pub fn unregister_stops_delivery_test() {
  let hub = hub(10)
  let client = process.new_subject()
  let id = live.register(hub, "chat", client)
  live.unregister(hub, id)

  live.broadcast(hub, "chat", live.patch("m", "1"))
  should.equal(process.receive(client, 50), Error(Nil))
}

pub fn encode_patch_test() {
  let encoded = live.encode(live.patch("messages", "<p>hi</p>"))
  should.be_true(string.contains(encoded, "\"kind\":\"morph\""))
  should.be_true(string.contains(encoded, "\"target\":\"messages\""))
}

pub fn encode_push_test() {
  let encoded = live.encode(live.push("messages", "<p>hi</p>"))
  should.be_true(string.contains(encoded, "\"kind\":\"append\""))
}

pub fn encode_stream_op_test() {
  let encoded = live.encode(live.stream_op(stream.toast("<div>hi</div>")))
  should.be_true(string.contains(encoded, "\"kind\":\"toast\""))
}

pub fn render_test() {
  should.equal(live.render(element.text("hi")), "hi")
}

pub fn drop_logging_test() {
  should.be_true(live.should_log_drop(1))
  should.be_true(live.should_log_drop(100))
  should.be_true(live.should_log_drop(200))
  should.be_false(live.should_log_drop(2))
}
