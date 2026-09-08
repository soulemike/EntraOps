import { defineConfig } from "@playwright/test";

// Specs drive the documentation and offline report pages over file:// URLs, so no web server is configured.
export default defineConfig({
    workers: 1,
    forbidOnly: Boolean(process.env.CI),
    reporter: process.env.CI ? "github" : "list",
    projects: [
        {
            name: "docs",
            testDir: "Docs",
            testMatch: "**/*.browser.spec.mjs"
        },
        {
            name: "reports",
            testDir: "Reports",
            testMatch: "**/*.spec.mjs"
        }
    ]
});
