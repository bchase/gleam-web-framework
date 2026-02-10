import gleam/string
import gleam/int
import gleam/result
import birl
import gleam/time/timestamp as ts
import gleam/time/duration as dur
import gleam/time/calendar as cal

pub fn to_timestamp(
  time time: birl.Time,
) -> ts.Timestamp {
  let birl.TimeOfDay(
    hour: hours,
    minute: minutes,
    second: seconds,
    milli_second:,
  ) = birl.get_time_of_day(time)
  let birl.Day(year:, month:, date:) = birl.get_day(time)

  let month =
    month
    |> cal.month_from_int
    |> result.lazy_unwrap(fn() {
      panic as {
        "`common.birl_to_timestamp` got an invalid month int: " <>
          { month |> int.to_string } <> "\n" <>
          "from `birl.Time`: " <> { time |> string.inspect } <> "\n"
      }
    })

  // let microseconds = milli_second * 1000
  let nanoseconds = milli_second * 1000 * 1000

  let date = cal.Date(year:, month:, day: date)
  let time = cal.TimeOfDay(hours:, minutes:, seconds:, nanoseconds:)

  ts.from_calendar(date, time, dur.seconds(0))
}

pub fn from_timestamp(
  time time: ts.Timestamp,
) -> birl.Time {
  let #(date, time) = ts.to_calendar(time, dur.seconds(0))

  let cal.Date(year:, month:, day:) = date
  let cal.TimeOfDay(hours:, minutes:, seconds:, ..) = time
  // TODO `microseconds`?
  let month = month |> cal.month_to_int

  birl.from_erlang_universal_datetime(
    #(#(year, month, day), #(hours, minutes, seconds)),
  )
}
