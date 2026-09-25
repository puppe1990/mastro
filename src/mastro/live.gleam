//// Live WebSocket hub.
////
//// In-process fan-out only: Live is **single-replica**. Two app replicas
//// do not share sockets; cross-replica fan-out needs an external bus.
////
//// The hub is transport agnostic. Mount `mist.websocket` in the app,
//// register the connection on init, forward hub messages as frames and
//// `ack` after each successful write so slow clients are dropped rather
//// than allowed to grow unbounded.

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/otp/actor
import gleam/result
import lustre/element.{type Element}
import mastro/stream

pub opaque type HubMessage {
  Register(
    view: String,
    subject: process.Subject(Message),
    reply: process.Subject(Int),
  )
  Unregister(id: Int)
  Ack(id: Int)
  Broadcast(view: String, message: Message)
  Dropped(reply: process.Subject(Int))
}

pub type Hub =
  process.Subject(HubMessage)

pub type Message {
  Patch(target: String, html: String)
  Push(target: String, html: String)
  Stream(op: stream.Op)
}

type Subscriber {
  Subscriber(view: String, subject: process.Subject(Message))
}

type State {
  State(
    next_id: Int,
    subscribers: Dict(Int, Subscriber),
    pending: Dict(Int, Int),
    dropped: Int,
    max_pending: Int,
  )
}

pub fn start(max_pending max: Int) -> Result(Hub, actor.StartError) {
  actor.new(State(
    next_id: 0,
    subscribers: dict.new(),
    pending: dict.new(),
    dropped: 0,
    max_pending: max,
  ))
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

/// Register a connection for a view. Returns the subscriber id.
pub fn register(
  hub: Hub,
  view: String,
  subject: process.Subject(Message),
) -> Int {
  let reply = process.new_subject()
  actor.send(hub, Register(view:, subject:, reply:))
  case process.receive(reply, 5000) {
    Ok(id) -> id
    Error(_) -> -1
  }
}

pub fn unregister(hub: Hub, id: Int) -> Nil {
  actor.send(hub, Unregister(id:))
}

/// Mark one message as handled, freeing a slot for the next broadcast.
pub fn ack(hub: Hub, id: Int) -> Nil {
  actor.send(hub, Ack(id:))
}

pub fn broadcast(hub: Hub, view: String, message: Message) -> Nil {
  actor.send(hub, Broadcast(view:, message:))
}

pub fn dropped(hub: Hub) -> Int {
  let reply = process.new_subject()
  actor.send(hub, Dropped(reply:))
  case process.receive(reply, 5000) {
    Ok(count) -> count
    Error(_) -> 0
  }
}

// -- Message constructors -----------------------------------------------------

pub fn patch(target: String, html: String) -> Message {
  Patch(target:, html:)
}

pub fn push(target: String, html: String) -> Message {
  Push(target:, html:)
}

pub fn stream_op(op: stream.Op) -> Message {
  Stream(op:)
}

/// Encode a hub message as one Amarra Stream op line.
pub fn encode(message: Message) -> String {
  case message {
    Patch(target:, html:) -> stream.encode(stream.morph(target, html))
    Push(target:, html:) -> stream.encode(stream.append(target, html))
    Stream(op:) -> stream.encode(op)
  }
}

/// Render a view element to HTML for broadcasting.
pub fn render(view: Element(Nil)) -> String {
  element.to_string(view)
}

pub fn should_log_drop(dropped: Int) -> Bool {
  dropped == 1 || dropped % 100 == 0
}

// -- Actor --------------------------------------------------------------------

fn handle(state: State, msg: HubMessage) -> actor.Next(State, HubMessage) {
  case msg {
    Register(view:, subject:, reply:) -> {
      let id = state.next_id
      process.send(reply, id)
      actor.continue(
        State(
          ..state,
          next_id: id + 1,
          subscribers: dict.insert(
            state.subscribers,
            id,
            Subscriber(view:, subject:),
          ),
        ),
      )
    }

    Unregister(id:) ->
      actor.continue(
        State(
          ..state,
          subscribers: dict.delete(state.subscribers, id),
          pending: dict.delete(state.pending, id),
        ),
      )

    Ack(id:) ->
      actor.continue(State(..state, pending: ack_one(state.pending, id)))

    Broadcast(view:, message:) ->
      actor.continue(
        dict.fold(state.subscribers, state, fn(acc, id, subscriber) {
          case subscriber.view == view {
            True -> deliver(acc, id, message)
            False -> acc
          }
        }),
      )

    Dropped(reply:) -> {
      process.send(reply, state.dropped)
      actor.continue(state)
    }
  }
}

fn ack_one(pending: Dict(Int, Int), id: Int) -> Dict(Int, Int) {
  case dict.get(pending, id) {
    Ok(n) if n > 0 -> dict.insert(pending, id, n - 1)
    _ -> pending
  }
}

fn deliver(state: State, id: Int, message: Message) -> State {
  let in_flight = dict.get(state.pending, id) |> result.unwrap(0)
  case in_flight + 1 > state.max_pending {
    True -> {
      let dropped = state.dropped + 1
      case should_log_drop(dropped) {
        True ->
          io.println(
            "[live] dropped a message for a slow client (total "
            <> int.to_string(dropped)
            <> ")",
          )
        False -> Nil
      }
      State(..state, dropped: dropped)
    }
    False -> {
      case dict.get(state.subscribers, id) {
        Ok(subscriber) -> process.send(subscriber.subject, message)
        Error(_) -> Nil
      }
      State(..state, pending: dict.insert(state.pending, id, in_flight + 1))
    }
  }
}
