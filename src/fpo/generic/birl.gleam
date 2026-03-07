import gleam/bool
import gleam/option.{type Option, Some, None}
import gleam/string
import gleam/int
import gleam/result.{try}
import gleam/time/timestamp as ts
import gleam/time/duration as dur
import gleam/time/calendar as cal
import birl/duration
import birl.{type Day}
import gleam/order.{type Order, Gt, Lt, Eq}
import gleam/yielder.{type Yielder}

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

pub fn day_str(
  day day: Day,
) -> String {
  [
    day.year |> int.to_string |> string.pad_start(4, "0"),
    day.month |> int.to_string |> string.pad_start(2, "0"),
    day.date |> int.to_string |> string.pad_start(2, "0"),
  ]
  |> string.join("-")
}

pub fn date_range(
  from from: Day,
  through through: Day,
) -> List(Day) {
  let start = birl.unix_epoch |> birl.set_day(from)
  let end = birl.unix_epoch |> birl.set_day(through)

  case start |> birl.compare(end) {
    order.Gt ->
      []

    order.Eq | order.Lt -> {
      let next = start |> birl.add(duration.days(1)) |> birl.get_day

      [from, ..date_range(from: next, through:)]
    }
  }
}

pub fn compare_day(a: Day, b: Day) -> Order {
  int.compare(a.year, b.year)
  |> order.break_tie(int.compare(a.month, b.month))
  |> order.break_tie(int.compare(a.date, b.date))
}

pub fn day_from_calendar_date(
  date date: cal.Date,
) -> Day {
    let cal.Date(year:, month:, day: date) = date
    let month = cal.month_to_int(month)
    birl.Day(year:, month:, date:)
}

pub fn day_to_calendar_date(
  day day: Day,
) -> Result(cal.Date, Nil) {
    let birl.Day(year:, month:, date: day) = day
    use month <- try(cal.month_from_int(month))
    Ok(cal.Date(year:, month:, day:))
}

pub fn day_utc_now() -> Day {
  birl.utc_now()
  |> birl.get_day
}

pub fn day_adjust(
  day day: Day,
  days days: Int,
) -> Day {
  day
  |> birl.set_day(birl.unix_epoch, _)
  |> birl.add(duration.days(days))
  |> birl.get_day
}

pub fn zero_day() -> Day {
  birl.unix_epoch
  |> birl.get_day
}

pub type DayRange {
  DayRange(
    start: Day,
    end: Day,
  )
}

pub fn day_ranges_back(
  from latest_day: Day,
  until earliest_day: Day,
  days_at_a_time days: Int,
) -> Yielder(DayRange) {
  use <- bool.guard(compare_day(latest_day, earliest_day) == order.Lt, yielder.empty())
  use <- bool.guard(!{ days >= 1 }, yielder.empty())

  let start =
    birl.unix_epoch
    |> birl.set_day(latest_day)
    |> birl.subtract(duration.days(days - 1))
    |> birl.get_day

  let start =
    case compare_day(start, earliest_day) {
      Lt -> earliest_day
      Eq | Gt -> start
    }

  let initial = DayRange(start:, end: latest_day)

  let invalid_day = birl.Day(0, 0, -1)

  yielder.unfold(from: initial, with: fn(range) {
    use <- bool.guard(compare_day(range.start, invalid_day) == Eq, yielder.Done)

    case range.start |> compare_day(earliest_day) {
      Lt ->
        yielder.Done

      Eq ->
        range
        |> yielder.Next(DayRange(start: invalid_day, end: invalid_day))

      Gt -> {
        let end =
          birl.unix_epoch
          |> birl.set_day(range.start)
          |> birl.subtract(duration.days(1))
          |> birl.get_day

        let start =
          birl.unix_epoch
          |> birl.set_day(end)
          |> birl.subtract(duration.days(days))
          |> birl.get_day

        let start =
          case compare_day(start, earliest_day) {
            Gt | Eq -> start
            Lt -> earliest_day
          }

        let next = DayRange(start:, end:)

        range
        |> yielder.Next(next)
      }
    }
  })
}

// pub fn day_range(
//   start start: Day,
//   end end: Option(Day),
// ) -> Yielder(Day) {
//   let zero = birl.unix_epoch

//   let start = birl.set_day(zero, start)
//   let end = end |> option.map(fn(end) { birl.set_day(zero, end) })

//   let step = duration.days(1)

//   birl.range(from: start, to: end, step:)
//   |> yielder.map(fn(time) { birl.get_day(time) })
// }

// // //

// pub opaque type Timezone {
//   Timezone(tz: tempo.TimeZoneProvider)
// }

// pub opaque type Offset {
//   Offset(offset: tempo.Offset)
// }

// pub fn utc_timezone() -> Timezone {
//   let assert Ok(tz) = parse_timezone("Etc/UTC")
//   tz
// }

// pub fn utc_offset() -> Offset {
//   let assert Ok(os) = parse_offset(0)
//   os
// }

// pub fn parse_timezone(
//   str str: String,
// ) -> Result(Timezone, Nil) {
//   gtz.timezone(str)
//   |> result.map(Timezone)
// }

// pub fn parse_offset(
//   minutes minutes: Int
// ) -> Result(Offset, Nil) {
//   offset.from_duration(tdur.minutes(minutes))
//   |> result.map(Offset)
// }

// pub fn offset(
//   time time: birl.Time,
//   offset offset: Offset,
// ) -> birl.Time {
//   let dt =
//     time
//     |> to_timestamp
//     |> datetime.from_timestamp
//     |> datetime.to_offset(offset.offset)

//   let offset =
//     dt
//     |> datetime.get_offset
//     |> offset.to_string

//   dt
//   |> datetime.to_timestamp
//   |> from_timestamp
//   |> birl.set_offset(offset)
//   |> result.unwrap(time)
// }

// pub fn convert(
//   time time: birl.Time,
//   tz tz: Timezone,
// ) -> birl.Time {
//   let assert Ok(offset) =
//     time
//     |> birl.get_offset
//     |> offset.from_string

//   let ts =
//     time
//     |> to_timestamp

//   let dt =
//     ts
//     |> datetime.from_timestamp
//     // |> datetime.to_offset(offset)
//     |> datetime.to_timezone(tz.tz)

//   let offset =
//     dt
//     |> datetime.get_offset
//     |> offset.to_string

//   dt
//   |> datetime.to_timestamp
//   |> from_timestamp
//   |> birl.set_offset(offset)
//   |> result.unwrap(time)
// }

// pub fn offset_minutes(
//   time time: birl.Time,
// ) -> Int {
//   let offset = birl.get_offset(time)

//   use <- bool.guard(offset == "Z", 0)

//   let assert Ok(re) =
//     "^([-+])?(\\d+)[:](\\d+)$"
//     |> regexp.from_string

//   let groups =
//     case regexp.scan(re, offset) {
//       [regexp.Match(submatches:, ..), .. ] -> submatches
//       _ -> []
//     }

//   let #(sign, hours, mins) =
//     case groups {
//       [sign, Some(hours), Some(mins)] -> {
//         case int.parse(hours), int.parse(mins) {
//           Ok(hours), Ok(mins) -> #(sign, hours, mins)
//           _, _ -> #(None, 0, 0)
//         }
//       }
//       _ -> #(None, 0, 0)
//     }

//   let offset = hours * 60 + mins

//   case sign {
//     Some("-") ->
//       int.negate(offset)

//     Some("+") |
//     Some(_) |
//     None ->
//       offset
//   }
// }

// pub fn beginning_of_day(
//   time time: birl.Time,
// ) -> birl.Time {
//   time
//   |> birl.set_time_of_day(birl.TimeOfDay(0, 0, 0, 0))
// }

// pub fn end_of_day(
//   time time: birl.Time,
// ) -> birl.Time {
//   time
//   |> birl.set_time_of_day(birl.TimeOfDay(0, 0, 0, 0))
//   |> birl.add(duration.days(1))
//   |> birl.subtract(duration.micro_seconds(1))
// }
