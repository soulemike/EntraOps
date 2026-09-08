# Contributing to EntraOps

Contributions are welcome through GitHub pull requests and issues. For defects, include the EntraOps version, PowerShell version, environment, sanitized logs, and reproducible steps. Do not include tenant secrets, access tokens, or unredacted sensitive tenant data.

## Contribution Terms

By submitting a contribution, you confirm that you have the right to submit it and license it under the repository's [MIT License](./LICENSE). Do not submit third-party code, documentation, images, data, or generated artifacts unless their license permits redistribution and required notices are included.

## Before Opening a Pull Request

- Search existing issues and pull requests before opening a new issue or proposing a duplicate change.
- Keep the change focused and preserve public compatibility unless a breaking change is documented.
- Add or update focused tests for behavior changes.
- Update user-facing documentation and [CHANGELOG.md](./CHANGELOG.md) for release-relevant changes.
- Run the relevant PowerShell parser, Pester tests, and formatting or static checks available in your environment.
- Follow [SECURITY.md](./SECURITY.md) for vulnerabilities; do not disclose them in a public pull request or issue.
