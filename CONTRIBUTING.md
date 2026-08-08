# Contributing

Thanks for helping improve MemoryRouter's public integration and release resources.

## Good contributions

- documentation corrections and clearer examples;
- fixes for broken or stale links;
- reproducible fixes to the legacy patch helpers; and
- compatibility notes for published release assets.

For larger changes, open an issue first so scope and current product behavior can be confirmed before implementation.

## Before opening a pull request

1. Base the work on the repository's default `main` branch.
2. Keep the change focused and avoid unrelated formatting churn.
3. Use placeholders and synthetic data in examples.
4. Never commit Memory Keys, provider credentials, OAuth tokens, customer data, or private memory content.
5. Validate shell changes with `bash -n patches/patch-openclaw.sh`.
6. Check every new public link resolves successfully.

Product and account support belongs at [hello@memoryrouter.ai](mailto:hello@memoryrouter.ai). Security reports must follow [SECURITY.md](SECURITY.md).
