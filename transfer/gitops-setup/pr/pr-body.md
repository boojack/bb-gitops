### Why

A project owner wants database changes to travel the same way as code changes: a developer adds a SQL file to a pull request, Bytebase reviews it there, and merging the pull request deploys it to the databases, one environment after another.

To get there, a pipeline in the repository must act in Bytebase on the right databases. Before setup, the pipeline and Bytebase know nothing about each other, and the knowledge that connects them is split between the owner and Bytebase:

- The pipeline does not know which databases to change, or in which order.
- Bytebase does not know the pipeline. The pipeline needs an account in Bytebase, a rule for which repository may use it, and a role in the project.
- The repository has no workflow that calls Bytebase. The workflow carries about ten values that must match Bytebase.
- A mistake shows only when a pipeline runs. That can be days later, in the git provider, in front of a developer who did not do the setup. Some mistakes give a passing job that deploys nothing.

### What changes

Two improvements and one fix.

**Improvements**

1. **Setup is a step-by-step flow.** The GitOps page becomes three steps, each with one question or one task: Databases, Workload identity, Workflow files. A row on top names every step, and Back and Continue stay at the bottom of the window. Other products guide a setup with choices the same way, for example the deployment wizard in Flyway Desktop. The owner makes one decision at a time and sees its result before the next one. Nothing is saved; the files in the repository are the setup.
2. **Step 1 shows the deploy order before any file is written.** The picked database group or databases are listed by environment, in the order the rollout deploys them. A picked group that matches databases with no environment shows a warning, because the rollout skips those databases.

**Fix**

3. **The generated deploy jobs follow the project's environments.** The generator wrote two fixed deploy jobs, `deploy-to-test` and `deploy-to-prod`, with `--target-stage=environments/test` and `environments/prod`, whatever environments the databases were in. In a project with other environment IDs, the deploy command does not find the stage, logs it and ends without an error, so the job passes and deploys nothing. An environment other than `test` or `prod` got no deploy job. The generator now writes one deploy job per environment of the picked databases, in the workspace's environment order, and each job needs the one before it. The action itself is not changed and still ends without an error for an unknown stage (BYT-10426).

The steps:

| Step | Question | What the owner does |
|---|---|---|
| 1. Databases | Which databases should GitOps deploy to? | Picks a database group (recommended) or databases. Sees the deploy order by environment. |
| 2. Workload identity | Which workload identity does your workflow sign in as? | Picks or creates one. Sees its git provider with its logo, the repositories that can sign in, and its role. |
| 3. Workflow files | Add the files to your repository | Copies the files, which already hold the databases, environments, identity and migration folder. Each file shows its path and a copy button. A file longer than 12 lines shows its first 12 lines, with "Show all N lines" under them. Copy always takes the whole file. The repository link carries the git provider's logo. |

Other changes, before and after:

| | Before | After |
|---|---|---|
| Deploy branch | Read from the identity, `main` by default | The repository's default branch, read at run time |
| Migration folder | Fixed `migrations/` | `migrations/` by default, editable |
| Provider | GitHub/GitLab tabs, with a mismatch warning | The identity's git provider decides; an identity for another OIDC provider cannot be picked. A line on every step says setup writes files for GitHub Actions and GitLab CI |
| Sign-in in the files | An 18-line token exchange script in every GitHub job, 10 lines in every GitLab job | No sign-in step. `bytebase-action` signs in as `BYTEBASE_WORKLOAD_IDENTITY` (#21974) |
| Databases with no environment | Accepted, then skipped by the rollout | Cannot be picked one by one; a group that matches some shows a warning |
| Identity with no role | Accepted | Warning with a link to Members; Continue is disabled |
| Creating an identity | The dialog ends on its Done step | Opened from setup, the dialog offers GitHub Actions and GitLab CI only, closes after Create, and the identity is picked |
| External URL not set | A failed check in the list; files hold an empty URL | Warning on every step; files show `{EXTERNAL_URL}` marked; copy is off |
| Self-hosted runner switch | Present | Removed |

Notes for review:

- GitLab: the prod deploy job no longer has `when: manual`. Every environment deploys in order after the previous one, the same as GitHub.
- The files no longer carry the token exchange script or `--access-token`. This is the generator change of #21974, so it must ship after #21974 has reached Bytebase Cloud. GitLab jobs name their ID token `BYTEBASE_ID_TOKEN`.
- The one-off test workflow in the workload identity dialog is unchanged. It runs without the action image and keeps its own exchange.
- The pickers in the steps render their menus in the overlay layer, so the sticky footer does not cover them.
- Workflow files that are already in a repository keep working. The server still accepts the token exchange and `--access-token`.
- No API, proto, store or backend change.

Details are in `docs/design/gitops-setup-page.md`: the decisions, the state tables, the research on how Atlas, Liquibase and Flyway set up a pipeline, and the alternatives considered.

### Screenshots

The page with placeholder data: project `shop`, a database group with one database in Test and one in Prod, and a workload identity for the GitHub repository `acme-corp/deploy`.

Step 1, Databases. The database group is picked, and the deploy order shows its databases by environment:

![Step 1, Databases](pr-screens/byt-10423/1-databases.png)

Step 2, Workload identity. The box shows what setup reads from the picked identity: its git provider, the repositories that can sign in, and its role in the project:

![Step 2, Workload identity](pr-screens/byt-10423/2-workload-identity.png)

Step 3, Workflow files. Each file shows its path, a copy button, and its first 12 lines. The files already hold the Bytebase URL, the identity and the project:

![Step 3, Workflow files](pr-screens/byt-10423/3-workflow-files.png)

### Commits

1. `docs(design)`: the design doc.
2. `gitopsWorkflowYaml.ts`: `generateWorkflowFiles` builds the files from the picked targets, environments, identity and folder.
3. `gitops-setup/useDeployTargets.ts` and `DeployOrder.tsx`: the deploy order.
4. Opt-in props on shared parts: `WorkloadIdentityDialog closeOnCreate` and `gitProvidersOnly`, `WorkloadIdentitySelect describe/disabledReason`, `DatabaseSelect requireEnvironment`.
5. The page becomes the three steps; old generators, the workflow image and unused strings are removed.

### Tests

- `gitopsWorkflowYaml.test.ts`: files parse as YAML; paths, job order and `needs`, default-branch conditions, group as one target, folder, placeholder, folder validation; no job has a sign-in step or passes a token; every GitHub job has `id-token: write`; every GitLab job names its ID token `BYTEBASE_ID_TOKEN`.
- `useDeployTargets.test.ts`, `DeployOrder.test.tsx`: environment order, unknown environments first, unassigned databases, chips and "+N more".
- `WorkloadIdentityDialog.test.tsx`, `WorkloadIdentitySelect.test.tsx`, `DatabaseSelect.test.tsx`: the new props, and no change without them.
- `ProjectGitOpsPage.test.tsx`: lone database prepicked; Continue disabled with nothing picked and for an identity with no role; other OIDC identity cannot be picked; Create from step 2 opens the dialog with git providers only and returns with it picked; the scope line on every step; every picker opens its menu in the overlay layer; a long file shows 12 lines until Show all, and Copy holds the whole file; a file's header bar holds only its path; repository link only for one named repository; the git provider's logo before the provider name and the repository link; folder edit updates files and the developers' line; unset External URL; footer buttons per step.
- Manual (to do): walk the steps at desktop width and at 375px in a small and a large project; add the files to a GitHub repository and a GitLab project, open a pull request with a migration file, and merge it.

### Not in this PR

- The exact workflow YAML and the action's behavior (BYT-10424).
- Hiding provider-reserved databases such as Neon's `postgres` (BYT-10254).
- Checking the repository side, a live sign-in status, and setup by coding agents (BYT-10425).
