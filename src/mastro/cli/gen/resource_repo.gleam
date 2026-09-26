/// The generated repo module: dispatch per database and the count queries.
///
import mastro/cli/gen/resource_repo_pog
import mastro/cli/gen/resource_repo_sqlite
import mastro/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}

pub fn resource_repo(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  db: DbChoice,
  references: List(String),
  sortable: List(String),
  display: String,
  seed: Bool,
) -> String {
  case db {
    Sqlite | NoDb ->
      resource_repo_sqlite.resource_repo_sqlite(
        app_name,
        resource_singular,
        type_name,
        fields,
        references,
        sortable,
        display,
        seed,
      )
    Postgres ->
      resource_repo_pog.resource_repo_pog(
        app_name,
        resource_singular,
        type_name,
        fields,
        references,
        sortable,
        display,
        seed,
      )
  }
}
