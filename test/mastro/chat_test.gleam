import gleam/list
import gleam/string
import gleeunit/should
import lustre/element
import mastro/chat

fn text(view: element.Element(Nil)) -> String {
  element.to_string(view)
}

pub fn truncate_test() {
  should.equal(chat.truncate("hello world", 5), "hello…")
  should.equal(chat.truncate("hi", 5), "hi")
}

pub fn message_bubble_test() {
  let out = chat.message_bubble(chat.User, "hello", "12:00") |> text
  should.be_true(string.contains(out, "chat-message"))
  should.be_true(string.contains(out, "user"))
  should.be_true(string.contains(out, "hello"))
  should.be_true(string.contains(out, "12:00"))
}

pub fn safe_bubble_escapes_test() {
  let out =
    chat.message_bubble(chat.Assistant, "<script>x</script>", "") |> text
  should.be_false(string.contains(out, "<script>"))
  should.be_true(string.contains(out, "&lt;script&gt;"))
}

pub fn live_bubble_test() {
  let out = chat.live_bubble("token") |> text
  should.be_true(string.contains(out, "id=\"chat-live\""))
  should.be_true(string.contains(out, "token"))
}

pub fn history_test() {
  let out = chat.history() |> text
  should.be_true(string.contains(out, "id=\"chat-history\""))
  should.be_true(string.contains(out, "data-amarra-stream"))
}

pub fn tool_bubbles_test() {
  let call = chat.tool_call_bubble("search", "{}") |> text
  should.be_true(string.contains(call, "tool-call"))
  should.be_true(string.contains(call, "search"))

  let result = chat.tool_result_bubble("search", "ok") |> text
  should.be_true(string.contains(result, "tool-result"))
  should.be_true(string.contains(result, "ok"))
}

pub fn detail_bubble_test() {
  let out = chat.detail_bubble("More", "details") |> text
  should.be_true(string.contains(out, "<details"))
  should.be_true(string.contains(out, "More"))
  should.be_true(string.contains(out, "details"))
}

pub fn unsafe_live_html_test() {
  let out = chat.unsafe_live_html("<b>raw</b>") |> text
  should.be_true(string.contains(out, "<b>raw</b>"))
}

pub fn select_window_ends_at_last_user_test() {
  let messages = [
    chat.ChatMessage(role: chat.System, text: "sys"),
    chat.ChatMessage(role: chat.User, text: "u1"),
    chat.ChatMessage(role: chat.Assistant, text: "a1"),
    chat.ChatMessage(role: chat.User, text: "u2"),
    chat.ChatMessage(role: chat.Assistant, text: "a2"),
  ]
  let window = chat.select_window_with_last_user(messages, 2)
  should.equal(list.map(window, fn(m) { m.text }), ["a1", "u2"])
}

pub fn select_window_without_user_falls_back_test() {
  let messages = [
    chat.ChatMessage(role: chat.Assistant, text: "a1"),
    chat.ChatMessage(role: chat.Assistant, text: "a2"),
  ]
  let window = chat.select_window_with_last_user(messages, 1)
  should.equal(list.map(window, fn(m) { m.text }), ["a2"])
}
