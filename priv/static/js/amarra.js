// Amarra runtime.
//
// Drive intercepts same-origin navigations and form submissions by
// default; `data-amarra-skip` opts an element out. Frame requests send
// `Amarra-Frame: <id>` and expect a fragment instead of the full layout.
//
// Built-in hooks: bulk, clipboard, dialog, dropdown, nav, password,
// reveal, theme.

export const DRIVE_HEADER = "Amarra-Drive";
export const FRAME_HEADER = "Amarra-Frame";
export const MORPH_TARGETS = ["amarra-main", "amarra-nav", "amarra-toast-host"];
export const THEME_KEY = "amarra-theme";

// -- Small DOM helpers --------------------------------------------------------

function attr(el, name) {
  return typeof el.getAttribute === "function" ? el.getAttribute(name) : null;
}

function has(el, name) {
  return typeof el.hasAttribute === "function" ? el.hasAttribute(name) : false;
}

function skipped(el) {
  return typeof el.closest === "function" ? el.closest("[data-amarra-skip]") : null;
}

function all(root, selector) {
  return Array.from(root.querySelectorAll(selector));
}

// -- Drive --------------------------------------------------------------------

export function frameTarget(el) {
  return attr(el, "data-amarra-frame");
}

export function shouldIntercept(el, origin) {
  if (!el || !el.href) return false;
  if (skipped(el)) return false;
  const target = attr(el, "target");
  if (target && target !== "_self") return false;
  if (has(el, "download")) return false;
  if (has(el, "data-amarra-frame")) return true;
  try {
    return new URL(el.href, origin).origin === origin;
  } catch {
    return false;
  }
}

async function fetchDrive(url, headers = {}) {
  const response = await fetch(url, {
    headers: { ...headers, [DRIVE_HEADER]: "true" },
  });
  return response.ok ? response.text() : null;
}

export function applyDriveHTML(html, doc = document) {
  const parsed = new DOMParser().parseFromString(html, "text/html");
  let changed = false;
  for (const id of MORPH_TARGETS) {
    const next = parsed.getElementById(id);
    const current = doc.getElementById(id);
    if (next && current) {
      current.innerHTML = next.innerHTML;
      changed = true;
    }
  }
  if (changed && typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent("amarra:morphed"));
  }
  return changed;
}

// -- Pure hook logic ----------------------------------------------------------

export function bulkSummary(count, total) {
  return {
    checked: total > 0 && count === total,
    indeterminate: count > 0 && count < total,
    count,
  };
}

export function revealMatches(value, expected) {
  return String(value) === String(expected);
}

export function pathMatches(pathname, href, origin) {
  try {
    return new URL(href, origin).pathname === pathname;
  } catch {
    return false;
  }
}

export function resolveTheme(stored, fallback = "dark") {
  return stored === "light" || stored === "dark" ? stored : fallback;
}

export function nextTheme(current) {
  return current === "light" ? "dark" : "light";
}

export function passwordState(visible, labels = {}) {
  return visible
    ? { type: "text", pressed: "true", label: labels.hide || "Hide password" }
    : { type: "password", pressed: "false", label: labels.show || "Show password" };
}

function themeClass(el) {
  return attr(el, "data-amarra-theme-class") || "light";
}

// -- Hooks --------------------------------------------------------------------

export function initBulk(root) {
  for (const container of all(root, '[amarra-hook="bulk"]')) {
    const master = container.querySelector("[data-amarra-bulk-all]");
    const bar = container.querySelector("[data-amarra-bulk-bar]");
    const countLabel = container.querySelector("[data-amarra-bulk-count]");
    const rows = () => Array.from(container.querySelectorAll("[data-amarra-bulk-row]"));
    const sync = () => {
      const boxes = rows();
      const checked = boxes.filter((box) => box.checked).length;
      const summary = bulkSummary(checked, boxes.length);
      if (master) {
        master.checked = summary.checked;
        master.indeterminate = summary.indeterminate;
      }
      if (bar) bar.hidden = summary.count === 0;
      if (countLabel) countLabel.textContent = String(summary.count);
    };
    if (master) {
      master.addEventListener("change", () => {
        for (const row of rows()) row.checked = master.checked;
        sync();
      });
    }
    for (const row of rows()) row.addEventListener("change", sync);
    sync();
  }
}

export function initClipboard(root) {
  for (const el of all(root, "[data-amarra-copy]")) {
    el.addEventListener("click", () => {
      if (navigator.clipboard) navigator.clipboard.writeText(attr(el, "data-amarra-copy") || "");
    });
  }
}

export function initDialog(root) {
  for (const container of all(root, '[amarra-hook="dialog"]')) {
    const dialog = container.querySelector("dialog[data-amarra-dialog-target]");
    if (!dialog) continue;
    let opener = null;
    dialog.setAttribute("aria-modal", "true");
    for (const button of all(container, "[data-amarra-dialog-open]")) {
      button.addEventListener("click", () => {
        opener = button;
        if (typeof dialog.showModal === "function") dialog.showModal();
      });
    }
    for (const button of all(container, "[data-amarra-dialog-close]")) {
      button.addEventListener("click", () => dialog.close());
    }
    dialog.addEventListener("close", () => {
      if (opener) opener.focus();
    });
  }
}

export function initDropdown(root) {
  for (const container of all(root, '[amarra-hook="dropdown"]')) {
    const button = container.querySelector("[data-amarra-dropdown-button]");
    const menu = container.querySelector("[data-amarra-dropdown-menu]");
    if (!button || !menu) continue;
    const close = () => {
      menu.hidden = true;
      button.setAttribute("aria-expanded", "false");
    };
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      const open = menu.hidden;
      menu.hidden = !open;
      button.setAttribute("aria-expanded", open ? "true" : "false");
    });
    for (const item of all(menu, "a,button")) item.addEventListener("click", close);
    document.addEventListener("click", (event) => {
      if (!container.contains(event.target)) close();
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") close();
    });
  }
}

export function syncNav(root, loc = window.location) {
  for (const nav of all(root, '[amarra-hook="nav"]')) {
    const on = (attr(nav, "data-amarra-nav-on") || "").split(/\s+/).filter(Boolean);
    const off = (attr(nav, "data-amarra-nav-off") || "").split(/\s+/).filter(Boolean);
    for (const link of all(nav, "a")) {
      const active = pathMatches(loc.pathname, link.href, loc.origin);
      for (const cls of on) link.classList.toggle(cls, active);
      for (const cls of off) link.classList.toggle(cls, !active);
      if (active) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    }
  }
}

export function initPassword(root) {
  for (const button of all(root, '[amarra-hook="password"]')) {
    button.setAttribute("aria-pressed", "false");
    button.addEventListener("click", () => {
      const selector = attr(button, "data-amarra-password-for");
      const field = selector
        ? document.querySelector(selector)
        : button.parentElement && button.parentElement.querySelector("input");
      if (!field) return;
      const visible = field.type === "password";
      const state = passwordState(visible, {
        show: attr(button, "data-amarra-label-show"),
        hide: attr(button, "data-amarra-label-hide"),
      });
      field.type = state.type;
      button.setAttribute("aria-pressed", state.pressed);
      if (button.textContent.trim()) button.textContent = state.label;
    });
  }
}

export function initReveal(root) {
  for (const control of all(root, '[amarra-hook="reveal"]')) {
    const selector = attr(control, "data-amarra-reveal-target");
    const target = selector ? document.querySelector(selector) : null;
    if (!target) continue;
    const expected = attr(control, "data-amarra-reveal-show");
    const sync = () => {
      target.hidden = !revealMatches(control.value, expected);
    };
    control.addEventListener("change", sync);
    sync();
  }
}

export function restoreTheme(doc = document) {
  let stored = null;
  try {
    stored = localStorage.getItem(THEME_KEY);
  } catch {
    stored = null;
  }
  if (resolveTheme(stored) === "light") doc.documentElement.classList.add("light");
}

export function initTheme(root) {
  for (const button of all(root, '[amarra-hook="theme"]')) {
    const cls = themeClass(button);
    const key = attr(button, "data-amarra-theme-key") || THEME_KEY;
    const onLabel = attr(button, "data-amarra-theme-on-label");
    const offLabel = attr(button, "data-amarra-theme-off-label");
    const lightColor = attr(button, "data-amarra-theme-color");
    const darkColor = attr(button, "data-amarra-theme-color-off");
    const meta = document.querySelector('meta[name="theme-color"]');
    const render = () => {
      const light = document.documentElement.classList.contains(cls);
      button.setAttribute("aria-pressed", light ? "true" : "false");
      if (light && onLabel) button.textContent = onLabel;
      if (!light && offLabel) button.textContent = offLabel;
      if (meta) meta.setAttribute("content", (light ? lightColor : darkColor || lightColor) || "");
    };
    button.addEventListener("click", () => {
      const light = !document.documentElement.classList.contains(cls);
      document.documentElement.classList.toggle(cls, light);
      try {
        localStorage.setItem(key, light ? "light" : "dark");
      } catch {
        /* storage unavailable */
      }
      render();
    });
    render();
  }
}

// -- Boot ---------------------------------------------------------------------

function initHooks(doc) {
  initBulk(doc);
  initClipboard(doc);
  initDialog(doc);
  initDropdown(doc);
  syncNav(doc);
  initPassword(doc);
  initReveal(doc);
  initTheme(doc);
}

export function start(doc = document) {
  doc.addEventListener("click", async (event) => {
    const anchor = event.target.closest && event.target.closest("a");
    if (!anchor || event.button !== 0 || event.metaKey || event.ctrlKey) return;
    if (!shouldIntercept(anchor, window.location.origin)) return;
    event.preventDefault();
    const html = await fetchDrive(anchor.href);
    if (html) applyDriveHTML(html, doc);
  });

  initHooks(doc);
  window.addEventListener("amarra:morphed", () => initHooks(doc));
  window.addEventListener("popstate", () => syncNav(doc));
}
