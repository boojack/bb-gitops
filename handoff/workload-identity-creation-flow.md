# Workload Identity creation flow

Status: proposed · 2026-11-09 · [BYT-10429](https://linear.app/bytebase/issue/BYT-10429) · builds on the BYT-10349 server fix, [#21931] (merged)

A workload identity lets a CI job sign in to Bytebase with the job's OIDC token instead of a stored
secret. Today it is created in one sheet with up to eleven fields: the provider is a dropdown, the
issuer and subject pattern hide under "Advanced", and nothing explains what any field binds to.
The role is optional, so an identity can be saved that signs in and can do nothing. After Create
the sheet closes, and nothing says what to do next.
**The sheet becomes a four-step dialog that asks one question per step: where the tokens come
from, which repositories may sign in, and who the identity is in Bytebase. It then ends on the
email the workflow uses. Every value the old sheet stored is still stored, in the same fields, and
every identity that signs in today keeps signing in.** Frontend only: no proto, API, store or
migration change.

The step layout follows the Claude Platform's "Connect workload" wizard (left rail, one question
and one sentence per step, choice cards). The mock-up (v42, with desktop, phone and variant
screens) is kept outside the repo.

## Problem

Verified on `main` at `f52ecbc`, in `CreateWorkloadIdentitySheet`
(`frontend/src/components/CreateWorkloadIdentitySheet.tsx`):

- **One long form, in an order that doesn't match the task.** The fields are: Name, Email, Roles,
  Platform, Owner, Repository, Allowed branches/tags (GitLab), Branch, Audience. Behind
  "Advanced" are Issuer URL and Subject pattern. Other OIDC shows Issuer URL, JWKS URL and Subject
  pattern instead. The account's name and email come first, before the user has said what will
  sign in.
- **The provider is a dropdown.** The UX contract (`docs/agents/frontend-ux.md`, Choice Controls)
  asks for visible choices with descriptions when choosing an identity-provider type.
- **What signs in is hidden.** The subject pattern decides which jobs may sign in, and it sits
  under Advanced. Editing Owner, Repository or Branch recomputes it from scratch. That widens a
  hand-written pattern such as `repo:o/r:environment:prod` to `repo:o/r:*` (comment at lines 252 to 259).
- **No owner ID.** GitHub moves repositories created, renamed or transferred after 2026-07-15 to
  ID-based subjects (`repo:owner@123/name@456:...`). #21931 makes the server accept both formats
  for a name pattern, and it also accepts `repo:owner@ID/...`, which survives the owner name being
  freed and taken over. The form has no way to set the ID.
- **No role is allowed.** Roles are optional, and hidden entirely when the user cannot set IAM
  policy. The identity is created, signs in, and has no permission.
- **No next step.** Create shows a "Created" toast and closes the sheet. The email the workflow
  needs is not shown, and there is no way to check that the identity works.

## Principle

> Ask for what the user knows, in the order they know it. Prefill what Bytebase knows, and show
> it read-only until the user chooses to change it. Store exactly what the old form stored, so one
> path serves every identity, old or new.

## Decisions

**D1 · Four steps in a centered dialog.** Steps: Token source, Repositories, Account, Done. A left
rail shows each step's title and one-line description ("Select the CI provider", "Match owner and
repository", "Email and role", "Use it in your workflow"). Finished steps turn green and the line
between them follows. The footer is fixed: Back (secondary, from step 2), Cancel, and
Continue / Create (primary). Each step is validated before Continue, with errors beside the
fields, and Back keeps what was entered. The dialog has a fixed height: 680px, or the window
height minus 64px when the window is smaller. The buttons stay in the same place on every step; a
short step leaves space above them, and a long one scrolls inside the step body. The scroll area
leaves room for focus rings, so no field border is cut. This is a `Dialog`, not the wide sheet that the UX
contract suggests for short wizards. The rail with descriptions and the side-by-side layout follow
the Claude Platform wizard that the flow is modelled on, and a side sheet leaves the form too
little width beside the rail. All other wizard rules in the contract apply. Rejected: one page with
sections; it keeps today's problem of a long form with no order.

**D2 · Step 1, Token source: "Where do your CI jobs get their token?"** Three choice cards
(`RadioGroup` with choice-card styling): GitHub Actions, GitLab CI, Other OIDC. GitHub Actions is
selected when the dialog opens for a new identity. Then, for the chosen provider:

- **GitHub and GitLab.** One sentence, then Issuer URL and Audiences, prefilled from today's
  `PLATFORM_PRESETS` (`https://token.actions.githubusercontent.com`, `https://gitlab.com`,
  audience `bytebase`). Both are shown read-only, each with an Edit link. Edit turns Issuer URL
  into an input with the hint "Change it only for GitHub Enterprise Server, GHE.com, or an
  enterprise custom issuer." Edit turns Audiences into a tag input: Enter adds a value, × removes
  one, at least one is required, and Reset restores `bytebase`.
- **Other OIDC.** Issuer URL (required), Audiences (required, tag input) and JWKS URL (optional,
  last). All are editable from the start, because there is no preset. JWKS URL hint: "Where
  Bytebase downloads the issuer's public keys. Leave blank if the issuer publishes
  `/.well-known/openid-configuration`." GitHub and GitLab never show JWKS URL, because both publish
  discovery documents.

Changing the provider resets the issuer, audiences, JWKS URL and subject pattern, as today.

**D3 · Step 2, Repositories: the fields fold into `subject_pattern`.** No new stored field. The
fields are a view of the one stored pattern.

- **GitHub.** Owner (required), Repository (optional, blank means any repository of the owner),
  Owner ID (optional, digits only). Owner ID hint: "Get it with `gh api users/<owner> --jq .id`.
  The ID stays the same when the account is renamed."
- **GitLab.** Group (required), Project (optional). There is no group ID: GitLab's subject has no
  place for one.
- **Other OIDC.** The step is titled "Which tokens can sign in?" and has only Subject pattern
  (required, editable), with the hint "Must equal the token's `sub`. End with `*` to match a
  prefix."

The pattern is built from the fields:

| Fields | Pattern |
|---|---|
| Owner `acme-corp` | `repo:acme-corp/*` |
| Owner, Repository `deploy` | `repo:acme-corp/deploy:*` |
| Owner, Owner ID `111`, Repository | `repo:acme-corp@111/deploy:*` |
| Group `acme`, Project `deploy` | `project_path:acme/deploy:*` |

It follows the grammar the server parses in `backend/plugin/idp/wif/github.go`
(`repo:OWNER[@OWNER_ID]/*` or `repo:OWNER[@OWNER_ID]/REPO[@REPO_ID]:REST`). Since #21931, every
GitHub pattern in the table matches tokens in both subject formats.

Below the fields, Subject pattern is shown read-only with an Edit link and the hint "Built from the
fields above and read-only. Edit it only for a rule the fields can't express, such as one
environment." After Edit:

- Typing in the pattern updates the fields from it.
- Changing a field afterwards replaces only that field's part and keeps the rest of the pattern
  (for example `:environment:prod`). It never widens the pattern.
- Reset rebuilds the pattern from the fields.
- A pattern the fields cannot read, for example one that doesn't start with `repo:OWNER/`,
  disables the fields. The pattern is then matched by prefix only, as today.
- A pattern that names one environment shows a warning: only jobs with that `environment:` can
  sign in, and jobs without one, such as the GitOps review job, will fail.

While Owner ID is empty, GitHub shows a warning with a title and a body. Title: "This rule trusts
the name acme-corp alone". Body: "If the acme-corp account is renamed or deleted, GitHub frees the
name and anyone can register it. Workflows in their repositories would then match this rule and
sign in to Bytebase as this identity. Add the owner ID to tie the rule to this account." The
warning ends with the link "GitHub changelog: immutable subject claims", which opens GitHub's
announcement in a new tab: https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/. It is the one external link in the
dialog, because the risk is GitHub's behavior and GitHub's post explains it.
There is no field for the branch, tag, event or environment. Today's Branch and GitLab
"Allowed branches/tags" fields are dropped; a pattern edit still expresses them (D9).

**D4 · Step 3, Account: "Who is it in Bytebase?"**

- **Email** (required). The name is prefilled from the repository name plus `-ci` (for example
  `deploy-ci`), or from the owner name plus `-ci` when Repository is blank. The fixed suffix is shown beside it (`@<project>.workload.bytebase.com`, or
  `@workload.bytebase.com` at workspace level). A debounced `fetchWorkloadIdentity` lookup shows
  "Already used" before Create. A deleted identity also counts as used, because the server refuses
  the email. Hint: "Your workflow signs in with this email. It cannot be changed later."
- **Display name** (optional). Blank uses the email name, as today.
- **Role** (required, last). Prefilled with GitOps Service Agent (`roles/gitopsServiceAgent`) and
  shown read-only with an Edit link. It comes last for the same reason Subject pattern does in
  step 2: it is a prefilled value that the user rarely changes. Edit turns it into the shared
  `RoleSelect` in single-select mode (`multiple={false}`, with `scope="project"` in a project),
  and Reset puts the default back. The default is the same at project and workspace level. At
  workspace level the hint says the role applies in every project. A user without
  `bb.projects.setIamPolicy` (`bb.workspaces.setIamPolicy` at workspace level) sees a warning in
  place of the value, with no Edit link. Create stays allowed and no role is granted. Today the
  field is hidden.

Create runs on leaving step 3. It makes the same two calls as today: create the identity, then set
the IAM policy with the role. If the role call fails, the identity already exists, so the flow
still moves to Done, which shows the error and says the role was not granted.

**D5 · Step 4, Done: the email, then an optional check.** "Workload identity created. Jobs in
acme-corp/deploy can now sign in to project acme-deploy as this identity." The email follows, with
a Copy button and the hint "Set it as `BYTEBASE_WORKLOAD_IDENTITY` in your workflow. Workflows
generated on the GitOps page already use it."

Below a separator, the section "Check that it signs in (optional)" shows one complete test file,
with a Copy button at the top right of the code block.
For GitHub, `.github/workflows/bytebase-wif-test.yml`:

```yaml
name: bytebase-wif-test
on:
  push:
    paths:
      - .github/workflows/bytebase-wif-test.yml
permissions:
  id-token: write
  contents: read
jobs:
  sign-in:
    runs-on: ubuntu-latest
    steps:
      - name: Fetch GitHub OIDC token
        run: |
          OIDC_TOKEN=$(curl -sS --fail -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=bytebase" | jq -r .value)
          echo "::add-mask::$OIDC_TOKEN"
          echo "OIDC_TOKEN=$OIDC_TOKEN" >> $GITHUB_ENV
      - name: Exchange for a Bytebase access token
        run: |
          RESPONSE=$(curl -sS --fail-with-body <EXTERNAL_URL>/v1/auth:exchangeToken \
            -H "Content-Type: application/json" \
            -d '{"token":"'"$OIDC_TOKEN"'","email":"<EMAIL>"}') \
            || { echo "Sign-in refused: $RESPONSE"; exit 1; }
          echo "$RESPONSE" | jq '.accessToken = "<redacted>"'
```

For GitLab, a `bytebase-wif-test` job for `.gitlab-ci.yml` with `when: manual`, `id_tokens` with
`aud: bytebase`, and the same exchange.

- The test runs on a push of its own file, on any branch. It needs no pull request to a protected
  main, and it does not run on other pushes. `workflow_dispatch` was rejected because it only
  works from the default branch.
- `--fail-with-body` makes a refusal fail the job and print the server's reason. Plain `curl -sS`
  exits 0 on HTTP 401.
- `<EXTERNAL_URL>` is the workspace's External URL. When `needConfigureExternalUrl()` is true,
  the section asks the user to set it instead of showing a snippet.
- The audience is the identity's first audience.

Rejected: a live "waiting for the first sign-in" status in the dialog, which needs new backend
state; the job log already shows the result and the refusal reason. Also rejected: an "Add to an
existing workflow" tab, which repeated the generated GitOps workflow.

**D6 · Edit reuses steps 1 to 3.** A banner says the user is editing an existing identity. Every
step is reachable from the rail. The steps load what is stored: the issuer, the audiences, the JWKS
URL, and the pattern, with the fields read from it. There is no separate path for identities made
by the old form.

- **Email** is locked, as today.
- **Provider** is locked when one is stored, so a stored pattern is never rebuilt in another
  provider's format. When none is stored (`PROVIDER_TYPE_UNSPECIFIED`), the cards start empty and
  required, as on create, because the server refuses a save without one
  (`validateWorkloadIdentityConfig`). Today the sheet opens such an identity on GitHub.
- **Roles** are not edited here, as today. They are managed on the Members page.
- **Update** is enabled only when something changed. It sends `title`, and sends
  `workload_identity_config` only when the config changed, as today. The config always carries
  the stored `jwks_url`, also for GitHub and GitLab where the field is not shown.

**D7 · A server error goes to its step.** An `InvalidArgument` that names `issuer_url`, `jwks_url`,
`allowed_audiences` or `subject_pattern` moves the user to the step with that field and shows the
message beside it. Today the sheet opens Advanced instead.

**D8 · Phone layout.** Below 640px:

- The rail becomes one row at the top: numbered circles joined by lines, with only the current
  step's title and no descriptions. This is the shared `StepIndicator` in its `fitOneRow` mode.
- Fields go to one column.
- The dialog fills the screen height minus 16px top and bottom. The title, the step row and the
  footer stay in place; only the step body scrolls.
- The email suffix moves under the name.
- Code blocks scroll sideways.
- The dialog sets its own width (full width minus 16px each side), because the shared
  `DialogContent` is `100vw - 8rem` wide, which leaves 247px on a 375px phone.

**D9 · Nothing that works today breaks.**

- The API and stored data are unchanged.
- Every stored pattern, audience, issuer and JWKS URL loads and saves unchanged, unless the user
  edits it.
- Patterns the old form wrote, including branch patterns such as `repo:o/r:ref:refs/heads/main` and
  GitLab `ref_type` patterns, load with their remainder kept.
- Hand-written workflows and API clients are untouched.
- The API still accepts an identity with no role; the role is required only in the UI.
- The GitOps page reads Owner and Repository from the pattern with
  `parseWorkloadIdentitySubjectPattern` (`frontend/src/utils/workloadIdentity.ts`). It is taught
  to drop `@ID` parts, so `repo:acme-corp@111/deploy:*` gives owner `acme-corp`, not `acme-corp@111`,
  and its repository link stays right.

## States

| Provider | Step 1 shows | Step 2 shows | Step 4 test |
|---|---|---|---|
| GitHub Actions | Issuer, Audiences (read-only, Edit) | Owner, Repository, Owner ID, Subject pattern (read-only, Edit) | `.github/workflows/bytebase-wif-test.yml` |
| GitLab CI | Issuer, Audiences (read-only, Edit) | Group, Project, Subject pattern (read-only, Edit) | `bytebase-wif-test` job |
| Other OIDC | Issuer, Audiences, JWKS URL (editable) | Subject pattern (editable) | None |

| Edit: what is stored | Dialog shows |
|---|---|
| Provider set, pattern the fields can read | Provider locked, fields filled, pattern read-only with Edit |
| Provider set, pattern the fields cannot read | Provider locked, fields disabled, pattern editable |
| No provider | Provider cards empty and required |
| Audiences empty (not repaired by migration 3.23.4) | Audiences tag input empty; at least one value required |

| Role permission | Step 3 Role |
|---|---|
| Can set IAM policy | GitOps Service Agent, read-only with Edit |
| Cannot | A warning in place of the value, no Edit; Create allowed, no IAM call |

| Workspace | Step 4 test section |
|---|---|
| External URL set | The test file with that URL |
| External URL not set | Asks the user to set the External URL; no snippet |

## Scope

| File | Change |
|---|---|
| `frontend/src/utils/workloadIdentity.ts` | Drop `@ID` from GitHub owner and repository (D9). Ships first, on its own. |
| `frontend/src/utils/workloadIdentity.test.ts` | New: tests for that parser. |
| `frontend/src/components/ui/step-indicator.tsx` | `orientation="vertical"` and an optional `description` per step (D1). The horizontal default is unchanged. |
| `frontend/src/components/ui/` (tag input) | Reuse `Combobox multiple` if it accepts typed values; otherwise a small `TagInput` (D2). |
| `frontend/src/components/WorkloadIdentityFlow/subjectPattern.ts` | New: build, parse and replace-one-part for GitHub and GitLab patterns (D3). |
| `frontend/src/components/WorkloadIdentityFlow/testWorkflow.ts` | New: the GitHub test file and GitLab job (D5). |
| `frontend/src/components/WorkloadIdentityFlow/StepParts.tsx` | New: the step heading and the field title with its Edit and Reset links, shared by the steps. |
| `frontend/src/components/WorkloadIdentityFlow/WorkloadIdentityDialog.tsx` | New: the dialog, keeping the stable-entity ref and keyed inner form (D1, D6, D7, D8). |
| `frontend/src/components/WorkloadIdentityFlow/{TokenSource,Repositories,Account,Done}Step.tsx` | New: one component per step (D2–D5). |
| `frontend/src/routes/workspace/WorkloadIdentitiesPage.tsx` | Opens the new dialog. |
| `frontend/src/routes/project/ProjectGitOpsPage.tsx` | Opens the new dialog. |
| `frontend/src/components/CreateWorkloadIdentitySheet.tsx` and its test | Deleted. |
| `frontend/src/locales/*.json` | New strings in all five locales; strings no longer used are removed. |

Tests:

- `workloadIdentity.test.ts` (new): `@ID` dropped from owner and repository.
- `subjectPattern.test.ts`: build, parse and replace round trips; ID forms; an unparsable pattern;
  a field change never widens. The cases mirror `backend/plugin/idp/wif/github_test.go`, so the
  form and the server read a pattern the same way.
- `testWorkflow.test.ts`: the GitHub file and the GitLab job parse as YAML and carry the URL,
  email and audience.
- `WorkloadIdentityDialog.test.tsx`:
  - GitHub create sends `repo:acme-corp/deploy:*`, audiences `[bytebase]`, and the default role,
    GitOps Service Agent.
  - Role is read-only until Edit; choosing another role after Edit sends that role.
  - Owner ID gives `repo:acme-corp@111/deploy:*`.
  - Other OIDC sends its JWKS URL.
  - Edit keeps the stored `jwks_url` and the pattern's remainder when only Owner changes.
  - Edit of an identity with no provider requires picking one.
  - A user without IAM permission creates with no IAM call.
  - A failed role call shows the warning on Done.
  - `InvalidArgument` for `subject_pattern` moves the user to step 2.
- Manual: walk the flow on desktop and at 375px wide, as a project owner and as a workspace admin.
  Run the generated test file from a GitHub repository against a server with a public External
  URL.

## Not in this PR

- Which job used an identity, in the audit log ([BYT-10494](https://linear.app/bytebase/issue/BYT-10494)).
- A live sign-in status in the dialog.
- Branch, tag, event or environment fields; the pattern edit covers them.
- A GitLab group ID.
- "Read more" or setup-guide links in the dialog (the GitHub link in the owner warning is the one
  exception), and the Bytebase docs page for workload identity.

[#21931]: https://github.com/bytebase/bytebase/pull/21931
