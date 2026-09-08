/* Shared offline reporting helpers. */
(function () {
    "use strict";

    function csvValue(value) {
        var text = value == null ? "" : (typeof value === "object" ? JSON.stringify(value) : String(value));
        // Neutralise spreadsheet formula injection before RFC-4180 quoting. Excel and Sheets execute
        // a cell whose text begins with = + - @ (or a leading tab/CR), and these exports carry tenant
        // display names, which are attacker-influenceable (a guest can set their own). A leading
        // apostrophe forces the cell to be treated as literal text. Same guard as the in-app CSV
        // writers (EamDashboard/TierBreachAnalyzer/AccessPathMap csvCell).
        if (/^[=+\-@\t\r]/.test(text)) text = "'" + text;
        return '"' + text.replace(/"/g, '""') + '"';
    }

    function download(name, type, content) {
        var link = document.createElement("a");
        var href = URL.createObjectURL(new Blob([content], { type: type }));
        link.href = href;
        link.download = name;
        document.body.appendChild(link);
        link.click();
        link.remove();
        // Revoking immediately after click() can cancel the download in some browsers.
        setTimeout(function () { URL.revokeObjectURL(href); }, 1000);
    }

    function exportRows(name, rows) {
        var safeRows = Array.isArray(rows) ? rows : [];
        var keys = Object.keys(safeRows.reduce(function (all, row) {
            Object.keys(row || {}).forEach(function (key) { all[key] = true; });
            return all;
        }, {}));
        var csv = keys.map(csvValue).join(",") + "\n" + safeRows.map(function (row) {
            return keys.map(function (key) { return csvValue(row[key]); }).join(",");
        }).join("\n");
        download(name + ".csv", "text/csv;charset=utf-8", csv);
        download(name + ".json", "application/json;charset=utf-8", JSON.stringify(safeRows, null, 2));
    }

    function freshnessText(data, snapshot) {
        if (!data || !data.generatedAt) return "Dataset generation time unavailable";
        var text = "Generated " + (typeof fmtDate === "function" ? fmtDate(data.generatedAt) : data.generatedAt);
        if (snapshot && snapshot.commitDate) text += " · snapshot " + (typeof fmtDate === "function" ? fmtDate(snapshot.commitDate) : snapshot.commitDate);
        if (snapshot && snapshot.workingTree) text += " · working tree";
        return text;
    }

    function flowDeepLink(flowId, reportPath) {
        return (reportPath || "") + "#flow=" + encodeURIComponent(flowId);
    }

    function flowReferenceFromHash() {
        var match = /^#flow=([^&]+)$/.exec(window.location.hash || "");
        if (!match) return null;
        try { return decodeURIComponent(match[1]); } catch (_) { return null; }
    }

    function reviewStoreKey(reportId) { return "entraops.review." + reportId; }

    // Parsed review-map cache: reviewControl runs once per rendered row (hundreds of rows per
    // render in the risk/flag lists), and a synchronous localStorage.getItem + JSON.parse per
    // row dominated interaction cost. The cache is invalidated on our own writes and on
    // cross-tab storage events, so behavior is unchanged.
    var reviewMapCache = {};
    if (typeof window !== "undefined" && window.addEventListener) {
        window.addEventListener("storage", function (ev) {
            if (ev && ev.key && String(ev.key).indexOf("entraops.review.") === 0) reviewMapCache = {};
        });
    }
    function readReviewMap(reportId) {
        if (!(reportId in reviewMapCache)) {
            try { reviewMapCache[reportId] = JSON.parse(localStorage.getItem(reviewStoreKey(reportId)) || "{}"); }
            catch (_) { reviewMapCache[reportId] = null; }
        }
        return reviewMapCache[reportId];
    }

    function getReviewStatus(reportId, findingId, defaultStatus) {
        var values = readReviewMap(reportId);
        if (values === null) return defaultStatus || "Open";
        var status = values[findingId] || defaultStatus || "Open";
        return status === "New" ? "Open" : status;
    }

    function setReviewStatus(reportId, findingId, status) {
        try {
            var values = JSON.parse(localStorage.getItem(reviewStoreKey(reportId)) || "{}");
            values[findingId] = status;
            localStorage.setItem(reviewStoreKey(reportId), JSON.stringify(values));
            reviewMapCache[reportId] = values;
        } catch (_) { /* Local storage can be unavailable in hardened browsers. */ }
    }

    function reviewControl(reportId, findingId, defaultStatus, replaceOpenWithDefault) {
        var status = getReviewStatus(reportId, findingId, defaultStatus);
        if (replaceOpenWithDefault && status === "Open" && defaultStatus) status = defaultStatus;
            return '<select class="review-status" data-review-report="' + encodeURIComponent(reportId) + '" data-review-finding="' + encodeURIComponent(findingId) + '" aria-label="Review status"><option' + (status === "Open" ? " selected" : "") + '>Open</option><option' + (status === "Accepted risk" ? " selected" : "") + '>Accepted risk</option><option' + (status === "Remediated" ? " selected" : "") + '>Remediated</option></select>';
    }

    function bindReviewControls(container, onChange) {
        container.querySelectorAll("[data-review-report]").forEach(function (control) {
            control.addEventListener("change", function () {
                setReviewStatus(decodeURIComponent(control.getAttribute("data-review-report")), decodeURIComponent(control.getAttribute("data-review-finding")), control.value);
                if (onChange) onChange();
            });
        });
    }

    window.EntraOpsReportUtils = {
        exportRows: exportRows,
        freshnessText: freshnessText,
        flowDeepLink: flowDeepLink,
        flowReferenceFromHash: flowReferenceFromHash,
        getReviewStatus: getReviewStatus,
        setReviewStatus: setReviewStatus,
        reviewControl: reviewControl,
        bindReviewControls: bindReviewControls
    };
})();
