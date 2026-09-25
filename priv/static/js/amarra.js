// Amarra Drive client.
//
// Drive intercepts same-origin navigations and form submissions by
// default; `data-amarra-skip` opts an element out. Frame requests send
// `Amarra-Frame: <id>` and expect a fragment instead of the full layout.

export const DRIVE_HEADER = "Amarra-Drive";
export const FRAME_HEADER = "Amarra-Frame";
export const MORPH_TARGETS = ["amarra-main", "amarra-nav", "amarra-toast-host"];

function attr(el, name) {
  return typeof el.getAttribute === "function" ? el.getAttribute(name) : null;
}

function has(el, name) {
  return typeof el.hasAttribute === "function" ? el.hasAttribute(name) : false;
}

function skipped(el) {
  return typeof el.closest === "function" ? el.closest("[data-amarra-skip]") : null;
}

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

export function start(doc = document) {
  doc.addEventListener("click", async (event) => {
    const anchor = event.target.closest && event.target.closest("a");
    if (!anchor || event.button !== 0 || event.metaKey || event.ctrlKey) return;
    if (!shouldIntercept(anchor, window.location.origin)) return;
    event.preventDefault();
    const html = await fetchDrive(anchor.href);
    if (html) applyDriveHTML(html, doc);
  });
}
