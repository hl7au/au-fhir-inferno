# Dev workflow: from a change to production

How a change to the Inferno platform goes from an idea to live on
[inferno.hl7.org.au](https://inferno.hl7.org.au). Short version:

> **Branch → PR (+ optional live preview) → merge to `master` → auto-deploy to staging →
> merge the promotion PR → production.** The [project board][board] tracks every step.

There's **one long-lived branch, `master`** (the trunk). You branch off it, open a PR, and
merge back. Everything after the merge is automated.

This guide uses a real change as the running example:
[**#285 — default the AU Core test kit to v2.0.0**][issue] (implemented in
[PR #110][pr]).

---

## The board *is* the pipeline

Each [board][board] **Status** column is a real place a change can be. Move your card as it
moves:

| Column | Meaning | Where the code is |
| --- | --- | --- |
| **Backlog** | Triaged, not started | — |
| **In progress** | Being worked on | a feature branch |
| **PR** | PR open for review (often with a live preview) | the PR branch |
| **Deployed to Dev (Reviewing)** | Merged → auto-deployed to staging | `master` → staging |
| **Verified in Development** | Checked on staging, looks good | staging |
| **Deployed to Prod** | Promotion PR merged → live | production |
| **Done** | Verified on prod, issue closed | production |

---

## The steps (with examples)

### 1. Backlog → In progress
Pick up the issue, move it to **In progress**, branch off `master`:

```bash
git checkout master && git pull
git checkout -b feat/au-core-default-v200
```

Make the change. For #285 it was one file — `web/_test_kits/au-core.md` — reordering the
suite list so `au_core_v200` comes first (the test-kit page pre-selects the first suite):

```yaml
suites:
  - title: AU Core v2.0.0   # now first → selected by default
    id: au_core_v200
  - title: AU Core v1.0.0
    id: au_core_v100
```

### 2. → PR
Push and open a PR into `master`, linking the issue so it auto-closes on merge:

```bash
git push -u origin feat/au-core-default-v200
gh pr create --base master --title "feat(au-core): default the AU Core test kit to v2.0.0" \
  --body "Closes hl7au/au-fhir-core-inferno#285"
```

Move the card to **PR**. On every PR:
- A **`quality-control`** check runs automatically (Jekyll render + Helm template + specs).
- `master` is **branch-protected**: merging needs **1 review + a green check**.

### 3. Spin up a live preview (optional, encouraged)
Add the **`preview`** label to the PR:

```bash
gh pr edit 110 --add-label preview
```

Within a few minutes a bot comment posts the URL of a fully-deployed, throwaway copy of the
whole site:

```
https://pr-110.preview.inferno.sparked-fhir.com
```

Reviewers (and stakeholders) can click it and **see the change running** — here, the AU Core
page with **v2.0.0 selected by default** — before anything merges. It's torn down
automatically when the PR is closed, merged, or the label is removed. Full details:
[preview-environments.md](preview-environments.md).

> First load can take 5–10 min (validator warmup), and a brand-new preview hostname can take
> a few minutes to resolve in DNS — wait for the bot comment to flip to ✅ **live** rather
> than refreshing early.

### 4. → Deployed to Dev (Reviewing)
Get a review, then **merge to `master`**. From here it's hands-off:
- CI builds **one** image.
- ArgoCD Image Updater picks it up and deploys it to **staging**.

Move the card to **Deployed to Dev (Reviewing)**. Staging:

```
https://development.inferno.sparked-fhir.com
```

### 5. → Verified in Development
Check the change on staging. It's the *same artifact* prod will run, so "works on staging"
means "works on prod." Happy? Move to **Verified in Development**.

### 6. → Deployed to Prod
The same merge also **opened a promotion PR automatically** (titled `Promote prod → <sha>`,
with a one-click changelog). **Merging that PR is the release gate** — a deliberate human
step. Once merged, ArgoCD ships it to production:

```
https://inferno.hl7.org.au
```

Move the card to **Deployed to Prod**.

### 7. → Done
Confirm on prod, close the issue (the `Closes #…` does this on merge), drag to **Done**. 🎉

---

## Test-kit (gem) changes

The above is for **site/harness** changes (look, content, defaults — like #285). For changes
to the **actual tests** (`au-fhir-core-inferno`, `au-ps-inferno`):

1. Make and push the change in the kit repo; note the commit SHA.
2. In an `au-fhir-inferno` branch, bump that gem's `ref:` in **`Gemfile.dev`** and regenerate
   `Gemfile.dev.lock` (Ruby 3.3.6, clean `GEM_HOME`).
3. Open a PR and add the `preview` label — the preview runs your kit change end-to-end.
4. Once the kit is released to RubyGems, bump the version in the base **`Gemfile`** for prod.

It then rides the same pipeline above. (Why two Gemfiles: `Gemfile` = released/prod pins,
`Gemfile.dev` = bleeding-edge SHAs for dev/preview — see
[cicd-overhaul-plan.md](cicd-overhaul-plan.md).)

---

## Why it works this way

- **See it before you ship it** — every PR can be a real, clickable environment.
- **Build once, deploy many** — staging and prod run the same image.
- **Prod stays gated** — nothing reaches prod without a human merging the promotion PR.
- **The board tells the truth** — a card's column is its real deployment state.

## More detail
- [preview-environments.md](preview-environments.md) — preview environments in depth.
- [cicd-overhaul-plan.md](cicd-overhaul-plan.md) — the full pipeline design and decisions.

[board]: https://github.com/orgs/hl7au/projects/2
[issue]: https://github.com/hl7au/au-fhir-core-inferno/issues/285
[pr]: https://github.com/hl7au/au-fhir-inferno/pull/110
