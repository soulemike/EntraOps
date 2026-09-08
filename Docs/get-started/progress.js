// Get Started page only: adds a "Mark as done" checkbox to every phase heading (h2) and every
// GitHub deployment step heading (h3, nested 3.1-3.8 inside section 3), persisted in localStorage.
// Checking a heading collapses (hides) the content that follows it, up to the next heading of the
// same or higher level, and dims/checkmarks the matching link in the left sidebar and the right
// "On this page" TOC. Registered at top-level (not inside a DOMContentLoaded callback) so it's
// already listening before js/app.js's own DOMContentLoaded handler renders the Markdown and
// dispatches "docs:rendered" - same convention as changelog/changelog.js.
document.addEventListener("docs:rendered", function (ev) {
    "use strict";
    if (!ev.detail || ev.detail.page !== "get-started") return;

    var STORAGE_KEY = "entraops.getStartedProgress.v1";
    var TRACKED = [
        { id: "try-it-with-zero-configuration", level: 2 },
        { id: "phase-2-verify-output", level: 2 },
        { id: "deploy-with-github", level: 2 },
        { id: "step-1-create-your-repository-from-this-template", level: 3 },
        { id: "step-2", level: 3 },
        { id: "step-3", level: 3 },
        { id: "step-4", level: 3 },
        { id: "step-5", level: 3 },
        { id: "step-6-review-and-customize-the-entraopsconfig-file", level: 3 },
        { id: "step-7", level: 3 },
        { id: "step-8", level: 3 },
        { id: "phase-4-ingest-to-sentinel", level: 2 },
        { id: "phase-5-automate-protection", level: 2 },
        { id: "phase-6-full-tiering-rollout", level: 2 },
        { id: "optional-tenant-governance", level: 2 }
    ];

    function loadState() {
        try {
            return JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}") || {};
        } catch (e) {
            return {};
        }
    }
    function saveState(state) {
        try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
        } catch (e) { /* localStorage unavailable (private mode/quota) - progress just won't persist */ }
    }

    var state = loadState();
    var entries = [];

    TRACKED.forEach(function (t) {
        var heading = document.getElementById(t.id);
        if (!heading) return;

        // Collect every sibling up to (not including) the next heading of the same or higher
        // level, and move it into a collapsible wrapper right after the heading.
        var body = document.createElement("div");
        body.className = "eo-progress-body";
        var next = heading.nextElementSibling;
        var toMove = [];
        while (next && !(/^H[1-6]$/.test(next.tagName) && parseInt(next.tagName.slice(1), 10) <= t.level)) {
            toMove.push(next);
            next = next.nextElementSibling;
        }
        heading.insertAdjacentElement("afterend", body);
        toMove.forEach(function (el) { body.appendChild(el); });

        var label = document.createElement("label");
        label.className = "eo-progress-check";
        var input = document.createElement("input");
        input.type = "checkbox";
        var span = document.createElement("span");
        span.textContent = "Mark as done";
        label.appendChild(input);
        label.appendChild(span);
        heading.appendChild(label);

        entries.push({ id: t.id, heading: heading, body: body, input: input });
    });

    function markLinks(id, done) {
        document.querySelectorAll('.nav-subitem[href="#' + id + '"], .toc a[href="#' + id + '"]').forEach(function (a) {
            a.classList.toggle("eo-done", done);
        });
    }

    function applyDone(entry, done) {
        entry.body.hidden = done;
        entry.heading.classList.toggle("eo-progress-done", done);
        markLinks(entry.id, done);
    }

    entries.forEach(function (entry) {
        var done = !!state[entry.id];
        entry.input.checked = done;
        applyDone(entry, done);
        entry.input.addEventListener("change", function () {
            state[entry.id] = entry.input.checked;
            saveState(state);
            applyDone(entry, entry.input.checked);
        });
    });

    // The right "On this page" TOC is built by js/app.js right after it dispatches this same
    // "docs:rendered" event, i.e. after this handler returns - defer the initial TOC marking
    // until that synchronous render pass has finished.
    setTimeout(function () {
        entries.forEach(function (entry) { markLinks(entry.id, !!state[entry.id]); });
    }, 0);
});
