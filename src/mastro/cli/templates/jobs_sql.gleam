/// The SQL helpers the generated jobs module carries, shared by both drivers.
///
/// SQL the two drivers share; only execution and decoding differ.
pub fn sql() -> String {
  "fn columns() -> String {
  \"id, kind, payload, status, attempts, max_attempts, run_at, worker, heartbeat_at, finished_at, last_error, inserted_at\"
}

fn list_sql(filter: jobs.Filter) -> String {
  \"SELECT \"
  <> columns()
  <> \" FROM jobs\"
  <> where_sql(filter)
  <> \" ORDER BY id LIMIT \"
  <> int.to_string(filter.limit)
}

fn where_sql(filter: jobs.Filter) -> String {
  let conditions =
    [
      case filter.status {
        option.Some(status) -> option.Some(\"status = '\" <> status_sql(status) <> \"'\")
        option.None -> option.None
      },
      case filter.kind {
        option.Some(kind) -> option.Some(\"kind = '\" <> escape(kind) <> \"'\")
        option.None -> option.None
      },
    ]
    |> option.values

  case conditions {
    [] -> \"\"
    _ -> \" WHERE \" <> string.join(conditions, \" AND \")
  }
}

fn find_sql(id: Int) -> String {
  \"SELECT \" <> columns() <> \" FROM jobs WHERE id = \" <> int.to_string(id)
}

fn insert_sql(job: jobs.Job) -> String {
  \"INSERT INTO jobs (kind, payload, status, attempts, max_attempts, run_at, worker, heartbeat_at, finished_at, last_error, inserted_at) VALUES (\"
  <> value(job.kind)
  <> \", \"
  <> value(job.payload)
  <> \", '\"
  <> status_sql(job.status)
  <> \"', \"
  <> int.to_string(job.attempts)
  <> \", \"
  <> int.to_string(job.max_attempts)
  <> \", \"
  <> int.to_string(job.run_at)
  <> \", \"
  <> optional_text(job.worker)
  <> \", \"
  <> optional_int(job.heartbeat_at)
  <> \", \"
  <> optional_int(job.finished_at)
  <> \", \"
  <> optional_text(job.last_error)
  <> \", \"
  <> int.to_string(job.inserted_at)
  <> \")\"
}

fn update_sql(job: jobs.Job) -> String {
  \"UPDATE jobs SET kind = \"
  <> value(job.kind)
  <> \", payload = \"
  <> value(job.payload)
  <> \", status = '\"
  <> status_sql(job.status)
  <> \"', attempts = \"
  <> int.to_string(job.attempts)
  <> \", max_attempts = \"
  <> int.to_string(job.max_attempts)
  <> \", run_at = \"
  <> int.to_string(job.run_at)
  <> \", worker = \"
  <> optional_text(job.worker)
  <> \", heartbeat_at = \"
  <> optional_int(job.heartbeat_at)
  <> \", finished_at = \"
  <> optional_int(job.finished_at)
  <> \", last_error = \"
  <> optional_text(job.last_error)
  <> \" WHERE id = \"
  <> int.to_string(job.id)
}

fn delete_sql(id: Int) -> String {
  \"DELETE FROM jobs WHERE id = \" <> int.to_string(id)
}

fn status_sql(status: jobs.Status) -> String {
  case status {
    jobs.Pending -> \"pending\"
    jobs.Running -> \"running\"
    jobs.Failed -> \"failed\"
    jobs.Finished -> \"finished\"
  }
}

fn status_from_name(name: String) -> jobs.Status {
  case name {
    \"running\" -> jobs.Running
    \"failed\" -> jobs.Failed
    \"finished\" -> jobs.Finished
    _ -> jobs.Pending
  }
}

fn value(text: String) -> String {
  \"'\" <> escape(text) <> \"'\"
}

fn optional_text(field: option.Option(String)) -> String {
  case field {
    option.Some(text) -> value(text)
    option.None -> \"NULL\"
  }
}

fn optional_int(field: option.Option(Int)) -> String {
  case field {
    option.Some(number) -> int.to_string(number)
    option.None -> \"NULL\"
  }
}

fn escape(text: String) -> String {
  string.replace(text, \"'\", \"''\")
}
"
}
