import { expect, test } from "@playwright/test";
import { cp, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const dashboardSourceDir = fileURLToPath(new URL(".", import.meta.url));
const reportsSourceDir = fileURLToPath(new URL("..", import.meta.url));
let fixtureRoot;
let dashboardUrl;

// The row count has to exceed the table's own max-height so the sticky-header assertion
// below actually scrolls vertically; it stays under the dashboard's default page size.
const fixtureObjects = Array.from({ length: 40 }, (_, index) => ({
    objectId: `00000000-0000-0000-0000-${String(index + 1).padStart(12, "0")}`,
    objectTenantId: "00000000-0000-0000-0000-000000000000",
    objectType: "user",
    objectSubType: "Member",
    objectDisplayName: `Test identity ${index + 1}`,
    objectUserPrincipalName: `test.identity.${index + 1}@contoso.com`,
    objectAdminTierLevel: "1",
    objectAdminTierLevelName: "ManagementPlane",
    syncSource: "Cloud-Only",
    restrictedManagement: "Not available",
    restrictedManagementByAadRole: false,
    restrictedManagementByRAG: false,
    restrictedManagementByRMAU: false,
    assignedAdministrativeUnits: [],
    associatedWorkAccount: [],
    privilegedType: "Local Identities",
    outsideOfHomeTenant: false,
    roleSystem: "EntraID",
    classification: [
        {
            adminTierLevel: "1",
            adminTierLevelName: "ManagementPlane",
            service: "Identity"
        }
    ],
    controlPlaneReasoning: [],
    roleAssignments: []
}));

const fixtureData = {
    tenantName: "Contoso test tenant",
    generatedAt: "2026-01-01T00:00:00Z",
    changeSetId: "browser-test-fixture",
    notifications: [],
    linkedIdentityDisplayNames: {},
    objects: fixtureObjects
};

test.beforeAll(async () => {
    fixtureRoot = await mkdtemp(join(tmpdir(), "entraops-eam-dashboard-browser-"));
    const reportsFixtureDir = join(fixtureRoot, "Reports");
    const dashboardFixtureDir = join(reportsFixtureDir, "EamDashboard");

    await mkdir(reportsFixtureDir, { recursive: true });
    await cp(dashboardSourceDir, dashboardFixtureDir, {
        recursive: true,
        filter: (source) => {
            const sourceRelativePath = relative(dashboardSourceDir, source);
            if (!sourceRelativePath) return true;
            const firstSegment = sourceRelativePath.split(sep)[0];
            return firstSegment !== "data" &&
                !sourceRelativePath.endsWith(".spec.mjs") &&
                sourceRelativePath !== ".DS_Store";
        }
    });
    await cp(join(reportsSourceDir, "shared"), join(reportsFixtureDir, "shared"), { recursive: true });

    const dataDir = join(dashboardFixtureDir, "data");
    await mkdir(dataDir, { recursive: true });
    await writeFile(
        join(dataDir, "eam-dashboard-data.js"),
        `window.ENTRAOPS_EAM_DATA = ${JSON.stringify(fixtureData)};\n`,
        "utf8"
    );

    dashboardUrl = pathToFileURL(join(dashboardFixtureDir, "index.html")).href;
});

test.afterAll(async () => {
    if (fixtureRoot) await rm(fixtureRoot, { recursive: true, force: true });
});

for (const viewport of [
    { name: "desktop", width: 1472, height: 768 },
    { name: "mobile", width: 390, height: 844 }
]) {
    test(`${viewport.name} keeps the dashboard shell and wide tables inside the viewport`, async ({ page }) => {
        await page.setViewportSize(viewport);
        await page.goto(dashboardUrl);
        await expect(page.locator("#assetTable tbody tr").first()).toBeVisible();

        const layout = await page.evaluate(() => {
            const main = document.querySelector(".main").getBoundingClientRect();
            const nav = document.querySelector(".nav").getBoundingClientRect();
            const tableScroll = document.querySelector("#secAssets .eam-scroll");
            const scrollBounds = tableScroll.getBoundingClientRect();

            return {
                documentOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
                mainLeft: main.left,
                navRight: nav.right,
                scrollLeft: scrollBounds.left,
                scrollRight: scrollBounds.right,
                scrollClientWidth: tableScroll.clientWidth,
                scrollWidth: tableScroll.scrollWidth
            };
        });

        expect(layout.documentOverflow).toBeLessThanOrEqual(1);
        expect(layout.mainLeft).toBeGreaterThanOrEqual(layout.navRight - 1);
        expect(layout.scrollLeft).toBeGreaterThanOrEqual(layout.mainLeft - 1);
        expect(layout.scrollRight).toBeLessThanOrEqual(viewport.width + 1);
        expect(layout.scrollWidth).toBeGreaterThan(layout.scrollClientWidth);

        await page.locator("html").evaluate((element) => {
            element.dataset.theme = "dark";
        });
        await page.locator("#assetTable tbody tr.asset-row").first().click();
        const selectedRowColors = await page.locator("#assetTable tbody tr.sel-row").evaluate((row) => ({
            row: getComputedStyle(row).backgroundColor,
            actionCell: getComputedStyle(row.cells[12]).backgroundColor
        }));
        expect(selectedRowColors.actionCell).toBe(selectedRowColors.row);

        const stickyHeaderDelta = await page.locator("#secAssets .eam-scroll").evaluate((tableScroll) => {
            tableScroll.scrollLeft = 500;
            tableScroll.scrollTop = 300;
            const scrollTop = tableScroll.getBoundingClientRect().top;
            const headerTop = tableScroll.querySelector("thead th").getBoundingClientRect().top;
            return Math.abs(headerTop - scrollTop);
        });

        expect(stickyHeaderDelta).toBeLessThanOrEqual(1);
    });
}
