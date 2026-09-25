import gleeunit/should
import mastro/i18n

pub fn parse_accepts_portuguese_variants_test() {
  i18n.parse("pt") |> should.equal(i18n.Pt)
  i18n.parse("PT-BR") |> should.equal(i18n.Pt)
  i18n.parse("pt_br") |> should.equal(i18n.Pt)
}

pub fn parse_defaults_to_english_test() {
  i18n.parse("en") |> should.equal(i18n.En)
  i18n.parse("fr") |> should.equal(i18n.En)
  i18n.parse("") |> should.equal(i18n.En)
}

pub fn code_round_trips_test() {
  i18n.code(i18n.En) |> should.equal("en")
  i18n.code(i18n.Pt) |> should.equal("pt")
}

pub fn t_resolves_per_locale_test() {
  i18n.t(i18n.En, "app.home") |> should.equal("Home")
  i18n.t(i18n.Pt, "app.home") |> should.equal("Início")
}

pub fn t_falls_back_to_english_then_the_key_test() {
  i18n.t(i18n.Pt, "app.tagline") |> should.equal("A Gleam web app")
  i18n.t(i18n.En, "does.not.exist") |> should.equal("does.not.exist")
}
