//// Chat view helpers.
////
//// Bubbles are plain Lustre elements; `element.text` escapes by default,
//// so `message_bubble` is safe. `unsafe_*` callers own sanitisation.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type Role {
  User
  Assistant
  System
}

pub type ChatMessage {
  ChatMessage(role: Role, text: String)
}

pub fn truncate(text: String, max: Int) -> String {
  case string.length(text) > max {
    True -> string.slice(text, 0, max) <> "…"
    False -> text
  }
}

pub fn message_bubble(role: Role, text: String, time: String) -> Element(Nil) {
  html.div([attribute.class("chat-message " <> role_class(role))], [
    html.div([attribute.class("chat-text")], [element.text(text)]),
    html.span([attribute.class("chat-time")], [element.text(time)]),
  ])
}

pub fn safe_message_bubble(
  role: Role,
  text: String,
  time: String,
) -> Element(Nil) {
  message_bubble(role, text, time)
}

pub fn live_bubble(text: String) -> Element(Nil) {
  html.div(
    [
      attribute.id("chat-live"),
      attribute.class("chat-message assistant live"),
    ],
    [element.text(text)],
  )
}

/// The scrolling history container that Stream ops target.
pub fn history() -> Element(Nil) {
  html.div(
    [
      attribute.id("chat-history"),
      attribute.data("amarra-stream", ""),
    ],
    [],
  )
}

pub fn tool_call_bubble(name: String, arguments: String) -> Element(Nil) {
  html.div(
    [
      attribute.class("chat-tool tool-call"),
      attribute.data("amarra-tool", name),
    ],
    [
      html.strong([], [element.text(name)]),
      html.pre([], [element.text(arguments)]),
    ],
  )
}

pub fn tool_result_bubble(name: String, result: String) -> Element(Nil) {
  html.div(
    [
      attribute.class("chat-tool tool-result"),
      attribute.data("amarra-tool", name),
    ],
    [
      html.pre([], [element.text(result)]),
    ],
  )
}

pub fn detail_bubble(summary: String, detail: String) -> Element(Nil) {
  html.details([attribute.class("chat-detail")], [
    html.summary([], [element.text(summary)]),
    html.p([], [element.text(detail)]),
  ])
}

/// Caller owns sanitisation of `html_string`.
pub fn unsafe_live_html(html_string: String) -> Element(Nil) {
  element.unsafe_raw_html(
    "",
    "div",
    [
      attribute.id("chat-live"),
      attribute.class("chat-message assistant live"),
    ],
    html_string,
  )
}

/// Caller owns sanitisation of `html_string`.
pub fn unsafe_message_html(role: Role, html_string: String) -> Element(Nil) {
  element.unsafe_raw_html(
    "",
    "div",
    [
      attribute.class("chat-message " <> role_class(role)),
    ],
    html_string,
  )
}

/// Window of at most `n` messages ending at the last user message.
/// Falls back to the trailing `n` messages when there is no user turn.
pub fn select_window_with_last_user(
  messages: List(ChatMessage),
  n: Int,
) -> List(ChatMessage) {
  case last_user_index(messages) {
    Some(index) ->
      messages
      |> list.drop(int.max(0, index + 1 - n))
      |> list.take(n)
    None -> messages |> list.drop(int.max(0, list.length(messages) - n))
  }
}

fn last_user_index(messages: List(ChatMessage)) -> Option(Int) {
  let #(last, _) =
    list.fold(messages, #(-1, 0), fn(acc, message) {
      let #(found, index) = acc
      case message.role {
        User -> #(index, index + 1)
        _ -> #(found, index + 1)
      }
    })
  case last {
    -1 -> None
    index -> Some(index)
  }
}

fn role_class(role: Role) -> String {
  case role {
    User -> "user"
    Assistant -> "assistant"
    System -> "system"
  }
}
