import gleam/option
import gleeunit/should
import mastro/console

fn output(outcome: console.Outcome) -> List(String) {
  case outcome {
    console.Output(lines, _) -> lines
    console.Quit(lines, _) -> lines
  }
}

fn state_of(outcome: console.Outcome) -> console.State {
  case outcome {
    console.Output(_, state) -> state
    console.Quit(_, state) -> state
  }
}

pub fn empty_line_is_a_noop_test() {
  console.handle(console.new(), "   ") |> output |> should.equal([])
}

pub fn help_lists_the_commands_test() {
  let lines = console.handle(console.new(), "help") |> output
  lines |> should.equal(console.help())
}

pub fn exit_quits_test() {
  case console.handle(console.new(), "exit") {
    console.Quit([_], _) -> Nil
    _ -> should.fail()
  }
}

pub fn statements_are_echoed_and_remembered_test() {
  let outcome = console.handle(console.new(), "SELECT 1")
  output(outcome) |> should.equal(["sql> SELECT 1"])

  let next = console.handle(state_of(outcome), "!!")
  output(next) |> should.equal(["sql> SELECT 1", "  (from history)"])
}

pub fn history_is_numbered_most_recent_first_test() {
  let state =
    console.new()
    |> console.handle("one")
    |> state_of
    |> console.handle("two")
    |> state_of

  console.handle(state, "history")
  |> output
  |> should.equal(["  1  two", "  2  one"])
}

pub fn bang_n_replays_that_entry_test() {
  let state =
    console.new()
    |> console.handle("first")
    |> state_of
    |> console.handle("second")
    |> state_of

  console.handle(state, "!2")
  |> output
  |> should.equal(["sql> first", "  (from history)"])
}

pub fn bang_n_out_of_range_is_reported_test() {
  console.handle(console.new(), "!9")
  |> output
  |> should.equal(["no such history entry"])
}

pub fn bare_bang_asks_for_a_form_test() {
  console.handle(console.new(), "!")
  |> output
  |> should.equal(["enter !N or !!"])
}

pub fn repeat_without_history_is_reported_test() {
  console.handle(console.new(), "!!")
  |> output
  |> should.equal(["no history yet"])
}

pub fn history_commands_are_not_replayed_test() {
  let state = console.State(history: [], last: option.Some("!!"))
  console.handle(state, "!!")
  |> output
  |> should.equal(["refusing to re-run a history command"])
}
