## Summary

Describe the problem and the change. Link the related issue when one exists.

## Validation

List the focused tests, parser checks, linting, or manual validation performed.

## Checklist

- [ ] I searched existing issues and pull requests before proposing this change.
- [ ] I kept the change focused and documented any compatibility impact.
- [ ] I added or updated a focused Pester test where behavior changed and verified that it covers this change.
- [ ] I updated the EntraOps Docs, or confirmed that this change does not require documentation.
- [ ] If this change adds or changes an `EntraOpsConfig.json` property, I updated the Configuration Wizard and ensured `New-EntraOpsConfigFile` writes a documented default value.
- [ ] If I changed `Docs/content/*.md` or `CHANGELOG.md`, I regenerated `Docs/data/content.js` with `Docs/Update-EntraOpsDocsContent.ps1`.
- [ ] If I added or changed a public cmdlet or parameter, I updated its comment-based help and `EntraOps.psd1` exports where applicable.
- [ ] I updated `CHANGELOG.md` when this change is release-relevant.
- [ ] I removed secrets, tokens, personal data, and tenant-sensitive data from this pull request.
- [ ] I followed `SECURITY.md` for vulnerabilities instead of disclosing them publicly.
