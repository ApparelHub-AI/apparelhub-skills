# Workspaces (enterprise / agency accounts)

On Enterprise (agency) accounts, an account is divided into **workspaces** —
isolated client / brand spaces. Stores, products, designs, and orders are
organized by workspace. If the user is on a single-workspace or non-Enterprise
account, you can ignore this file: everything lives in one **Default**
workspace and the `?workspace=` param below is optional and harmless.

The one thing that trips agents up: on a multi-workspace account a list can
look like it's "missing" data when you're really just scoped to a different
workspace. It isn't missing. Read on.

---

## 1. Every request acts within ONE active workspace

Each Agent API request resolves an **active workspace**:

- **No `?workspace=` param** → the account's **Default** workspace.
- **`?workspace=<uuid>`** → that specific workspace, if you may access it.

List/get results are scoped to that active workspace. So before you tell a
user "you have no products / no stores," confirm you're looking at the right
workspace. A subset is almost never missing data — it's a different scope.

## 2. Targeting a workspace

Append `?workspace=<workspace_uuid>` to any list / get / create call. It
combines with other query params (`?limit=`, `?fields=`, etc.):

```bash
# Default workspace (no param)
curl -sS "https://api.apparelhub.ai/agents/v1/store" \
  -H "x-api-key: $APPARELHUB_API_KEY"

# A specific client workspace
curl -sS "https://api.apparelhub.ai/agents/v1/store?workspace=<workspace_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"

curl -sS "https://api.apparelhub.ai/agents/v1/images/generated?workspace=<workspace_uuid>&limit=20&sort=newest" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

There's no agent endpoint that lists an account's workspaces, so when the user
talks about a workspace by name ("the Crystal Riley client"), get the uuid
from the `workspaces` field on an asset you already have (section 4) or from
the web UI at `https://apparelhub.ai/team` (Team & Workspaces).

### Errors — a bad `?workspace=` fails the WHOLE request

There is no silent fallback to Default. Handle these before assuming the
platform is down:

| Status | `error` code | Meaning | What to do |
|---|---|---|---|
| 404 | `workspace_not_found` | The `?workspace=` uuid doesn't resolve to any workspace | Fix the uuid, or omit the param to use Default. |
| 403 | `workspace_forbidden` | The workspace exists but this key / user may not act in it | You're targeting a workspace you aren't assigned to (or a workspace-scoped key pointed at a different workspace — section 5). Use one you can access. |

Example bodies:

```json
404  {"error": "workspace_not_found", "message": "The requested workspace was not found."}
403  {"error": "workspace_forbidden", "message": "This key does not have access to the requested workspace."}
```

## 3. Don't misread a scoped list as "missing data"

This is the failure mode this whole file exists to prevent. On an enterprise
account:

- `GET /store` returns the stores in the **active** workspace, not every store
  on the account.
- `GET /images/generated`, `GET /product`, `GET /orders` are scoped the same
  way.

If something you expected isn't there, it's in another workspace. Re-issue with
the right `?workspace=`, or inspect the asset's workspace membership (next
section). Never report "no data" without checking the active workspace first.

## 4. Which workspace is an asset in? (Model A visibility)

Responses tell you, so you never have to guess.

- **Products** and **generated images** carry a `workspaces` **array** — every
  workspace the asset belongs to:

  ```json
  "workspaces": [
    {"uuid": "…", "name": "Crystal Riley", "is_default": false},
    {"uuid": "…", "name": "Default",       "is_default": true}
  ]
  ```

  An asset shows up in a workspace when it's tied to a **store** in that
  workspace (store-association based), or in its **home** workspace if it isn't
  on any store yet. So one design can legitimately appear under several clients
  at once.

- **Stores** live in exactly **one** workspace, carried as flat fields rather
  than an array:

  ```json
  "workspace_uuid": "…", "workspace_name": "Crystal Riley", "workspace_is_default": false
  ```

Practical use: a product whose `workspaces` is `[{"name": "Crystal Riley"}]`
won't appear when the active workspace is Default — that's correct, not a bug.
Switch with `?workspace=` to act on it.

## 5. Workspace-scoped agent keys

An Agent API key can be **pinned to a single workspace** (with a workspace
role) when it's created in the web UI (Developer → API Keys). The key string
looks no different; you infer the scope from behavior.

For a workspace-scoped key:

- **It's locked to its workspace.** Omitting `?workspace=` uses the key's
  workspace. Passing `?workspace=<a-different-workspace>` returns
  **403 `workspace_forbidden`**.
- **Its role gates capabilities.** A role without design-generation rights
  returns **403** on `POST /images/generate`:

  ```json
  {"error": "forbidden", "capability": "design.generate",
   "message": "This key's workspace role does not permit this action."}
  ```

  Don't retry — surface it. The account owner controls the key's role and
  workspace in the web UI.

- **Account-wide keys** (the default) are not pinned and can target any
  workspace the user can access via `?workspace=`.

## 6. Single-workspace / non-Enterprise accounts

Nothing changes. There's one Default workspace, every asset lives in it, and
`?workspace=` is optional. Passing the Default workspace's uuid behaves
identically to omitting the param. You only need this file when an account has
more than one workspace.
