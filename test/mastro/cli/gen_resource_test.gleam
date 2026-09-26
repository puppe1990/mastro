/// Integration tests for `gen resource` inside a generated project.
///
import gleam/list
import gleam/string
import gleeunit/should
import mastro/cli/cli_support.{
  current_directory, file_contains, file_exists, in_temp_dir, set_cwd,
}
import mastro/cli/gen/resource as gen_resource
import mastro/cli/new
import simplifile

pub fn resource_reference_adds_foreign_key_and_options_test() {
  in_temp_dir("resource_fk", fn(dir) {
    let project_dir = dir <> "/fk_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string", "author:references"])

    file_contains(
      "src/fk_app/data/migrations/001_create_posts.sql",
      "author_id INTEGER NOT NULL REFERENCES authors(id)",
    )
    |> should.be_true
    file_contains("src/fk_app/domain/post.gleam", "author_id: Int")
    |> should.be_true
    file_contains("src/fk_app/data/post_repo.gleam", "pub fn author_options(")
    |> should.be_true
    file_contains("src/fk_app/data/post_repo.gleam", "query.order_by(sort, dir")
    |> should.be_true
    file_contains(
      "src/fk_app/data/post_repo.gleam",
      "query.like_pattern(search)",
    )
    |> should.be_true
    file_contains("src/fk_app/web/post_handler.gleam", "query.parse(req.query)")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_seeds_the_parent_resource_first_test() {
  in_temp_dir("resource_fk_seed", fn(dir) {
    let project_dir = dir <> "/fk_seed_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("authors", ["name:string"])
    gen_resource.resource("posts", ["title:string", "author:references"])

    // The FK constraint fails on a fresh database unless the parent row is
    // there first.
    file_contains(
      "src/fk_seed_app/data/post_repo.gleam",
      "use author_id <- result.try(author_repo.seed_demo(db_path))",
    )
    |> should.be_true
    file_contains(
      "src/fk_seed_app/data/post_repo.gleam",
      "import fk_seed_app/data/author_repo",
    )
    |> should.be_true
    file_contains(
      "src/fk_seed_app/data/post_repo.gleam",
      "author_id: author_id",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_seeds_an_existing_parent_when_it_has_no_seed_test() {
  in_temp_dir("resource_fk_fallback", fn(dir) {
    let project_dir = dir <> "/fb_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("users", ["name:string", "--no-seed"])
    gen_resource.resource("posts", ["title:string", "user:references"])

    file_contains(
      "src/fb_app/data/post_repo.gleam",
      "user_repo.list(db_path, \"\", \"\", \"\", 1)",
    )
    |> should.be_true
    file_contains("src/fb_app/data/post_repo.gleam", "user_id: user.id")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_without_the_parent_repo_skips_the_demo_seed_test() {
  in_temp_dir("resource_fk_orphan", fn(dir) {
    let project_dir = dir <> "/orphan_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string", "author:references"])

    // Nothing to call: the seed would not compile, so it is skipped.
    file_contains("src/orphan_app/data/post_repo.gleam", "seed_demo")
    |> should.be_false
    file_contains("src/orphan_app/data/post_repo.gleam", "author_repo")
    |> should.be_false
    file_contains("src/orphan_app.gleam", "post_repo.seed_demo")
    |> should.be_false
    // The rest of the resource is generated.
    file_contains(
      "src/orphan_app/data/post_repo.gleam",
      "pub fn author_options(",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_index_uses_the_kit_test() {
  in_temp_dir("resource_kit", fn(dir) {
    let project_dir = dir <> "/kit_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string", "author:references"])

    let views = "src/kit_app/web/post_views.gleam"
    file_contains(views, "import mastro/kit") |> should.be_true
    file_contains(views, "kit.filters(") |> should.be_true
    file_contains(views, "kit.table(") |> should.be_true
    file_contains(views, "kit.empty_state(") |> should.be_true
    file_contains(views, "kit.pagination(") |> should.be_true
    file_contains(
      views,
      "kit.Column(field: \"title\", label: \"Title\", sortable: True)",
    )
    |> should.be_true
    // A foreign key is a column, not a sort target: the repo does not
    // whitelist it.
    file_contains(
      views,
      "kit.Column(field: \"author_id\", label: \"Author\", sortable: False)",
    )
    |> should.be_true
    // The base carries the filter, so sort and page links keep it.
    file_contains(views, "query.url(\"/admin/posts\", [#(\"q\", q)])")
    |> should.be_true

    let handler = "src/kit_app/web/post_handler.gleam"
    file_contains(handler, "query.total_pages(post_repo.count(ctx.db_path, q)")
    |> should.be_true
    file_contains(handler, "index_view(items, q, sort, dir, page, pages)")
    |> should.be_true

    file_contains(
      "src/kit_app/data/post_repo.gleam",
      "pub fn count(db_path: String, search: String) -> Int",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_admin_routes_are_gated_test() {
  in_temp_dir("resource_gate", fn(dir) {
    let project_dir = dir <> "/gate_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string"])

    let router = "src/gate_app/router.gleam"
    file_contains(router, "[\"admin\", \"posts\"]") |> should.be_true
    file_contains(router, "[\"admin\", \"posts\", id, \"edit\"]")
    |> should.be_true
    file_contains(router, "public_index") |> should.be_false

    let handler = "src/gate_app/web/post_handler.gleam"
    file_contains(handler, "fn require_admin(") |> should.be_true
    file_contains(handler, "wisp.get_cookie(req, \"_user_id\", wisp.Signed)")
    |> should.be_true
    file_contains(handler, "use <- require_admin(req, ctx)") |> should.be_true
    file_contains(handler, "security.bearer_authorized") |> should.be_false

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_bearer_admin_auth_flips_the_boot_gate_test() {
  in_temp_dir("resource_bearer", fn(dir) {
    let project_dir = dir <> "/bearer_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string", "--admin-auth", "bearer"])

    let handler = "src/bearer_app/web/post_handler.gleam"
    file_contains(handler, "security.bearer_authorized(") |> should.be_true
    file_contains(handler, "ctx.config.admin_token") |> should.be_true
    file_contains(handler, "get_cookie") |> should.be_false

    // A bearer route makes ADMIN_TOKEN mandatory in production.
    file_contains("src/bearer_app/config.gleam", "admin_routes: True")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_public_adds_the_public_list_test() {
  in_temp_dir("resource_public", fn(dir) {
    let project_dir = dir <> "/pub_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string", "--public"])

    file_contains(
      "src/pub_app/router.gleam",
      "[\"posts\"], http.Get -> post_handler.public_index(req, ctx)",
    )
    |> should.be_true
    file_contains("src/pub_app/web/post_handler.gleam", "pub fn public_index(")
    |> should.be_true
    // The public list is not gated.
    file_contains("src/pub_app/web/post_handler.gleam", "public_index_view(")
    |> should.be_true
    file_contains(
      "src/pub_app/web/post_views.gleam",
      "pub fn public_index_view(",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_seeds_a_demo_row_at_boot_test() {
  in_temp_dir("resource_seed", fn(dir) {
    let project_dir = dir <> "/seed_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string"])

    let repo = "src/seed_app/data/post_repo.gleam"
    file_contains(repo, "pub fn seed_demo(db_path: String) -> Result(Int, Nil)")
    |> should.be_true
    file_contains(repo, "PostParams(title: \"Demo Title\")") |> should.be_true
    file_contains(repo, "inserted once, when the table is") |> should.be_true

    // Booted in development only.
    let main = "src/seed_app.gleam"
    file_contains(main, "import seed_app/data/post_repo") |> should.be_true
    file_contains(main, "post_repo.seed_demo(db_path)") |> should.be_true
    file_contains(main, "case config.is_development(cfg)") |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_no_seed_skips_the_demo_seed_test() {
  in_temp_dir("resource_no_seed", fn(dir) {
    let project_dir = dir <> "/noseed_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string", "--no-seed"])

    let repo = "src/noseed_app/data/post_repo.gleam"
    file_contains(repo, "seed_demo") |> should.be_false
    file_contains("src/noseed_app.gleam", "post_repo") |> should.be_false
    // The rest of the resource is unaffected.
    file_contains(repo, "pub fn count(db_path: String, search: String) -> Int")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_resource_creates_all_files_test() {
  in_temp_dir("gen_resource", fn(dir) {
    let project_dir = dir <> "/res_app"
    new.run(project_dir, ["--db", "postgres"])

    // Change to project dir and run gen resource
    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", [
      "title:string",
      "body:text",
      "published:bool",
    ])

    // Verify files exist
    file_exists("src/res_app/web/post_handler.gleam") |> should.be_true
    file_exists("src/res_app/web/post_views.gleam") |> should.be_true
    file_exists("src/res_app/web/forms/post_form.gleam") |> should.be_true
    file_exists("src/res_app/domain/post.gleam") |> should.be_true
    file_exists("src/res_app/data/post_repo.gleam") |> should.be_true
    file_exists("src/res_app/data/migrations/001_create_posts.sql")
    |> should.be_true
    file_exists("test/res_app/web/post_handler_test.gleam") |> should.be_true

    // Verify router was patched: the admin routes live under /admin
    file_contains("src/res_app/router.gleam", "post_handler") |> should.be_true
    file_contains("src/res_app/router.gleam", "[\"admin\", \"posts\"]")
    |> should.be_true

    // Verify domain type
    file_contains("src/res_app/domain/post.gleam", "pub type Post")
    |> should.be_true
    file_contains("src/res_app/domain/post.gleam", "title: String")
    |> should.be_true

    // Verify migration SQL
    file_contains(
      "src/res_app/data/migrations/001_create_posts.sql",
      "CREATE TABLE",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_two_resources_no_duplication_test() {
  in_temp_dir("gen_two", fn(dir) {
    let project_dir = dir <> "/two_app"
    new.run(project_dir, ["--db", "postgres"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string"])
    gen_resource.resource("comments", ["body:text"])

    // Both handlers exist
    file_exists("src/two_app/web/post_handler.gleam") |> should.be_true
    file_exists("src/two_app/web/comment_handler.gleam") |> should.be_true

    // Router has both resources, no duplication
    let assert Ok(router) = simplifile.read("src/two_app/router.gleam")
    let post_count =
      router
      |> string.split("post_handler.index")
      |> list.length
    // Should appear exactly twice: once in import area doesn't count, once in routes
    // Actually split produces N+1 parts for N occurrences
    { post_count <= 3 } |> should.be_true

    // Separate migrations
    file_exists("src/two_app/data/migrations/001_create_posts.sql")
    |> should.be_true
    file_exists("src/two_app/data/migrations/002_create_comments.sql")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}
