# Omarchy Snippet Manager

## 1. Feature Overview

The **Omarchy Snippet Manager** is a native, minimal GUI for saving frequently used text and code snippets and quickly copying them when needed.

The feature is designed around one principle:

> **Open → find → one click → copied.**

It must feel instant and lightweight, not like a full notes application or a graphical terminal.

The user should never need to edit files manually or understand the underlying storage format.

---

# 2. Core UX

Entry point:

```text
Omarchy Menu
└── Snippets
```

Main interface:

```text
Snippets
────────────────────────

🔍 Search...

Docker cleanup
DRF serializer
Git commit
Nginx config
PostgreSQL query
Bash aliases
```

Clicking a snippet **once** immediately copies its content to the clipboard.

After copying:

```text
✓ Copied
```

The menu may close automatically after a successful copy.

The primary workflow must never require opening a detail page.

---

# 3. Minimal Data Model

A snippet contains only:

```text
Snippet
├── Name
└── Content
```

No additional metadata is required for the MVP.

Do not require:

- category
- tags
- language
- description
- author
- cloud ID
- account ID
- workspace
- project
- favorite metadata

The feature should remain intentionally minimal.

---

# 4. Required Operations

The MVP supports:

```text
Create
Search
Copy
Edit
Delete
Import
Export
```

Nothing else is required for the first version.

---

# 5. One-Click Copy

This is the most important interaction.

When the user clicks a snippet:

```text
Snippet
   ↓
Clipboard
   ↓
✓ Copied
```

There must be no:

```text
Open details
Confirm
Click Copy
```

sequence.

One click is enough.

The copied clipboard content must be exactly the stored `content`.

No formatting, trimming, escaping, or transformation should alter the actual snippet content.

---

# 6. Search

Search must be fast and lightweight.

The main search field is always available.

Search should match at minimum:

```text
Name
Content
```

Example:

```text
Search: serializer
```

Results:

```text
DRF User Serializer
Serializer Validation
Nested Serializer
```

Search must remain responsive even when the user has a large number of snippets.

The UI should not require the user to manually browse categories.

---

# 7. Create

The create UI should be minimal:

```text
New Snippet

Name
[ Docker cleanup ]

Content
┌──────────────────────────────┐
│ docker system prune -af      │
└──────────────────────────────┘

[Cancel]                 [Save]
```

Only these fields are required:

```text
Name
Content
```

A snippet cannot be saved with an empty name.

Content may be empty only if there is a deliberate UX reason to support empty snippets; otherwise reject empty content.

---

# 8. Edit

Editing opens the same minimal form:

```text
Edit Snippet

Name
[ Docker cleanup ]

Content
┌──────────────────────────────┐
│ docker system prune -af      │
└──────────────────────────────┘

[Cancel]                 [Save]
```

Saving replaces the existing snippet.

The snippet identity must remain stable internally where possible.

---

# 9. Delete

Delete is a secondary action.

Example:

```text
Delete "Docker cleanup"?

[Cancel]     [Delete]
```

Deletion must remove only that snippet.

It must not affect:

- other snippets
- clipboard history
- system files
- Omarchy configuration
- installed applications

---

# 10. Local-Only Privacy

This is a fundamental requirement.

All snippets must be stored **only on the user's local machine**.

The feature must not send snippet data to:

- remote servers
- cloud storage
- analytics services
- telemetry systems
- external APIs
- third-party services

There must be no automatic synchronization.

The application must not require an account.

The snippet content must never leave the user's machine unless the user explicitly exports it to a local file.

This is especially important because snippets may contain:

- API keys
- passwords
- private configuration
- internal code
- commands
- credentials

The feature must therefore be **local-only by design**.

---

# 11. Storage

The exact storage location must follow existing Omarchy conventions.

Before implementation, inspect the repository for the appropriate user-local configuration/data location.

Do not invent a storage convention if Omarchy already has one.

The storage must be user-owned and local.

File permissions should prevent other users from unnecessarily reading private snippet data.

---

# 12. Import / Export

Import and Export are required MVP functionality.

They must use **exactly the same file format**.

The basic flow is:

```text
Export
   ↓
snippets.json
   ↓
Import
```

A file exported from one Omarchy installation must be directly importable into another installation using the same format.

---

# 13. Standard Snippet File Format

Use a versioned JSON format.

Example:

```json
{
  "version": 1,
  "snippets": [
    {
      "name": "Docker cleanup",
      "content": "docker system prune -af"
    },
    {
      "name": "DRF Serializer",
      "content": "class UserSerializer(serializers.ModelSerializer):\n    ..."
    }
  ]
}
```

The format intentionally contains only:

```text
version
snippets[]
  ├── name
  └── content
```

Do not add unnecessary metadata.

---

# 14. Format Versioning

The exported file must contain:

```json
"version": 1
```

This allows future versions of the Snippet Manager to evolve the format without breaking existing exports.

The importer must validate the version before importing.

Unsupported versions must produce a clear error instead of silently importing incorrect data.

---

# 15. Export

Export must allow the user to choose a local destination.

Example:

```text
Snippets
   ↓
Export
   ↓
Save file
   ↓
snippets.json
```

The exported file contains all snippets unless a future version explicitly adds selective export.

The export operation must not send the data anywhere remotely.

---

# 16. Import

Import flow:

```text
Import
   ↓
Choose snippets.json
   ↓
Validate
   ↓
Preview / resolve conflicts
   ↓
Import
```

The importer must validate:

- JSON syntax
- top-level structure
- supported version
- presence of `snippets`
- snippet object structure
- required `name`
- required `content`

Invalid files must not partially modify the local snippet database.

---

# 17. Import Large Collections

Import must support a large number of snippets through a single file.

For example:

```text
snippets.json
├── 10 snippets
├── 100 snippets
├── 500 snippets
└── 1000+ snippets
```

The user should not have to import snippets one-by-one.

The importer should process the complete file as one logical operation.

---

# 18. Import Conflict Handling

If an imported snippet conflicts with an existing snippet, the GUI must make the behavior explicit.

Possible choices:

```text
"DRF Serializer" already exists.

○ Skip
○ Replace
○ Keep both
```

The implementation must not silently overwrite existing snippets.

If `Keep both` is supported, the new snippet needs a deterministic unique name.

Example:

```text
DRF Serializer
DRF Serializer (Imported)
```

The exact naming strategy should remain simple and predictable.

---

# 19. Import Atomicity

Import should behave as one logical operation.

If validation fails:

```text
No snippets are changed.
```

If an import operation cannot complete safely:

```text
Previous local state remains intact.
```

Do not partially import a large file and then leave the user with an unknown state.

---

# 20. Export / Import Compatibility

The following must always work:

```text
Omarchy A
    ↓
Export
    ↓
snippets.json
    ↓
Omarchy B
    ↓
Import
```

The same file format must be used in both directions.

Export must produce files that the importer itself can consume.

This should be covered by automated round-trip tests:

```text
Create snippets
    ↓
Export
    ↓
Import into clean fixture
    ↓
Compare
    ↓
Name + Content identical
```

---

# 21. Clipboard Behavior

The clipboard operation must be local.

The feature should use the system clipboard mechanism already used by Omarchy rather than implementing a second clipboard system.

The copied content must remain exactly:

```text
snippet.content
```

No logging of snippet content is allowed.

Notifications must never expose the actual snippet content.

Use only:

```text
Copied
```

or:

```text
Copied "Snippet Name"
```

if displaying the name is considered safe.

Never display the full content in a notification.

---

# 22. Performance

The manager is intended for fast daily use.

The UI must remain responsive with many snippets.

Requirements:

- Search should be local.
- No network operation may occur during normal use.
- Opening the Snippets panel should not require a remote operation.
- Copy should be immediate.
- Search should not require spawning a process for every keystroke.
- Import/export can be slower because they process files, but should still avoid unnecessary work.

If the collection becomes large, use an efficient local index/data structure rather than repeatedly scanning and reparsing unnecessarily.

---

# 23. Keyboard Workflow

Keyboard support should complement the one-click mouse workflow.

Preferred flow:

```text
Open Snippets
    ↓
Type search
    ↓
Select result
    ↓
Enter
    ↓
Copied
```

The exact global shortcut should be determined during implementation based on existing Omarchy keybinding conventions and conflict checks.

A global shortcut is useful but is not required to define the core Snippet Manager behavior.

---

# 24. UI Design Principles

The interface must be:

- minimal
- compact
- fast
- keyboard-friendly
- easy to scan
- visually consistent with Omarchy

Avoid:

- large cards
- unnecessary metadata
- complex navigation
- detail pages for copying
- excessive confirmation dialogs
- unnecessary animations
- category management
- dashboards

The primary screen should focus almost entirely on:

```text
Search
+
Snippet list
```

---

# 25. Secondary Actions

Normal snippet interaction:

```text
Click
→ Copy
```

Secondary actions should be accessible without cluttering the main list.

Possible interaction:

```text
Right click / context menu
```

or:

```text
...
```

Actions:

```text
Edit
Delete
```

The exact UI mechanism should follow existing Omarchy menu conventions.

---

# 26. Empty State

If there are no snippets:

```text
No snippets yet.

Save commands and code you use often.

[ + New Snippet ]
```

Keep the empty state concise.

---

# 27. No Categories in MVP

Do not add:

```text
Categories
Tags
Folders
Favorites
Languages
Projects
```

to the MVP.

Search is sufficient for organizing a personal snippet collection.

These can be considered only if real usage demonstrates a need.

---

# 28. No Cloud Sync

Cloud synchronization is explicitly out of scope.

Do not add:

```text
Sign in
Account
Cloud
Sync
Backup service
```

The only supported transfer mechanism is explicit user-controlled local Import/Export.

---

# 29. Security Requirements

Because snippets can contain sensitive information:

- Never log snippet content.
- Never send snippet content over the network.
- Never include snippet content in telemetry.
- Never include snippet content in error reports.
- Do not expose content in desktop notifications.
- Use local user-owned storage.
- Preserve file permissions.
- Import only user-selected local files.
- Export only to a user-selected local destination.

Import/export are explicit user actions.

---

# 30. Architecture

The feature should be implemented as a native Omarchy component, not as a separate package.

Conceptual architecture:

```text
Omarchy Menu
      ↓
Snippet Manager UI
      ↓
Local Snippet Store
      ↓
Local JSON / storage
```

Clipboard:

```text
Snippet UI
    ↓
Existing local clipboard mechanism
```

Import:

```text
Local file
    ↓
Parser
    ↓
Validator
    ↓
Conflict resolver
    ↓
Local store
```

Export:

```text
Local store
    ↓
Serializer
    ↓
snippets.json
```

No remote layer exists.

---

# 31. Storage Abstraction

The UI must not directly manipulate storage files.

Use a small local storage abstraction:

```text
SnippetStore
├── list()
├── search(query)
├── create(name, content)
├── update(id, name, content)
├── delete(id)
├── import(file)
└── export(file)
```

The exact implementation can use JSON or another local format if Omarchy conventions make that preferable.

The Import/Export interchange format must remain the documented versioned JSON format.

---

# 32. Validation

Validate at the storage boundary.

Create/update:

```text
name != empty
```

Import:

```text
valid JSON
supported version
valid snippets array
valid name
valid content
```

Reject invalid data before persistence.

---

# 33. Error Handling

Errors should be concise and user-readable.

Examples:

```text
Could not save snippet.
```

```text
Invalid snippet file.
```

```text
Unsupported snippet format version.
```

```text
A snippet with this name already exists.
```

Do not expose stack traces, Lua code, file parser internals, or raw implementation errors in the normal UI.

Detailed errors may be available through existing developer/debug mechanisms.

---

# 34. Duplicate Names

The snippet model has only `Name + Content`, so names should be treated as user-facing identifiers.

The implementation should prevent accidental ambiguity.

If duplicate names are not allowed:

```text
A snippet named "Docker cleanup" already exists.
```

If duplicates are allowed for a concrete reason, the UI must still make them distinguishable.

For MVP, **unique names are recommended** because they make search and import conflict handling simpler.

---

# 35. Import Conflict Model

Recommended behavior:

```text
Same name + same content
→ Skip as already existing

Same name + different content
→ Ask:
   Skip
   Replace
   Keep both
```

This avoids unnecessary duplicates during repeated imports.

---

# 36. Testing

Automated tests should cover:

### CRUD

```text
create
read
search
update
delete
```

### Copy

```text
stored content
      ==
clipboard content
```

### Import

```text
valid JSON
invalid JSON
unsupported version
missing fields
large collection
duplicate/conflicting snippets
```

### Export

```text
local snippets
      ↓
JSON
      ↓
valid format
```

### Round Trip

```text
Create
 ↓
Export
 ↓
Import
 ↓
Compare
```

Expected:

```text
Name identical
Content identical
```

### Privacy

There must be no network dependency for normal Snippet Manager operation.

Tests should ensure the feature does not invoke remote APIs or network services.

---

# 37. MVP Scope

The first implementation includes exactly:

```text
Snippet Manager
├── Search
├── Create
├── 1-click Copy
├── Edit
├── Delete
├── Import
└── Export
```

Data:

```text
Name
Content
```

Storage:

```text
Local only
```

Transfer:

```text
Explicit local JSON Import / Export
```

No cloud.

No categories.

No tags.

No favorites.

No analytics.

No remote sync.

---

# 38. Success Criteria

The feature is successful when a user can:

1. Open Snippets quickly.
2. Immediately search their snippets.
3. Copy a snippet with exactly one click.
4. Create a snippet with only a name and content.
5. Edit an existing snippet.
6. Delete an existing snippet.
7. Export all snippets to one standard JSON file.
8. Import that same JSON format on another Omarchy installation.
9. Import large collections in one operation.
10. Resolve duplicate/conflicting snippets explicitly.
11. Keep all snippet data exclusively local unless the user explicitly exports it.
12. Use the feature without an account or network connection.
13. Use the feature without ever seeing configuration syntax.

---

# 39. Final UX Principle

The entire feature should feel like:

```text
Open
 ↓
Search
 ↓
Click
 ↓
Copied
```

The user should never feel like they are managing a database.

The user should never feel like they are editing a configuration file.

The Snippet Manager exists to make frequently reused content **immediately available with the least possible friction**.
