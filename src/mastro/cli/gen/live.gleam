/// `gen live <name>` — a Lustre server component, its socket and handler.
///
import gleam/io
import mastro/cli/files
import mastro/cli/format
import mastro/cli/gen/router
import mastro/cli/project
import mastro/cli/text
import simplifile

pub fn live(name: String) {
  let app = project.app_name()

  let live_dir = "src/" <> app <> "/web/live"
  let _ = simplifile.create_directory_all(live_dir)

  let component_path = live_dir <> "/" <> name <> ".gleam"
  let socket_path = live_dir <> "/" <> name <> "_socket.gleam"
  let handler_path = "src/" <> app <> "/web/" <> name <> "_live_handler.gleam"

  let assert Ok(_) = simplifile.write(component_path, live_component(app, name))
  let assert Ok(_) = simplifile.write(socket_path, live_socket(app, name))
  let assert Ok(_) = simplifile.write(handler_path, live_handler(app, name))

  // Patch router
  let _ = router.patch_live(app, name)
  let router_path = "src/" <> app <> "/router.gleam"
  format.format_files([component_path, socket_path, handler_path, router_path])

  io.println("")
  io.println("Created:")
  io.println("  " <> component_path)
  io.println("  " <> socket_path)
  io.println("  " <> handler_path)
  io.println("")
  io.println("Updated:")
  io.println("  " <> router_path)
  io.println("")
  io.println("The live component runs on the server and patches the DOM")
  io.println("over WebSocket. Visit /" <> name <> " to see it in action.")
}

fn live_component(_app: String, name: String) -> String {
  let type_name = text.capitalize(name)

  "/// " <> type_name <> " — a Lustre server component.
///
/// This component runs on the server. UI updates are sent to the
/// browser over WebSocket. The client runtime (~10kb) patches the DOM.
///
import gleam/int
import lustre
import lustre/effect
import lustre/element.{text}
import lustre/element/html.{button, div, h1, p}
import lustre/event

pub type Model {
  Model(count: Int)
}

pub type Msg {
  Increment
  Decrement
}

pub fn init(_flags: Nil) -> #(Model, effect.Effect(Msg)) {
  #(Model(count: 0), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    Increment -> #(Model(count: model.count + 1), effect.none())
    Decrement -> #(Model(count: model.count - 1), effect.none())
  }
}

pub fn view(model: Model) -> element.Element(Msg) {
  div([], [
    h1([], [text(\"" <> type_name <> "\")]),
    div([], [
      button([event.on_click(Decrement)], [text(\"-\")]),
      p([], [text(int.to_string(model.count))]),
      button([event.on_click(Increment)], [text(\"+\")]),
    ]),
  ])
}

/// Create a Lustre application for server-side rendering.
pub fn app() {
  lustre.application(init, update, view)
}
"
}

fn live_socket(app: String, name: String) -> String {
  "/// WebSocket transport for the " <> name <> " server component.
///
/// This module handles the WebSocket connection between the Lustre
/// server component and the browser client runtime.
///
/// ## Setup
///
/// 1. Add the WebSocket route to router.gleam. Because WebSocket
///    upgrades bypass Wisp, handle it before the Wisp handler in
///    your main module:
///
///    ```gleam
///    // In src/<app>.gleam, before the wisp_mist.handler:
///    import " <> app <> "/web/live/" <> name <> "_socket
///
///    // In the mist handler, check for WS upgrade:
///    fn handle(req) {
///      case request.path_segments(req) {
///        [\"" <> name <> "\", \"ws\"] -> " <> name <> "_socket.upgrade(req)
///        _ -> wisp_handler(req)
///      }
///    }
///    ```
///
/// 2. Start a Lustre factory supervisor in your main module to
///    manage server component instances.
///
/// See: https://hexdocs.pm/lustre/lustre/server_component.html
///
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/json
import gleam/option.{None}
import lustre/server_component
import mist.{type Connection, type ResponseData}

/// WebSocket connection state.
pub type State {
  State
}

/// Upgrade an HTTP request to a WebSocket for the server component.
pub fn upgrade(
  req: Request(Connection),
) -> response.Response(ResponseData) {
  mist.websocket(
    request: req,
    handler: fn(state, msg, conn) {
      case msg {
        mist.Text(text) -> {
          // Decode event from client and dispatch to server runtime
          // TODO: wire to your Lustre runtime Subject
          // case json.parse(text, server_component.runtime_message_decoder()) {
          //   Ok(runtime_msg) -> process.send(runtime, runtime_msg)
          //   Error(_) -> Nil
          // }
          mist.continue(state)
        }
        mist.Binary(_) -> mist.continue(state)
        mist.Custom(_) -> mist.continue(state)
        mist.Closed | mist.Shutdown -> mist.stop()
      }
    },
    on_init: fn(_conn) {
      // TODO: Start a Lustre server component instance here.
      // Use lustre.supervised() or lustre.factory() to create
      // a managed runtime, then register a callback to send
      // patches over the WebSocket:
      //
      // server_component.register_callback(fn(msg) {
      //   let patch = server_component.client_message_to_json(msg)
      //   mist.send_text_frame(conn, json.to_string(patch))
      // })
      #(State, None)
    },
    on_close: fn(_state) { Nil },
  )
}
"
}

fn live_handler(app: String, name: String) -> String {
  let type_name = text.capitalize(name)

  "/// Handler for the " <> name <> " live page.
///
/// Serves the HTML shell that mounts the Lustre server component
/// via the <lustre-server-component> custom element over WebSocket.
///
import " <> app <> "/context.{type Context}
import " <> app <> "/web/layouts/root_layout
import lustre/attribute
import lustre/element.{text}
import lustre/element/html.{div, section}
import lustre/server_component
import wisp.{type Request, type Response}

pub fn index(req: Request, _ctx: Context) -> Response {
  section([], [
    // Inline the Lustre server component client runtime
    server_component.script(),
    // Mount the server component, connecting via WebSocket
    server_component.element(
      [
        server_component.route(\"/" <> name <> "/ws\"),
        server_component.method(server_component.WebSocket),
      ],
      [text(\"Loading " <> type_name <> "...\")],
    ),
  ])
  |> root_layout.wrap(\"" <> type_name <> "\", req)
  |> wisp.html_response(200)
}
"
}
