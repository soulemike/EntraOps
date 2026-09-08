/* Updates the landing-page tenant banner without requiring inline script execution. */
(function () {
    "use strict";
    if (window.ENTRAOPS_EAM_DATA && typeof window.ENTRAOPS_EAM_DATA.tenantName === "string" && window.ENTRAOPS_EAM_DATA.tenantName.trim()) {
        var el = document.getElementById("tenantName");
        if (el) el.textContent = window.ENTRAOPS_EAM_DATA.tenantName.trim();
    }
})();
