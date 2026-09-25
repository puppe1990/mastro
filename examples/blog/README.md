# Blog Example

A blog application built with [Mastro](https://github.com/puppe1990/mastro).

## Features

- Posts with title, body, and published flag
- User registration and login
- About page

## Setup

```bash
# Install dependencies
gleam build

# Create database
createdb blog_dev

# Run migrations (see src/blog/data/migrations/)
psql blog_dev < src/blog/data/migrations/001_create_posts.sql
psql blog_dev < src/blog/data/migrations/002_create_users.sql

# Start the server
gleam run
# → http://localhost:4000
```

## Routes

Run `gleam run -m mastro/cli -- routes` to see all routes.
