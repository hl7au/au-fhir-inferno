## Summary
<!-- What does this PR change, and why? -->

## Related board item
<!-- Link the tracking issue. Use a closing keyword if this PR completes it so the
     board status advances automatically (e.g. "Closes #123", or "Part of #123"). -->
Closes #

## Type
- [ ] Feature / enhancement
- [ ] Fix
- [ ] CI/CD / infra
- [ ] Docs

## Checklist
- [ ] Targets the right base branch (`development` for app/content; prod is reached via the automated promotion PR on `master`)
- [ ] If test-kit versions changed, only `Gemfile.dev` / `Gemfile.dev.lock` were touched — the prod `Gemfile` / `Gemfile.lock` are unchanged (unless intentionally promoting a release to prod)
- [ ] `quality-control` / tests pass
- [ ] Any deployment-config change was checked against dev
