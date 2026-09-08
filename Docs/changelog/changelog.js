// Changelog-specific: CHANGELOG.md version headings look like "[1.0.0] - YYYY-MM-DD".
// DocsMD's generic slugify() would turn that into an ugly/unstable id, so once the Markdown
// has been rendered (see the "docs:rendered" event dispatched by js/app.js, which fires
// *before* the shared "on this page" TOC is built from the resulting heading ids) reassign
// each version heading a clean, stable id ("v1-0-0") and use it to populate the "Jump to
// version" dropdown and support deep-linking to a version via URL hash
// (e.g. changelog/index.html#v1-0-0).
document.addEventListener("docs:rendered", function (ev) {
    if (!ev.detail || ev.detail.page !== "changelog") return;
    var article = document.querySelector('.prose[data-md="changelog"]');
    var select = document.getElementById("versionJump");
    if (!article) return;

    var versions = [];
    article.querySelectorAll("h2[id]").forEach(function (h) {
        var m = h.textContent.match(/^\[(\d[\w.\-]*)\]/);
        if (!m) return;
        var id = "v" + m[1].replace(/\./g, "-");
        h.id = id;
        versions.push({ id: id, label: h.textContent.trim() });
    });

    if (select && versions.length) {
        versions.forEach(function (v) {
            var opt = document.createElement("option");
            opt.value = v.id;
            opt.textContent = v.label;
            select.appendChild(opt);
        });
        select.addEventListener("change", function () {
            if (!select.value) return;
            var target = document.getElementById(select.value);
            if (target) {
                history.replaceState(null, "", "#" + select.value);
                target.scrollIntoView({ behavior: "smooth", block: "start" });
            }
        });
    }
    // Deep-linking to a version via URL hash (e.g. #v1-0-0) is handled generically by
    // js/app.js's own post-render hash-scroll, which runs after this listener reassigns the
    // clean version ids above.
});
