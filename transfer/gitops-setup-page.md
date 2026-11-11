# GitOps setup page

Status: proposed · 2026-11-11 · [BYT-10423](https://linear.app/bytebase/issue/BYT-10423) · builds on the workload identity dialog, [#21942]

The project's GitOps page sets up database changes by pull request: a workflow in the team's
repository asks Bytebase to review each pull request and to deploy on merge.
**The page becomes a three-step setup. The owner picks the databases, picks or creates a workload
identity, and gets workflow files in which every value is already filled in. Each step shows the
result of its decision before any file exists.**
Frontend only: no proto, API, store or migration change. The exact text of the generated workflow
files is tracked in [BYT-10424](https://linear.app/bytebase/issue/BYT-10424).

The mock-up (v15, with desktop, large-project and 375px phone frames) and the research pages are
kept outside the repo. The research is summarized in this document with its public sources.

## Problem

The setup owner owns a Bytebase project and can add files to the team's repository. This is often a
DBA or a platform engineer. They want database changes to travel the same way as code changes: a
developer adds a SQL file to a pull request, Bytebase reviews it there, and merging the pull request
deploys it to the databases, one environment after another. Developers do all of this in the git
provider and do not open Bytebase.

To get there, a pipeline in the repository must act in Bytebase on the right databases. Before
setup, the pipeline and Bytebase know nothing about each other. The knowledge needed to connect them
is split between the owner and Bytebase, and nothing tells the owner when the two sides do not
agree. The problem has four parts.

| # | Part of the problem | Why it is hard for the owner | What a mistake causes |
|---|---|---|---|
| 1 | The pipeline does not know what to change. | Which databases belong to the repository is the owner's knowledge. Their names and their environment order are Bytebase's knowledge. The pipeline needs both. | A deploy for an environment that none of the databases is in passes and deploys nothing. A database with no environment is skipped. |
| 2 | Bytebase does not know the pipeline. | The pipeline needs an account in Bytebase that it can use with no stored secret. The rule that says which repository may use the account is written in the git provider's token terms. The account also needs a role in the project. | A rule that is too narrow refuses the pipeline. A rule that is too wide lets other repositories change the databases. An account with no role cannot review or deploy. |
| 3 | The repository has no workflow that calls Bytebase. | The workflow is written in the git provider's language and carries about ten values that must match Bytebase. The owner knows some of them, and Bytebase knows the rest. | One wrong value fails the job, or makes it do nothing. |
| 4 | A mistake is found late, somewhere else, by someone else. | The result of setup shows only when a pipeline runs. That can be days later, in the git provider, in front of a developer who did not do setup. Some mistakes give a passing job. | The team believes a change is deployed when it is not, or a developer is stopped by an error they cannot fix. |

The behavior behind the "mistake" column, verified on `main` at `b203c3f`:

- `action/command/rollout.go`: when the stage named by `--target-stage` is not in the rollout, the
  deploy command logs it and ends without an error.
- `backend/api/v1/rollout_service_task.go`: a target database with no environment gets no deploy
  task.
- `action/command/file.go`: a migration file with no version at the start of its name is skipped
  with a warning. When no file matches the pattern, the command stops with an error.
- `backend/api/v1/release_service_check.go`: the review call stores nothing, so Bytebase holds no
  record that a review ran.

## Principle

> The owner decides only what only the owner knows. Each decision shows its result at once. The
> files are written from the decisions, so they agree with Bytebase with nothing to edit.

Setup is the one place where both sides are known. The owner brings two decisions: which databases,
and which repository may deploy. Bytebase brings everything else.

| Part | Resolved by | The owner decides | Setup does | Result |
|---|---|---|---|---|
| 1 | Step 1, Databases | Which databases this repository's changes belong to | Shows the deploy order, built from the databases' environments. Warns about a database with no environment | The owner sees what a merge will change. The files get the right databases and their environments in order |
| 2 | Step 2, Workload identity | Which repository may deploy, by picking or creating an identity | Shows which repositories the identity trusts and which role it has. Warns when it has no role | No secret is stored. Only the named repositories can sign in, and the account may review and deploy |
| 3 | Step 3, Workflow files | Nothing. The owner adds the files to the repository | Writes the files in full from steps 1 and 2, with every value filled in | The pipeline and Bytebase agree, because the pipeline's values come from Bytebase's own data |
| 4 | Every step | Nothing extra | Checks what Bytebase can see: the environments in step 1, the git provider and the role in step 2, and the Bytebase address before the steps | A mistake that Bytebase can see is caught where the decision is made. What only the repository can show is out of scope (see "Not in this PR") |

## Research

Four questions were researched. Each part below gives the evidence, then what this design takes and
what it leaves out. Nothing is taken because another product does it. A pattern is taken only where
it serves the owner's problem above.

### R1 · How other schema-change tools set up a pipeline

| Product | Setup UI | What the user does | Who adds the file |
|---|---|---|---|
| Flyway Desktop (Enterprise) | In-product wizard "Automated Deployment" with four steps: Workflow, Environments, Review, Checklist | Picks the platform once (GitHub Actions, Bash or PowerShell), then builds a row of environments | The wizard saves `deployment.yml` locally. The user commits it |
| Atlas | Terminal prompts from `gh atlas init-action` ([ariga/gh-atlas](https://github.com/ariga/gh-atlas) at `e861b64`), plus docs | Answers the prompts | The command sets a repository secret and opens a pull request |
| Liquibase | Docs only | Follows nine steps in the git provider's own screens | The user |

None of the three signs in with the pipeline's own OIDC token.

- **Taken:** the file is generated from the user's choices (Flyway, Atlas), and the platform is
  asked once (Flyway). Here the platform is not asked at all, because the workload identity already
  holds it.
- **Left out:** a Review step and a Checklist step (Flyway). Each step here already shows the result
  of its decision, and there is no secret to add, so there is nothing to review or tick off. Opening
  the pull request for the user (Atlas) is left out because Bytebase has no write access to the
  repository.

### R2 · What makes an in-product setup guide work

Sources: NN/g on wizards, GOV.UK service patterns, PatternFly wizard, Shopify setup guide, Carbon
progress indicator, and the setup flows of Sentry
([getsentry/sentry](https://github.com/getsentry/sentry) at `9e85b69`), Codecov
([codecov/gazebo](https://github.com/codecov/gazebo) at `8633d95`), PostHog
([PostHog/posthog](https://github.com/PostHog/posthog) at `61817ef`), and the Claude Platform
"Connect workload" dialog.

| # | Rule found | In this design |
|---|---|---|
| 1 | Few steps, one question each | Yes. Three steps, two questions and one task (D2) |
| 2 | Show all steps, and name each by its result | Yes. The step row shows the three titles (D7) |
| 3 | Ask only what the product cannot know, once | Yes. Two questions. Every other value is read (D6) |
| 4 | Help stays in the step | Yes. One line under each question. No links to setup docs |
| 5 | A blocked step is a task to do, not an error | Yes. Preconditions and failed checks show as tasks with a link (D4, D9) |
| 6 | A generated file carries the user's values | Yes (D5, D6) |
| 7 | Guide the step outside the product with exact handholds | Partly. Paths, copy buttons, the repository link and "what happens next" are given. Ordinary git actions are not explained, because the owner knows their git provider |
| 8 | End on what happens next, with no congratulation page | Yes (D1, D5) |
| 9 | Let the user leave and come back | Not used. Setup saves nothing, and going through it again takes a few clicks (D1) |

### R3 · Where the step list goes

Three layouts were compared: a rail on the left, a row on top, and all steps stacked on one page.

| Evidence | Finding |
|---|---|
| Bytebase pages, `main` at `b203c3f` | Every page-level step flow uses the horizontal `StepIndicator` on top: `routes/project/ProjectSyncSchemaPage.tsx`, `components/sql-review/ReviewCreation.tsx`, `routes/auth/workspace-setup/SetupScreenFrame.tsx`. A vertical rail exists only in the workload identity dialog of [#21942] |
| `docs/agents/frontend-ux.md` | A long multi-step workflow that deserves a route is a full-page wizard with the shared step indicator |
| Design systems | Side: Carbon, PatternFly, Cloudscape. Top: Material, SAP Fiori, Atlassian, Ant Design, USWDS. No source gives a rule that fits every case |
| Products, by kind of setup | Choices that shape a result are shown one step at a time (Flyway Desktop, Claude Platform). Instructions that are carried out elsewhere are stacked (Sentry, Codecov, Liquibase docs). GitOps setup is the first kind |
| Width, measured on the mock-up | The project navigation is 208px (`components/DashboardBodyShell.tsx`). A 232px rail beside it leaves 760px for the workflow files. In a 1024px window, 5 and 7 lines of the two GitHub files do not fit. With the row on top the content is 992px wide, and 1 and 1 lines do not fit |

- **Taken:** the row on top (D7). It is what Bytebase pages already use, and it gives the workflow
  files the most width.
- **Left out:** the rail's one-line description per step. The row has no room for it, so each step
  states its question and one line of help in its own body.

### R4 · Where Back and Continue go when the steps are on top

| Where the buttons are | Who does it | In view on a tall step |
|---|---|---|
| In the header, beside the step row | Flyway Desktop (Back top left, Continue top right) | Only if the header stays on screen |
| In a footer bar at the bottom | [SAP Fiori wizard](https://experience.sap.com/fiori-design-web/wizard/) in tab-bar mode, the Azure portal create flow, Bytebase `ReviewCreation.tsx` | Bytebase: yes, verified in source. The others do not state it |
| At the end of the step content | Demos of [MUI](https://mui.com/material-ui/react-stepper/), [Mantine](https://mantine.dev/core/stepper/), [Chakra UI](https://chakra-ui.com/docs/components/steps), [Ark UI](https://ark-ui.com/docs/components/steps), [PrimeReact](https://primereact.org/stepper/), SAP Fiori in anchor-bar mode, PostHog onboarding | No |

[USWDS](https://designsystem.digital.gov/components/step-indicator/) and
[Carbon](https://carbondesignsystem.com/components/progress-indicator/usage/) say the step indicator
is not navigation and that back and next must be provided separately, but not where. shadcn/ui, Base
UI, Radix and HeroUI have no stepper component.

- **Taken:** the buttons sit under the step content, where every library puts them, in a footer that
  stays at the bottom of the window (D8). Bytebase already has this part:
  `components/ui/sticky-action-footer.tsx`, used by 11 pages and forms.
- **Left out:** buttons in the header. See "Alternatives considered".

## Decisions

**D1 · The GitOps page is the setup.** There is no start screen, no Start button, no finish screen
and no Done button. The page opens with the outcome in one sentence: "Every pull request that
changes the migration folder gets a Bytebase review. Merging it deploys." Under it are the three
steps, with step 1 open. Bytebase saves nothing: the files in the repository are the setup, and a
saved copy would go stale as soon as someone edits them. Opening the page again starts at step 1. A
lone database and a lone identity are already picked, so going through the steps again takes a few
clicks.

**D2 · Three steps: Databases, Workload identity, Workflow files.** Two decisions that only the
owner can make, and one hand-over. Databases comes first because it is the goal the owner came with,
and the identity is the means. Workflow files comes last because the files are built from both. Each
title names what the step settles. Steps 1 and 2 open with a question, and step 3 opens with a task.

**D3 · Step 1, Databases: "Which databases should GitOps deploy to?"** Resolves part 1.

- *The owner decides:* one database group (the first tab, marked Recommended), or one or more
  databases. A group is recommended because a database that joins the group later is deployed too,
  with no change to the workflow files. A list of databases is written into the files, so adding one
  means editing them. Databases are picked with `DatabaseSelect`, which searches on the server and
  loads more results on demand, so a project with hundreds of databases stays usable. If the project
  has no database group, the Databases tab opens, and a lone database is already picked.
- *Setup shows:* the deploy order, as one bordered list with one section per environment, in the
  project's environment order. A vertical line with one dot per environment joins the sections.
  There are no order numbers, because the setup steps on the same page are already numbered. A
  section has the environment name and the first three databases, each as a chip written as instance
  / database (`DatabaseTargetDisplay`), because several instances often hold a database with the
  same name. A section with more than three databases ends the chips with an inline "+81 more"
  action, placed and styled as on the plan page, that opens the list of the other databases, with
  search when the list is long. The list has a total when the pick has more than three databases. On
  the Database group tab, a View group link opens the group. Hiding provider-reserved databases,
  such as Neon's `postgres`, is tracked in [BYT-10254](https://linear.app/bytebase/issue/BYT-10254)
  and is not part of this change.
- *Setup checks:* databases with no environment. A group that matches some shows a warning under the
  deploy order. The warning says how many will not be deployed, names the first three with the same
  "+N more" action, and says to assign an environment to include them. On the Databases tab they are
  listed but cannot be picked, and each one says "No environment". If no database in the project has
  an environment, the tab shows a warning instead.
- *Goes into the files:* the group, or the list of databases, and their environments. Nothing is
  created in Bytebase.
- *Not asked:* the environment. It comes from each database.
- Continue is disabled until at least one database or a group is picked.

**D4 · Step 2, Workload identity: "Which workload identity does your workflow sign in as?"**
Resolves part 2.

- *The owner decides:* one workload identity of this project. If the project has only one, it is
  already picked. If it has none, the step shows only a Create workload identity button, which opens
  the dialog of [#21942]. Opened from setup, the dialog closes after Create and the new identity
  comes back picked (D10).
- *Setup shows:* what it reads from the picked identity, in a read-only box: Git provider,
  Repositories that can sign in (one repository, or every repository of an owner), and Role in this
  project.
- *Setup checks,* shown only when one fails, as a task with a link:
  - The git provider is GitHub Actions or GitLab CI. An identity for another OIDC provider is listed
    but cannot be picked, because setup has no files for it.
  - The identity has a role that allows GitOps in this project, such as GitOps Service Agent. An
    identity with no role cannot review or deploy, so Continue is disabled and a warning links to
    the Members page.
- *Goes into the files:* the identity's email and its git provider.
- *Not asked:* git provider, owner, repository, owner ID, email, role, issuer and audience. The
  identity already holds them.

**D5 · Step 3, Workflow files: "Add the files to your repository".** Resolves part 3. The step asks
no question. It does not explain how to commit a file or open a pull request. It shows, in this
order:

1. The migration folder, `migrations/`, read-only with an Edit action. Changing it updates the
   files.
2. The repository, as a link, when the identity names one. A workload identity does not require a
   repository: it can trust every repository of an owner. In that case this line is left out.
3. The generated files for the identity's git provider, each in full with its path in a header bar
   and a copy button, one under the other. There are no tabs and nothing is collapsed. GitHub
   Actions: `.github/workflows/bytebase-review.yml` reviews pull requests that change migration
   files, and `.github/workflows/bytebase-deploy.yml` deploys on each merge. GitLab CI: one
   `bytebase.gitlab-ci.yml` with both jobs, plus the one `include` line to add to `.gitlab-ci.yml`.
4. What happens next: "Once the files are on the default branch, the next pull request that changes
   the migration folder gets a Bytebase review comment. Merging it deploys." GitLab says "merge
   request".
5. For developers: "Add a file such as `migrations/0001_create_orders.sql` in a pull request. File
   names start with a version number. The workflow skips a file without one."

Each job signs in with the identity's email and the job's own token. There is no secret and no build
job. The only placeholder is the Bytebase URL while the External URL is not set (D9). The owner
commits the files. Bytebase does not.

[#21974] moved sign-in into `bytebase-action`, so the files no longer need the token exchange
script. The generator drops the script in a follow-up of that change, after the new action image has
reached Bytebase Cloud (`docs/design/bytebase-action-sign-in.md`). This change leaves the sign-in
lines as they are.

**D6 · Every value in the files has one source, and the owner is asked for two.**

| Value | Used for | Source |
|---|---|---|
| Bytebase URL and project | Every call to Bytebase | Known by the page. On self-hosted Bytebase the URL is the workspace External URL (D9) |
| Action version | The action must fit the server's version | Known by the page (`bytebaseActionImage` in `gitopsWorkflowYaml.ts`) |
| Databases to deploy to | What to review and deploy | **Asked in step 1** |
| Deploy environments | Which stages the deploy runs, in order | The databases' environments, in the project's environment order |
| Workload identity | The account the workflow signs in as | **Picked or created in step 2** |
| Email, audience, git provider | Signing in, file format and triggers | Read from the workload identity |
| Token settings | Letting the job get its own token | Written by the page for the identity's git provider |
| Repository | Where the owner commits the files | Read from the workload identity when it names one. The files do not contain it |
| Deploy branch | When the deploy job runs | The repository's default branch, read by the workflow at run time |
| Migration folder | Which files to review and deploy | Prefilled `migrations/`, editable in step 3 |

**D7 · The step list is a row on top.** It is the shared horizontal `StepIndicator`: a 24px circle
and a title per step, joined by lines. A finished step shows a check. A reached step can be clicked
to go back to it (`onStepClick`, added by [#21942]). On a phone the row shows only the open step's
title. The row scrolls with the page. Step headings, fields, buttons, code blocks and warnings use
the same parts as the workload identity dialog (`WorkloadIdentityFlow/StepParts.tsx`), so the two
step flows look and behave the same. Setup has no close button, no Cancel button and no fixed
height.

**D8 · Back and Continue sit in a footer that stays at the bottom of the window.** It is the shared
`StickyActionFooter`: Back on the left from step 2, Continue on the right, a line on top and the
page background, so the step content scrolls under it. A step can be taller than the window, for
example with a long deploy order, a warning, or the workflow files. The owner then still sees
Continue without scrolling to the end. Step 3 has only Back. The footer is the same on a phone.

**D9 · Preconditions show only when they are not met.** Setup needs three things: the project has at
least one database, the project has a workload identity or the user may create one, and on
self-hosted Bytebase the workspace External URL is set. A precondition that is not met shows as a
task at the top of the page: what is missing, who can fix it, and a link.

Without a database, or without an identity and the permission to create one, the steps cannot be
used. An unset External URL does not block the steps. Only a workspace admin can set it, the owner
is often not one, and steps 1 and 2 do not need it. The task stays on top of every step. Step 3
shows the files in full with a marked placeholder in place of the URL. Its copy buttons are
disabled, with the reason beside them, so a file that cannot reach Bytebase is not committed by
accident.

**D10 · Opened from setup, the workload identity dialog closes after Create.** Its last step shows
the email and a test workflow file. Setup already shows the identity, and step 3 gives the real
files, so a test file shown first would give the owner two different files to add. Opened anywhere
else, the dialog keeps its last step.

**D11 · Workload identity only, with GitHub Actions and GitLab CI only.** Setup offers no service
account and no other platform. Service accounts stay available elsewhere in Bytebase, and
hand-written workflows keep working.

**D12 · The deploy branch is not asked.** The deploy job runs on the repository's default branch,
which GitHub and GitLab both expose to the workflow. A team that deploys from another branch changes
one line.

## States

| Project | Step 1 opens with |
|---|---|
| Has a database group | Database group tab, the group picked, deploy order shown |
| No database group, one database | Databases tab, the database picked |
| No database group, several databases | Databases tab, nothing picked, Continue disabled |
| Some databases have no environment | A warning under the deploy order. On the Databases tab they cannot be picked |
| No database has an environment | A warning in place of the picker. Continue disabled |

| Project's workload identities | Step 2 shows |
|---|---|
| None | Only the Create workload identity button |
| One, for GitHub Actions or GitLab CI | That identity picked, with the read-only box |
| Several | A picker, nothing picked, and a Create workload identity button beside it |
| One for another OIDC provider | Listed, cannot be picked, with the reason |
| Picked identity has no role | The read-only box, a warning with a link to Members, Continue disabled |

| Picked identity | Step 3 shows |
|---|---|
| GitHub Actions, names one repository | The repository link and two files |
| GitHub Actions, trusts every repository of an owner | Two files, no repository link |
| GitLab CI | One file and the `include` line, and "merge request" in the text |

| Workspace | Page shows |
|---|---|
| External URL set, or Bytebase Cloud | The three steps |
| Self-hosted, External URL not set | A task on top of every step with "Configure now". The steps can be used. Step 3 shows the files with a placeholder for the URL, and its copy buttons are disabled |

| Window | Layout |
|---|---|
| Desktop | Content up to 1040px wide, step row with three titles, footer at the bottom of the window |
| Phone, 375px | One column, step row with the open step's title only, the same footer |

## Alternatives considered

**The step set**

- **Sign-in first (Workload identity, then Databases).** Rejected. The databases are what the owner
  came for. Neither decision depends on the other, so the order follows the owner's goal.
- **Two steps (Databases and Workload identity on one screen, then the files).** Rejected. Each
  decision has its own result to show and its own check, and two results on one screen bury both.
- **A fourth step, "First migration", with a sample file.** Rejected. Owners will not run a sample
  change against real databases, and Bytebase cannot see whether they did. After the hand-over the
  owner is in the git provider, so a step on the setup page would speak in the wrong place.
- **A repository step.** Rejected. The workload identity already says which repositories may sign
  in, and the files do not contain the repository.
- **Offering a service account as well.** Rejected for setup (D11). It needs a stored secret, which
  is part 2 of the problem.

**Knowing that setup worked**

- **Run the review job on the pull request that adds the workflow files.** The review file would
  also trigger on a change to itself, and a passing job would show that sign-in works. Rejected for
  now: the review command stops with an error when the migration folder has no file
  (`action/command/file.go`), so a repository that is new to GitOps would get a failed job although
  sign-in worked. It needs a change in the action first (BYT-10424).
- **A live check on the setup page.** Not in this PR. Since [#21971] the audit log records each
  sign-in with its repository, so a later change could read it. That change needs its own design
  (see "Not in this PR").

**The layout**

- **A rail on the left, as in the workload identity dialog.** Rejected (R3). On a page it adds a
  second left column beside the project navigation and takes 232px from the workflow files.
- **All steps stacked on one page.** Rejected (R3). Stacked steps fit instructions that are carried
  out elsewhere. Here step 3 cannot be shown until steps 1 and 2 are answered, because the identity
  decides the file format and the databases decide the deploy stages.
- **Back and Continue in the header, beside the step row.** Rejected (R4). The owner finishes
  reading a step at the bottom, where a header button is furthest away. A 375px row has no room for
  the step and two buttons. Only one product was found that does this.
- **Back and Continue at the end of the step content, not fixed.** Rejected. It is the libraries'
  default and works for short steps, but a long deploy order or the workflow files push Continue
  below the window.
- **Keeping the step row fixed at the top as well.** Rejected. A fixed row and a fixed footer
  together take too much of a phone screen.

**Smaller choices**

- **Saving the setup in Bytebase.** Rejected (D1).
- **Asking for the deploy branch.** Rejected (D12).
- **Asking which runner the jobs use.** Rejected. The files use the git provider's hosted runner. A
  team with its own runners needs its own labels or runner group, which only the team knows, and it
  changes one line.
- **Blocking every step until the External URL is set.** Rejected (D9). The owner often cannot set
  it, and would see nothing of the setup while waiting for an admin.
- **Deploy order as counts only, as plain names with a "Show all" link, with a "View all" action in
  a header strip, or with order numbers.** Rejected in favor of the plan page's own pattern: chips
  and an inline "+N more" (D3).

## Scope

Expected files. The list is refined when implementation starts.

| File | Change |
|---|---|
| `frontend/src/routes/project/ProjectGitOpsPage.tsx`, with a new test | Becomes the three-step setup: outcome sentence, preconditions, step row, step body, footer (D1, D2, D7, D8, D9). |
| `frontend/src/routes/project/gitops-setup/{DatabasesStep,WorkloadIdentityStep,WorkflowFilesStep}.tsx` | New: one component per step (D3, D4, D5). |
| `frontend/src/routes/project/gitops-setup/DeployOrder.tsx` and its test | New: the deploy order list, the "+N more" list and the no-environment warning (D3). |
| `frontend/src/routes/project/gitopsWorkflowYaml.ts` and its test | Takes the picked targets, their environments, the identity and the folder, and returns the files for the identity's git provider (D5, D6). The exact YAML is BYT-10424. |
| `frontend/src/routes/project/WorkloadIdentitySelect.tsx` | Lists every identity of the project and disables those for another OIDC provider (D4). |
| `frontend/src/components/WorkloadIdentityFlow/WorkloadIdentityDialog.tsx` and its test | An opt-in prop to close after Create and return the new identity (D10). |
| `frontend/src/components/ui/step-indicator.tsx` | Reused as it is after [#21942]. |
| `frontend/src/components/ui/sticky-action-footer.tsx` | Reused as it is. |
| `frontend/src/components/DatabaseSelect.tsx`, `DatabaseTargetDisplay.tsx` | Reused as they are. |
| `frontend/src/locales/{en-US,es-ES,ja-JP,vi-VN,zh-CN}.json` | New `gitops` setup strings in all five locales. Strings that are no longer used are removed. |
| `docs/design/gitops-setup-page.md` | This document. |

Tests:

- `gitopsWorkflowYaml.test.ts`: the files parse as YAML and carry the URL, project, targets, email,
  audience, action version and folder. A group gives one target. Environments appear in the
  project's order. GitHub gives two files and GitLab one. No secret is referenced.
- `DeployOrder.test.tsx`: sections follow the environment order. Three chips, then "+N more". The
  total shows above three databases. The warning counts databases with no environment.
- `ProjectGitOpsPage.test.tsx`:
  - A project with one database and no identity opens on the Databases tab with the database picked.
  - Continue is disabled with nothing picked, and with an identity that has no role.
  - An identity for another OIDC provider cannot be picked.
  - Creating an identity from step 2 returns to step 2 with it picked.
  - The repository link shows only when the identity names a repository.
  - Editing the folder changes the paths in the files and in the developers' line.
  - An unset External URL shows the task on every step, a placeholder in the files and disabled copy
    buttons.
  - The footer holds Continue on steps 1 and 2 and only Back on step 3.
- Manual: walk the three steps on desktop and at 375px wide, in a project with one database and in
  one with more than a hundred. In a window shorter than the step, check that Continue stays in
  view. Add the generated files to a GitHub repository and to a GitLab project, open a pull request
  with a migration file, and merge it.

## Not in this PR

- The exact workflow YAML and the action's behavior
  ([BYT-10424](https://linear.app/bytebase/issue/BYT-10424)), including a deploy job that passes
  without deploying ([BYT-10426](https://linear.app/bytebase/issue/BYT-10426)) and a review that
  ends without an error when there are no files.
- Checking the repository side: whether the files were added, whether a job may request a token, and
  whether the runner can reach Bytebase. The first pull request with a migration file is the check.
- A live sign-in status for the identity on the setup page. Since [#21971], audit rows name the
  repository behind each sign-in ([BYT-10494](https://linear.app/bytebase/issue/BYT-10494)). Setup
  does not read them.
- Setup by coding agents ([BYT-10425](https://linear.app/bytebase/issue/BYT-10425)).
- Service accounts, and CI systems other than GitHub Actions and GitLab CI.
- Review rules, approvals and environments. They have their own places in Bytebase.
- The workload identity and service account list pages
  ([BYT-10511](https://linear.app/bytebase/issue/BYT-10511)).

[#21942]: https://github.com/bytebase/bytebase/pull/21942
[#21971]: https://github.com/bytebase/bytebase/pull/21971
[#21974]: https://github.com/bytebase/bytebase/pull/21974
