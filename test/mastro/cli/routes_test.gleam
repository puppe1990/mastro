import gleeunit/should
import mastro/cli/routes

fn sample() -> String {
  "pub fn handle_request(req, ctx) {
  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)
    [\"posts\"], http.Get -> post_handler.index(req, ctx)
    [\"posts\", \"new\"], http.Get -> post_handler.new(req, ctx)
    [\"posts\", id], http.Get -> post_handler.show(req, ctx, id)
    _, _ -> error_handler.not_found(req)
  }
}"
}

pub fn extract_routes_reads_method_path_handler_test() {
  routes.extract_routes(sample())
  |> should.equal([
    routes.Route("GET", "/", "home_handler.index"),
    routes.Route("GET", "/posts", "post_handler.index"),
    routes.Route("GET", "/posts/new", "post_handler.new"),
    routes.Route("GET", "/posts/:id", "post_handler.show"),
  ])
}

pub fn conflicts_flag_literal_and_param_at_the_same_depth_test() {
  routes.conflicts([
    routes.Route("GET", "/posts/new", "post_handler.new"),
    routes.Route("GET", "/posts/:id", "post_handler.show"),
  ])
  |> should.equal([routes.Conflict("GET", "/posts/new", "/posts/:id")])
}

pub fn different_depths_do_not_conflict_test() {
  routes.conflicts([
    routes.Route("GET", "/posts", "post_handler.index"),
    routes.Route("GET", "/posts/:id", "post_handler.show"),
  ])
  |> should.equal([])
}

pub fn duplicates_conflict_test() {
  routes.conflicts([
    routes.Route("GET", "/posts", "a"),
    routes.Route("GET", "/posts", "b"),
  ])
  |> should.equal([routes.Conflict("GET", "/posts", "/posts")])
}

pub fn different_methods_do_not_conflict_test() {
  routes.conflicts([
    routes.Route("GET", "/posts", "index"),
    routes.Route("POST", "/posts", "create"),
  ])
  |> should.equal([])
}
