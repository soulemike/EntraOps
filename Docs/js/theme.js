(function () {
    "use strict";

    var storageKey = "entraops.theme";
    var preference = window.matchMedia("(prefers-color-scheme: dark)");

    function currentTheme() {
        return localStorage.getItem(storageKey) || (preference.matches ? "dark" : "light");
    }

    function applyTheme(theme) {
        document.documentElement.dataset.theme = theme;
    }

    function updateButton(button) {
        var dark = currentTheme() === "dark";
        button.textContent = dark ? "\u2600" : "\u263e";
        button.title = dark ? "Switch to light theme" : "Switch to dark theme";
        button.setAttribute("aria-label", button.title);
        button.setAttribute("aria-pressed", String(dark));
    }

    applyTheme(currentTheme());

    document.addEventListener("DOMContentLoaded", function () {
        var appbar = document.querySelector(".appbar");
        if (!appbar) return;

        var button = document.createElement("button");
        button.type = "button";
        button.className = "appbar-link theme-toggle";
        button.addEventListener("click", function () {
            var theme = currentTheme() === "dark" ? "light" : "dark";
            localStorage.setItem(storageKey, theme);
            applyTheme(theme);
            updateButton(button);
        });
        updateButton(button);
        appbar.appendChild(button);
    });
}());
