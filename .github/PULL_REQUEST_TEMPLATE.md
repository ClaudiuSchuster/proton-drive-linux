## What changed

Describe the observable PDrive behavior and why the change belongs in this
focused Proton Drive client.

## Safety impact

State the effect on credentials, the RC socket, active transfers, Dirty VFS
data, metadata consistency, service restarts and privileged setup. Write “none”
only after checking each boundary.

## Verification

- [ ] `make verify`
- [ ] Behavior-specific regression coverage was added or the reason it is not
      needed is explained.
- [ ] UI changes were exercised in English and German, at minimum width and in
      both idle and active fixtures.
- [ ] No real credentials, tokens, private paths or personal filenames appear
      in code, fixtures, logs or screenshots.
- [ ] No active transfer was interrupted and no Dirty cache data was deleted.
- [ ] User-facing documentation and version metadata are updated where needed.
