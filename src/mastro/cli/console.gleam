/// `mastro console`
///
/// A small REPL over the project. `mastro/console` keeps the line handling
/// pure so it can be tested; this module only wires stdin/stdout.
import gleam/io
import gleam/list
import mastro/console

@external(erlang, "mastro_console_ffi", "read_line")
fn read_line() -> Result(String, Nil)

pub fn run(_args: List(String)) {
  io.println("mastro console — `help` for commands, `exit` to leave.")
  loop(console.new())
}

fn loop(state: console.State) {
  io.print("mastro> ")
  case read_line() {
    Error(_) -> Nil
    Ok(line) ->
      case console.handle(state, line) {
        console.Quit(lines, _) -> list.each(lines, io.println)
        console.Output(lines, next) -> {
          list.each(lines, io.println)
          loop(next)
        }
      }
  }
}
