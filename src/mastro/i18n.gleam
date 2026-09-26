//// Tiny i18n helper: a locale from `LOCALE` and a `t` lookup.
////
//// Catalogs are plain dictionaries. `t` falls back to English, then to the
//// key itself, so a missing translation is visible but never crashes a
//// render.

import gleam/dict.{type Dict}
import gleam/string

pub type Locale {
  En
  Pt
}

/// `LOCALE=pt` (or `pt-BR`) selects Portuguese; anything else is English.
pub fn parse(value: String) -> Locale {
  case string.lowercase(string.trim(value)) {
    "pt" -> Pt
    "pt-br" -> Pt
    "pt_br" -> Pt
    _ -> En
  }
}

pub fn code(locale: Locale) -> String {
  case locale {
    En -> "en"
    Pt -> "pt"
  }
}

/// Resolve a key for a locale, falling back to English and then to the key.
pub fn t(locale: Locale, key: String) -> String {
  case dict.get(catalog(locale), key) {
    Ok(value) -> value
    Error(_) ->
      case dict.get(catalog(En), key) {
        Ok(value) -> value
        Error(_) -> key
      }
  }
}

fn catalog(locale: Locale) -> Dict(String, String) {
  case locale {
    En -> dict.from_list(en_strings())
    Pt -> dict.from_list(pt_strings())
  }
}

fn en_strings() -> List(#(String, String)) {
  [
    #("app.home", "Home"),
    #("app.tagline", "A Gleam web app"),
    #("app.welcome", "Welcome"),
    #("nav.language", "Language"),
    #("auth.login", "Log in"),
    #("auth.logout", "Log out"),
    #("auth.register", "Sign up"),
  ]
}

fn pt_strings() -> List(#(String, String)) {
  [
    #("app.home", "Início"),
    #("app.welcome", "Bem-vindo"),
    #("nav.language", "Idioma"),
    #("auth.login", "Entrar"),
    #("auth.logout", "Sair"),
    #("auth.register", "Criar conta"),
  ]
}
