import { strict as assert } from "node:assert";
import test from "node:test";
import {
  bulkSummary,
  nextTheme,
  passwordState,
  pathMatches,
  resolveTheme,
  revealMatches,
} from "./amarra.js";

const ORIGIN = "https://app.test";

test("bulkSummary: all rows selected", () => {
  assert.deepEqual(bulkSummary(3, 3), { checked: true, indeterminate: false, count: 3 });
});

test("bulkSummary: some rows selected is indeterminate", () => {
  assert.deepEqual(bulkSummary(1, 3), { checked: false, indeterminate: true, count: 1 });
});

test("bulkSummary: none selected", () => {
  assert.deepEqual(bulkSummary(0, 3), { checked: false, indeterminate: false, count: 0 });
});

test("bulkSummary: empty list is not checked", () => {
  assert.deepEqual(bulkSummary(0, 0), { checked: false, indeterminate: false, count: 0 });
});

test("revealMatches compares as strings", () => {
  assert.equal(revealMatches("access_keys", "access_keys"), true);
  assert.equal(revealMatches("1", 1), true);
  assert.equal(revealMatches("default_chain", "access_keys"), false);
});

test("pathMatches ignores query strings", () => {
  assert.equal(pathMatches("/posts", "/posts?page=2", ORIGIN), true);
  assert.equal(pathMatches("/posts", "/posts/1", ORIGIN), false);
  assert.equal(pathMatches("/", "/", ORIGIN), true);
});

test("nextTheme toggles between light and dark", () => {
  assert.equal(nextTheme("dark"), "light");
  assert.equal(nextTheme("light"), "dark");
  assert.equal(nextTheme(undefined), "light");
});

test("resolveTheme only accepts known themes", () => {
  assert.equal(resolveTheme("light"), "light");
  assert.equal(resolveTheme("dark"), "dark");
  assert.equal(resolveTheme("nope"), "dark");
  assert.equal(resolveTheme(null), "dark");
});

test("passwordState toggles type, aria-pressed and label", () => {
  assert.deepEqual(passwordState(false), {
    type: "password",
    pressed: "false",
    label: "Show password",
  });
  assert.deepEqual(passwordState(true), {
    type: "text",
    pressed: "true",
    label: "Hide password",
  });
});
