<details>
  <summary style="font-size: 1.3em; font-weight: bold; padding: 14px; background: #334155; color: white; border-radius: 10px; cursor: pointer; margin: 10px 0;">
    <strong>git_config_xdg &mdash; Omarchy Git XDG Config Proposal</strong>
  </summary>

  <div style="margin: 18px 0; padding: 12px 18px; background: #dbeafe; border-radius: 8px; border-left: 5px solid #2563eb; font-size:1.1em;">
    <strong>author:</strong> <a href="https://github.com/phaedrusflow" target="_blank" style="color: #1d4ed8;">@phaedrusflow</a><br>
    <strong>summary:</strong><br>
    Optimized Git configuration to accelerate status, checkout, fetch, and repack for large monorepos and modern developer workstations in alignment with X Desktop Group (XDG protocols) .<br>
  </div>
      📖 <strong>References:</strong>
    <a href="https://git-scm.com/docs/git-config" target="_blank" style="color:#2563eb;font-weight:bold;">Git Config Documentation</a> |
    <a href="https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html" target="_blank" style="color:#059669;font-weight:bold;">XDG Base Directory Spec</a>
  </div>

  <details>
    <summary style="padding: 8px; background: #475569; color: #fff; border-radius: 6px; cursor: pointer;">
      Show Proposed <em>.gitconfig</em>
    </summary>

```config
# ~/.config/git/config
######################
[feature]
manyFiles = true

[core]
preloadindex = true
untrackedCache = true
fsmonitor = true
commitgraph = true
bigFileThreshold = 50m
packedGitLimit = 512m
packedGitWindowSize = 512m

[pack]
threads = 0
windowMemory = 5g
packSizeLimit = 2g

[index]
version = 4
skipHash = true

[fetch]
writeCommitGraph = true

[checkout]
workers = -1
thresholdForParallelism = 1000

[gc]
auto = 8000
```

<details>
    <summary style="padding: 8px; background: #1e293b; color: #fff; border-radius: 6px; cursor: pointer;">
      Git Config by the numbers
    </summary>

| Section   | Key                      | Type   | Values/Example                | Description                                                                           |
|-----------|--------------------------|--------|-------------------------------|---------------------------------------------------------------------------------------|
| feature   | manyFiles                | bool   | true / false                  | Optimize for repos with a very large number of files.                                 |
| core      | preloadindex             | bool   | true / false                  | Preloads Git index in background; speeds up `git status`.                             |
| core      | untrackedCache           | bool   | true / false                  | Caches untracked files for faster operations; best for large repos.                   |
| core      | fsmonitor                | bool   | true / false                  | Uses fsmonitor (if available) to detect changes, reducing scans (needs OS support).   |
| core      | commitgraph              | bool   | true / false                  | Enables commit-graph for faster queries on history, merges, and branches.             |
| core      | bigFileThreshold         | size   | e.g. 50m                       | Files larger than this size are considered "big"; skips some expensive scanning.      |
| core      | packedGitLimit           | size   | e.g. 512m                      | Max RAM used for memory-mapping packfiles.                                            |
| core      | packedGitWindowSize      | size   | e.g. 512m                      | Window for accessing packfiles in memory.                                             |
| pack      | threads                  | int    | 0 (auto), N                    | Auto-selects number of threads for repacking based on CPU cores.                      |
| pack      | windowMemory             | size   | e.g. 5g                        | Max RAM for delta compression windows when repacking.                                 |
| pack      | packSizeLimit            | size   | e.g. 2g                        | Cap on a single new packfile; keeps packs manageable.                                 |
| index     | version                  | int    | 4                              | Enables index format v4 for faster, smaller index.                                    |
| index     | skipHash                  | bool   | true / false                  | Skips hash on index write (faster, slight safety trade-off).                          |
| fetch     | writeCommitGraph         | bool   | true / false                  | Automatically updates commit graph after fetch.                                       |
| checkout  | workers                  | int    | -1 (auto), N                   | Auto-parallelizes file checkout for multi-core CPUs.                                  |
| checkout  | thresholdForParallelism  | int    | 1000                           | Only parallelize checkout when >1,000 files update to avoid small-repo overhead.      |
| gc        | auto                     | int    | 8000                           | Run GC less often; better for repos with many objects.                                |

  </details>

</details>
