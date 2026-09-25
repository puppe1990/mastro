import { strict as assert } from "node:assert";
import test from "node:test";
import { csrfToken, frameTarget, shouldIntercept } from "./amarra.js";

const ORIGIN = "https://app.test";

function fakeAnchor(overrides = {}) {
  return {
    href: "https://app.test/posts",
    getAttribute: () => null,
    hasAttribute: () => false,
    closest: () => null,
    ...overrides,
  };
}

function fakeDocument(content) {
  return {
    querySelector: (selector) =>
      selector === 'meta[name="csrf-token"]'
        ? {
            getAttribute: (name) => (name === "content" ? content : null),
          }
        : null,
  };
}

test("intercepts a plain same-origin anchor by default", () => {
  assert.equal(shouldIntercept(fakeAnchor(), ORIGIN), true);
});

test("does not intercept anchors opted out with data-amarra-skip", () => {
  const anchor = fakeAnchor({ closest: (sel) => (sel === "[data-amarra-skip]" ? {} : null) });
  assert.equal(shouldIntercept(anchor, ORIGIN), false);
});

test("does not intercept cross-origin anchors", () => {
  assert.equal(shouldIntercept(fakeAnchor({ href: "https://other.test/x" }), ORIGIN), false);
});

test("does not intercept anchors with a non-self target", () => {
  const anchor = fakeAnchor({ getAttribute: (name) => (name === "target" ? "_blank" : null) });
  assert.equal(shouldIntercept(anchor, ORIGIN), false);
});

test("does not intercept downloads", () => {
  const anchor = fakeAnchor({ hasAttribute: (name) => name === "download" });
  assert.equal(shouldIntercept(anchor, ORIGIN), false);
});

test("always intercepts data-amarra-frame anchors", () => {
  const anchor = fakeAnchor({
    href: "https://other.test/cart",
    hasAttribute: (name) => name === "data-amarra-frame",
    getAttribute: (name) => (name === "data-amarra-frame" ? "cart" : null),
  });
  assert.equal(shouldIntercept(anchor, ORIGIN), true);
});

test("frameTarget reads the data-amarra-frame attribute", () => {
  const anchor = fakeAnchor({
    getAttribute: (name) => (name === "data-amarra-frame" ? "cart" : null),
  });
  assert.equal(frameTarget(anchor), "cart");
  assert.equal(frameTarget(fakeAnchor()), null);
});

test("csrfToken reads the csrf-token meta tag", () => {
  assert.equal(csrfToken(fakeDocument("tok-123")), "tok-123");
});

test("csrfToken is empty when the page has no meta tag", () => {
  assert.equal(csrfToken(fakeDocument(null)), "");
  assert.equal(csrfToken({}), "");
});
