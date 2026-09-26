/// Cron parsing and next-fire computation for `mastro/jobs`.
///
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp

/// The next fire time after `from`, or an error for a bad expression.
pub fn next(expression: String, from: Int) -> Result(Int, String) {
  use fields <- result.try(parse_cron(expression))
  find_next(fields, next_minute(from), 0)
}

type Cron {
  Cron(
    minutes: List(Int),
    hours: List(Int),
    days: List(Int),
    months: List(Int),
    weekdays: List(Int),
    any_day: Bool,
    any_weekday: Bool,
  )
}

fn parse_cron(expression: String) -> Result(Cron, String) {
  case string.split(string.trim(expression), " ") |> list.filter(is_not_blank) {
    [minutes, hours, days, months, weekdays] -> {
      use minutes <- result.try(field(minutes, 0, 59))
      use hours <- result.try(field(hours, 0, 23))
      use days <- result.try(field(days, 1, 31))
      use months <- result.try(field(months, 1, 12))
      use weekdays <- result.try(field(weekdays, 0, 6))

      Ok(Cron(
        minutes: minutes,
        hours: hours,
        days: days,
        months: months,
        weekdays: weekdays,
        any_day: string.trim(days_raw(expression)) == "*",
        any_weekday: string.trim(weekday_raw(expression)) == "*",
      ))
    }
    _ -> Error("a cron expression has five fields: " <> expression)
  }
}

fn days_raw(expression: String) -> String {
  case string.split(string.trim(expression), " ") |> list.filter(is_not_blank) {
    [_, _, days, ..] -> days
    _ -> ""
  }
}

fn weekday_raw(expression: String) -> String {
  case string.split(string.trim(expression), " ") |> list.filter(is_not_blank) {
    [_, _, _, _, weekdays] -> weekdays
    _ -> ""
  }
}

fn is_not_blank(part: String) -> Bool {
  string.trim(part) != ""
}

/// Every value from `start` to `stop`, both included — what a cron field
/// expands to. Field bounds always run low to high.
fn inclusive_range(start: Int, stop: Int) -> List(Int) {
  int.range(from: start, to: stop + 1, with: [], run: list.prepend)
  |> list.reverse
}

fn field(text: String, low: Int, high: Int) -> Result(List(Int), String) {
  case string.trim(text) {
    "*" -> Ok(inclusive_range(low, high))
    _ -> {
      use parts <- result.try(
        text
        |> string.split(",")
        |> list.try_map(fn(part) { part_values(part, low, high) }),
      )
      Ok(parts |> list.flatten |> list.unique |> list.sort(int.compare))
    }
  }
}

fn part_values(part: String, low: Int, high: Int) -> Result(List(Int), String) {
  let #(range, stride) = case string.split(part, "/") {
    [range, stride_text] ->
      case int.parse(stride_text) {
        Ok(stride) if stride > 0 -> #(range, stride)
        _ -> #(range, 1)
      }
    _ -> #(part, 1)
  }

  use #(start, values) <- result.try(case string.trim(range) {
    "*" -> Ok(#(low, inclusive_range(low, high)))
    _ -> bounds(range, low, high)
  })

  Ok(
    values
    |> list.filter(fn(value) { { value - start } % stride == 0 }),
  )
}

fn bounds(
  range: String,
  low: Int,
  high: Int,
) -> Result(#(Int, List(Int)), String) {
  case string.split(string.trim(range), "-") {
    [start, end] ->
      case int.parse(start), int.parse(end) {
        Ok(start), Ok(end) if start >= low && end <= high && start <= end ->
          Ok(#(start, inclusive_range(start, end)))
        _, _ -> Error("bad range: " <> range)
      }
    [single] ->
      case int.parse(single) {
        Ok(value) if value >= low && value <= high -> Ok(#(value, [value]))
        _ -> Error("bad value: " <> single)
      }
    _ -> Error("bad field: " <> range)
  }
}

/// The next minute boundary strictly after `from`.
fn next_minute(from: Int) -> Int {
  from - from % 60 + 60
}

fn find_next(cron: Cron, candidate: Int, days_tried: Int) -> Result(Int, String) {
  case days_tried > 400 {
    True -> Error("no run time in the next year")
    False ->
      case day_matches(cron, candidate) {
        False -> find_next(cron, start_of_next_day(candidate), days_tried + 1)
        True ->
          case hour_matches(cron, candidate) {
            False -> find_next(cron, start_of_next_hour(candidate), days_tried)
            True ->
              case minute_matches(cron, candidate) {
                True -> Ok(candidate)
                False -> find_next(cron, candidate + 60, days_tried)
              }
          }
      }
  }
}

fn day_matches(cron: Cron, at: Int) -> Bool {
  let #(date, _) = to_calendar(at)

  case list.contains(cron.months, calendar.month_to_int(date.month)) {
    False -> False
    True -> {
      let day = list.contains(cron.days, date.day)
      let weekday = list.contains(cron.weekdays, weekday_of(at))

      // `*` in a field means the field does not constrain the day. When
      // both are restricted they are OR-ed, as Vixie cron does.
      case cron.any_day, cron.any_weekday {
        True, True -> True
        True, False -> weekday
        False, True -> day
        False, False -> day || weekday
      }
    }
  }
}

fn hour_matches(cron: Cron, at: Int) -> Bool {
  let #(_, time) = to_calendar(at)
  list.contains(cron.hours, time.hours)
}

fn minute_matches(cron: Cron, at: Int) -> Bool {
  let #(_, time) = to_calendar(at)
  list.contains(cron.minutes, time.minutes)
}

fn start_of_next_hour(at: Int) -> Int {
  at - at % 3600 + 3600
}

fn start_of_next_day(at: Int) -> Int {
  at - at % 86_400 + 86_400
}

fn to_calendar(at: Int) -> #(calendar.Date, calendar.TimeOfDay) {
  timestamp.to_calendar(timestamp.from_unix_seconds(at), duration.seconds(0))
}

/// 1970-01-01 was a Thursday, which is 4 when Sunday is 0.
fn weekday_of(at: Int) -> Int {
  let days = { at - at % 86_400 } / 86_400
  { days + 4 } % 7
}
