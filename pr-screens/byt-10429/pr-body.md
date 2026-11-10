### Why

A workload identity lets a CI job sign in to Bytebase with the job's OIDC token instead of a stored secret. Today it is created in one sheet with up to eleven fields:

- The account's name and email come first, before the user has said what will sign in.
- The provider is a dropdown, and the issuer and subject pattern are hidden under "Advanced". The subject pattern decides which jobs can sign in, yet nothing explains it.
- Editing Owner, Repository or Branch rebuilds the pattern from scratch. That silently widens a hand-written pattern such as `repo:acme-corp/deploy:environment:prod` to `repo:acme-corp/deploy:*`.
- There is no way to set GitHub's owner ID. Without it, a rule trusts the owner name alone, and anyone who registers a freed name can sign in. The server already accepts `repo:OWNER@ID/...` since #21931.
- The role is optional, so an identity can be saved that signs in and can do nothing.
- After Create the sheet closes with a toast. The email the workflow needs is not shown, and there is no way to check that the identity works.

### What changes

The sheet is replaced by a four-step dialog that asks one question per step. The layout follows the Claude Platform's "Connect workload" wizard: a left rail, one question per step, and choice cards.

| Step | Question | What the user does |
|---|---|---|
| 1. Token source | Where do your CI jobs get their token? | Picks GitHub Actions, GitLab CI or Other OIDC. Issuer URL and Audiences are prefilled and read-only, with Edit. |
| 2. Repositories | Which repositories can sign in? | Types Owner, Repository (optional) and, for GitHub, Owner ID (optional). The subject pattern is built from them and shown read-only, with Edit. |
| 3. Account | Who is it in Bytebase? | Email is prefilled as `<repo>-ci`. Display name is optional. Role defaults to GitOps Service Agent, read-only with Edit. |
| 4. Done | | Copies the email, and optionally copies a test workflow that checks the identity can sign in. |

Before and after:

| | Before | After |
|---|---|---|
| Order | Name and email first, then the provider | Token source, then repositories, then the account |
| Provider | Dropdown | Three choice cards |
| Subject pattern | Hidden under Advanced; rebuilt on every field edit | Always visible, read-only until Edit; a field edit replaces only its own part and never widens the pattern |
| GitHub owner ID | Not available | Optional field, with a box that explains the name-reuse risk |
| Role | Optional; an identity could be saved with no permission | Required in the UI, defaults to GitOps Service Agent |
| After Create | Toast, sheet closes | Done step with the email, Copy, and a test workflow |
| Edit | Same sheet; closes with a toast after save | The same four steps with a one-line "Editing ..." banner; Update on step 3 saves and shows step 4 with the test file |
| Height | Changes with content | Fixed (680px, or the window height minus 64px); only the step body scrolls |

**No API, proto, store or migration change.** Every value the old sheet stored is still stored, in the same fields. Owner, Owner ID and Repository are a view of the one stored `subject_pattern` (for example `repo:acme-corp@1234567/deploy:*`). Every identity that signs in today keeps signing in, and identities made by the old sheet open in the new dialog with no special path.

Details, decisions and state tables: `docs/design/workload-identity-creation-flow.md`.

### Screenshots

Step 1, Token source:

![Step 1, Token source](pr-screens/byt-10429/1-token-source.png)

Step 2, Repositories. The owner ID box is always shown for GitHub, so the step height never changes. It is a warning while Owner ID is empty:

![Step 2 without owner ID](pr-screens/byt-10429/2-repositories-no-owner-id.png)

and turns to info once an ID is typed. The ID is folded into the pattern:

![Step 2 with owner ID](pr-screens/byt-10429/2-repositories-with-owner-id.png)

Step 3, Account:

![Step 3, Account](pr-screens/byt-10429/3-account.png)

Step 4, Done. The test file's name is the header of its code block, next to Copy. When the External URL is not set, the file uses a placeholder URL and a warning above it says so:

![Step 4, Done](pr-screens/byt-10429/4-done.png)

Edit, step 2, with the editing banner:

![Edit, step 2](pr-screens/byt-10429/5-edit-repositories.png)

Edit, step 4 after Update. The test file is shown again, so the user can re-check sign-in after changing who can sign in:

![Edit, step 4](pr-screens/byt-10429/5-edit-done.png)

Phone (375px wide), step 2. The steps become one row on top, and only the step body scrolls:

![Phone, step 2](pr-screens/byt-10429/6-phone-repositories.png)

### Alternatives considered

UI and UX choices only. Each row says what we chose instead and why.

| Where | Alternative | Chosen instead, and why |
|---|---|---|
| Layout | Keep one form, reordered | Steps that ask one question each. A single form still shows every field at once, with no order. |
| Layout | A wide side sheet, the default in `docs/agents/frontend-ux.md` for short wizards | A centered dialog. The rail with step descriptions next to the fields needs more width than a sheet leaves. This is a recorded exception; the contract's other wizard rules still apply. |
| Layout | A full page | A dialog. Nothing needs a page: no deep link, long-running work or review. The GitOps page gets the new identity back in place, and Edit opens over the list. |
| Layout | Height that follows the content | A fixed height (680px, or the window minus 64px). The buttons never move between steps, and wording was shortened so no step scrolls. |
| Step 1 | Provider dropdown | Three choice cards with a subtitle each, as the UX contract asks for identity-provider choices. |
| Step 1 | Issuer and audiences editable from the start, or hidden under "Advanced" | Shown prefilled and read-only, with Edit. The user sees what is used but does not change it by accident. |
| Step 2 | A free-text subject pattern only | Owner, Repository and Owner ID fields that build the pattern. The pattern stays visible, read-only, with Edit for rules the fields can't express. |
| Step 2 | Branch, tag and environment fields | Dropped. They made the form long for a rare need; a pattern edit still covers them. |
| Step 2 | An owner ID warning that appears only while the ID is empty | A box that is always shown and only changes style (warning, then info), so typing never changes the step's height. |
| Step 3 | Role optional and empty by default | GitOps Service Agent prefilled, read-only, with Edit. Without a role the identity signs in and can do nothing. |
| Done | Close the dialog with a "Created" toast | A Done step with the email, Copy, and an optional test workflow. The email is the one value the workflow needs. |
| Done | A live "waiting for the first sign-in" status | Not added. It needs new backend state, and the job log already shows the result and the refusal reason. |
| Done | An "Add to an existing workflow" tab | Not added. It repeated the workflow the GitOps page already generates. |
| Done | Hide the test file when the External URL is not set | Show it with a placeholder URL and a warning with "Configure now", so the template is never lost. |
| Edit | A separate edit form | The same steps, with a one-line "Editing ..." banner. One path for every identity, old or new. |
| Edit | Close the dialog with an "Updated" toast after saving | Step 4 with "Changes saved" and the test file. Edits usually change who can sign in, and an existing identity has no other place to get the test file. |

### Test plan

- [x] New unit tests: `subjectPattern.test.ts` (cases mirror `backend/plugin/idp/wif/github_test.go`), `testWorkflow.test.ts`, `tag-input.test.tsx`, `workloadIdentity.test.ts`, `step-indicator.test.tsx`.
- [x] `WorkloadIdentityDialog.test.tsx`: GitHub create sends the pattern, audiences and default role; Other OIDC sends its JWKS URL; GitLab shows no owner ID box; owner ID in the pattern; role default, Edit and Reset; no IAM call without permission; failed role grant shown on Done; email already used; edit keeps the stored JWKS URL and pattern remainder; Update on edit shows step 4 with the test file; edit of identities with no provider or no audiences; server `InvalidArgument` sends the user to the right step.
- [x] `pnpm test` passes: Biome, the i18n, layering and UI guideline checks, `tsc --build`, the release build, and Vitest (705 files, 8,786 tests).
- [x] Walked create and edit for GitHub in the browser on desktop. Step 2 does not scroll in create or edit.
- [x] Walked create and edit at 375px wide: no horizontal overflow, only the step body scrolls.
- [x] Ran the generated test workflow from a GitHub repository against a server with a public External URL: the job signed in ([run](https://github.com/boojack/bb-gitops/actions/runs/42767366833)).

### Not in this PR

- Recording which job used an identity, in the audit log (BYT-10494).
- A live sign-in status in the dialog.
- The service account and workload identity list pages (BYT-10511).
- A GitLab group ID (GitLab's subject has no place for one).
- A Bytebase docs page for workload identity.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
