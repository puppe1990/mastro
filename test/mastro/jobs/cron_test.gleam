/// `mastro/jobs` cron expressions.
///
import gleeunit/should
import mastro/jobs

// -- Cron ---------------------------------------------------------------------

pub fn cron_next_finds_the_next_hour_test() {
  // 1970-01-01 00:00 UTC: the next 03:00 is three hours away.
  should.equal(jobs.cron_next("0 3 * * *", 0), Ok(10_800))
  should.equal(jobs.cron_next("0 3 * * *", 10_800), Ok(97_200))
}

pub fn cron_next_handles_steps_and_lists_test() {
  // */15 fires at :15, not at the boundary it starts from.
  should.equal(jobs.cron_next("*/15 * * * *", 0), Ok(900))
  should.equal(jobs.cron_next("30 9,17 * * *", 0), Ok(34_200))
}

pub fn cron_next_handles_ranges_test() {
  // 9-17 expands to [9..17], so the first hit is 09:00.
  should.equal(jobs.cron_next("0 9-17 * * *", 0), Ok(32_400))
  // An inverted range is rejected rather than silently wrapped.
  should.be_error(jobs.cron_next("0 17-9 * * *", 0))
}

pub fn cron_next_handles_weekdays_test() {
  // 1970-01-01 was a Thursday; the next Monday 00:00 is 1970-01-05.
  should.equal(jobs.cron_next("0 0 * * 1", 0), Ok(345_600))
}

pub fn cron_next_rejects_a_bad_expression_test() {
  should.be_error(jobs.cron_next("0 3 * *", 0))
  should.be_error(jobs.cron_next("0 99 * * *", 0))
}
