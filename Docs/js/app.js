// EntraOps Docs - shared behavior (mobile nav toggle, active nav highlighting,
// auto-generated "on this page" table of contents with scrollspy).
(function () {
    "use strict";

    function onReady(fn) {
        if (document.readyState !== "loading") fn();
        else document.addEventListener("DOMContentLoaded", fn);
    }

    function esc(s) {
        return String(s == null ? "" : s)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    onReady(function () {
        var navToggle = document.getElementById("navToggle");
        var nav = document.getElementById("nav");
        if (navToggle && nav) {
            navToggle.addEventListener("click", function () {
                nav.classList.toggle("open");
            });
            nav.addEventListener("click", function (ev) {
                if (ev.target.closest("a")) nav.classList.remove("open");
            });
        }

        // Highlight the current top-level nav item based on <body data-page="...">
        // (set on each page's <body> tag - CSP (default-src 'self') blocks inline scripts,
        // so this can't be a `window.DOCS_PAGE = "..."` inline <script> instead).
        var current = document.body.getAttribute("data-page");
        if (current) {
            document.querySelectorAll(".nav-item.top[data-page]").forEach(function (el) {
                if (el.getAttribute("data-page") === current) el.classList.add("active");
            });
        }

        // Render the page's Markdown content (window.EODOCS_CONTENT[DOCS_PAGE], embedded by
        // Docs/Update-EntraOpsDocsContent.ps1 from Docs/content/*.md or CHANGELOG.md) into the
        // article container, using the shared DocsMD renderer (Docs/js/markdown.js). All
        // EntraOps Docs content is authored/maintained as Markdown - never hand-written HTML.
        var article = document.querySelector(".prose[data-md]");
        if (article && window.DocsMD && window.EODOCS_CONTENT) {
            var key = article.getAttribute("data-md");
            var md = window.EODOCS_CONTENT[key];
            if (md) {
                // Every page's own page-head already renders an <h1> title, so strip a
                // single leading "# Title" line from the Markdown source before rendering -
                // otherwise it would render again as a duplicate heading right below. The
                // leading H1 is kept in the .md source files (and CHANGELOG.md) on purpose,
                // since it's still wanted when that Markdown file is read standalone (e.g. on
                // GitHub) rather than through this page.
                md = md.replace(/^\s*#\s+.+(?:\r?\n)+/, "");
            }
            article.innerHTML = md ? DocsMD.render(md) : "<p><em>Content not found: " + esc(key) + "</em></p>";
            document.dispatchEvent(new CustomEvent("docs:rendered", { detail: { page: key } }));
        }

        // Auto-build "On this page" TOC from the article's heading(s). Defaults to h2+h3;
        // a narrower page (e.g. Changelog, which only wants its many version h2's, not every
        // repeated "Added"/"Changed"/"Fixed" h3) can opt out of h3 via [data-toc-levels="h2"].
        var toc = document.getElementById("toc");
        var tocLevels = toc && toc.getAttribute("data-toc-levels") === "h2" ? "h2[id]" : "h2[id], h3[id]";
        if (toc && article) {
            var headings = article.querySelectorAll(tocLevels);
            if (headings.length === 0) {
                toc.hidden = true;
            } else {
                var list = document.createElement("div");
                headings.forEach(function (h) {
                    var a = document.createElement("a");
                    a.href = "#" + h.id;
                    a.textContent = h.textContent;
                    if (h.tagName === "H3") a.classList.add("h3");
                    list.appendChild(a);
                });
                var label = document.createElement("div");
                label.className = "toc-label";
                label.textContent = "On this page";
                toc.appendChild(label);
                toc.appendChild(list);

                var links = Array.prototype.slice.call(list.querySelectorAll("a"));
                // Also highlight the matching left-sidebar nav-subitem (hand-authored per page,
                // so not every observed heading necessarily has one - guarded with a null check).
                var navLinks = Array.prototype.slice.call(document.querySelectorAll(".nav-subitem"));
                var io = new IntersectionObserver(function (entries) {
                    entries.forEach(function (entry) {
                        var link = list.querySelector('a[href="#' + entry.target.id + '"]');
                        var navLink = document.querySelector('.nav-subitem[href="#' + entry.target.id + '"]');
                        if (entry.isIntersecting) {
                            links.forEach(function (l) { l.classList.remove("active"); });
                            if (link) link.classList.add("active");
                            navLinks.forEach(function (l) { l.classList.remove("active"); });
                            if (navLink) navLink.classList.add("active");
                        }
                    });
                }, { rootMargin: "-15% 0px -70% 0px" });
                headings.forEach(function (h) { io.observe(h); });
            }
        }

        // Scroll to the requested anchor once the Markdown-rendered heading ids actually
        // exist. The browser's own initial "scroll to URL fragment" behavior runs before this
        // script populates `article` (it's empty at parse time), so a direct/cross-page link
        // like get-started/index.html#deploy-with-github would otherwise silently land at the
        // top of the page instead of the target section.
        if (location.hash) {
            var target = document.getElementById(location.hash.slice(1));
            if (target) target.scrollIntoView({ block: "start" });
        }
    });
})();
