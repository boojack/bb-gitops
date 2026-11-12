### Why

A project owner wants database changes to travel the same way as code changes: a developer adds a SQL file to a pull request, Bytebase reviews it there, and merging the pull request deploys it to the databases, one environment after another.

To get there, a pipeline in the repository must act in Bytebase on the right databases. Before setup, the pipeline and Bytebase know nothing about each other, and the knowledge that connects them is split between the owner and Bytebase:

- The pipeline does not know which databases to change, or in which order.
- Bytebase does not know the pipeline. The pipeline needs an account in Bytebase, a rule for which repository may use it, and a role in the project.
- The repository has no workflow that calls Bytebase. The workflow carries about ten values that must match Bytebase.
- A mistake shows only when a pipeline runs. That can be days later, in the git provider, in front of a developer who did not do the setup. Some mistakes give a passing job that deploys nothing.

### What changes

The GitOps page becomes the setup itself. Nothing is saved; the files in the repository are the setup. The change improves how the owner goes through setup, and fixes cases where setup produced files that did not work.

**Improvements**

- **Setup is a step-by-step flow.** Three steps with one question or one task each: Databases, Workload identity, Workflow files. A row on top names every step, and Back and Continue stay at the bottom of the window. A step opens only when the steps before it are complete. Other products guide a setup with choices the same way, for example the deployment wizard in Flyway Desktop.
- **Each step shows the result of its decision.** Step 1 shows the deploy order: the picked databases by environment, in the order the rollout deploys them. Step 2 shows what setup reads from the identity: its git provider, the repositories that can sign in, and its role in the project.
- **The owner answers two questions, and every other value is read.** The git provider comes from the identity, so there are no GitHub and GitLab tabs to choose from. The environments come from the databases. The files arrive complete.
- **Creating an identity does not leave setup.** Opened from step 2, the dialog offers GitHub Actions and GitLab CI only, closes after Create, and the new identity is picked.
- **The files are shorter and easier to copy.** They have no sign-in script: `bytebase-action` signs in as `BYTEBASE_WORKLOAD_IDENTITY` (#21974), which removes 18 lines from every GitHub job and 10 from every GitLab job. Each file shows its path and a copy button. A file longer than 12 lines shows its first 12 lines with "Show all N lines"; Copy always takes the whole file.
- **The migration folder can be changed.** It is `migrations/` by default, and an edit updates the files.
- **The page says what it covers and what comes next.** A line on every step says setup writes files for GitHub Actions and GitLab CI. Step 3 ends with what happens once the files are on the default branch.

**Fixes**

| What went wrong | Now |
|---|---|
| The deploy jobs were fixed: `deploy-to-test` and `deploy-to-prod`, with `--target-stage=environments/test` and `environments/prod`. In a project with other environment IDs, the deploy command does not find the stage and ends without an error, so the job passes and deploys nothing. Any other environment had no deploy job. | One deploy job per environment of the picked databases, in the workspace's environment order. Each job needs the one before it. |
| The files held one branch name, read from the identity's rule, or `main` when the rule names no branch. In a repository with another default branch, the workflows did not run. | The jobs compare with the repository's default branch at run time. |
| A database with no environment could be picked. The rollout skips it without an error. | It cannot be picked. A group that matches some shows a warning with their count. |
| An identity with no role in the project could be picked. Bytebase refuses its review and its deploy. | A warning with a link to Members. Continue is disabled. |
| An identity for another OIDC provider could be picked. The GitHub or GitLab files were still shown, under a warning. | It cannot be picked, and the picker says why. |
| The files were shown and could be copied before a database or an identity was picked, with `{...}` placeholders in them. With no External URL, they held an empty URL. | Step 3 opens only after steps 1 and 2. With no External URL, the files show `{EXTERNAL_URL}` marked, and copy is off. |

The action is not changed. It still ends without an error for a stage that is not in the rollout (BYT-10426).

Notes for review:

- GitLab: the prod deploy job no longer has `when: manual`. Every environment deploys in order after the previous one, the same as GitHub.
- The files no longer carry the token exchange script or `--access-token`. This is the generator change of #21974, so it must ship after #21974 has reached Bytebase Cloud. GitLab jobs name their ID token `BYTEBASE_ID_TOKEN`.
- The one-off test workflow in the workload identity dialog is unchanged. It runs without the action image and keeps its own exchange.
- The pickers in the steps render their menus in the overlay layer, so the sticky footer does not cover them.
- Workflow files that are already in a repository keep working. The server still accepts the token exchange and `--access-token`.
- The self-hosted runner switch is removed. An owner who uses one changes `runs-on` in the repository.
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
