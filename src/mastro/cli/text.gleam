/// Text helpers shared by the CLI modules.
///
import gleam/string

/// Uppercase the first grapheme: `posts` -> `Posts`.
pub fn capitalize(word: String) -> String {
  case string.pop_grapheme(word) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(_) -> word
  }
}

/// Singularize a resource name for generated files and types:
/// `posts` -> `post`, `categories` -> `category`, `buses` -> `bus`.
/// Deliberately naive: only the three common English suffixes.
pub fn singularize(word: String) -> String {
  case string.ends_with(word, "ies") {
    True -> string.drop_end(word, 3) <> "y"
    False -> singularize_es(word)
  }
}

fn singularize_es(word: String) -> String {
  case string.ends_with(word, "ses") {
    True -> string.drop_end(word, 2)
    False -> drop_trailing_s(word)
  }
}

fn drop_trailing_s(word: String) -> String {
  case string.ends_with(word, "s") {
    True -> string.drop_end(word, 1)
    False -> word
  }
}
