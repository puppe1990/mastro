//// The console REPL, minus the terminal.
////
//// `handle` takes the previous state and one line, and returns the lines
//// to print plus the next state (or `Quit`). Tests drive it directly; the
//// CLI only reads stdin and prints the lines.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const max_history = 50

pub type State {
  State(history: List(String), last: Option(String))
}

/// What to do after a line: keep going, or stop.
pub type Outcome {
  Output(lines: List(String), state: State)
  Quit(lines: List(String), state: State)
}

pub fn new() -> State {
  State(history: [], last: None)
}

pub fn help() -> List(String) {
  [
    "commands:",
    "  <statement>   run SQL against the app's database",
    "  store, cfg, db available as bindings",
    "  help          this list",
    "  history       numbered history",
    "  !N            re-run entry N",
    "  !!            re-run the last command",
    "  exit, quit    leave",
  ]
}

pub fn handle(state: State, line: String) -> Outcome {
  let command = string.trim(line)
  case command {
    "" -> Output([], state)
    "help" -> Output(help(), remember(state, command))
    "exit" | "quit" -> Quit(["bye"], state)
    "history" -> Output(history_lines(state.history), remember(state, command))
    _ ->
      case string.starts_with(command, "!") {
        True -> repeat(state, command)
        False -> Output(run(command), remember(state, command))
      }
  }
}

fn run(command: String) -> List(String) {
  ["sql> " <> command]
}

fn repeat(state: State, command: String) -> Outcome {
  case command {
    "!" -> Output(["enter !N or !!"], state)
    "!!" -> replay(state, state.last)
    _ -> replay_nth(state, command)
  }
}

fn replay(state: State, last: Option(String)) -> Outcome {
  case last {
    Some(command) ->
      case string.starts_with(command, "!") {
        True -> Output(["refusing to re-run a history command"], state)
        False ->
          Output(
            list.append(run(command), ["  (from history)"]),
            remember(state, command),
          )
      }
    None -> Output(["no history yet"], state)
  }
}

fn replay_nth(state: State, command: String) -> Outcome {
  case int.parse(string.drop_start(command, 1)) {
    Ok(index) ->
      case nth(state.history, index) {
        Ok(entry) -> replay(state, Some(entry))
        Error(_) -> Output(["no such history entry"], state)
      }
    Error(_) -> Output(["usage: !N or !!"], state)
  }
}

fn nth(history: List(String), index: Int) -> Result(String, Nil) {
  case index < 1 {
    True -> Error(Nil)
    False -> history |> list.drop(index - 1) |> list.first
  }
}

fn history_lines(history: List(String)) -> List(String) {
  history
  |> list.index_map(fn(command, index) {
    "  " <> int.to_string(index + 1) <> "  " <> command
  })
}

fn remember(state: State, command: String) -> State {
  State(
    history: list.take([command, ..state.history], max_history),
    last: Some(command),
  )
}
