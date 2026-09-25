import { strict as assert } from "node:assert";
import test from "node:test";
import { parseOps } from "./amarra.js";

test("parseOps parses newline-delimited JSON ops", () => {
  const body = [
    '{"kind":"append","target":"list","html":"<li>a</li>"}',
    '{"kind":"toast","target":"amarra-toast-host","html":"<div>hi</div>"}',
  ].join("\n");
  const ops = parseOps(body);
  assert.equal(ops.length, 2);
  assert.equal(ops[0].kind, "append");
  assert.equal(ops[1].target, "amarra-toast-host");
});

test("parseOps ignores blank lines", () => {
  const body = '\n{"kind":"remove","target":"x","html":""}\n\n';
  const ops = parseOps(body);
  assert.equal(ops.length, 1);
  assert.equal(ops[0].kind, "remove");
});

test("parseOps skips invalid JSON lines", () => {
  const body = 'not json\n{"kind":"morph","target":"x","html":"y"}';
  const ops = parseOps(body);
  assert.equal(ops.length, 1);
  assert.equal(ops[0].kind, "morph");
});
