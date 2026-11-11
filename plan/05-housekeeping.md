# Housekeeping on GitHub

The cloud session may not delete remote branches (the server refuses it), so these are left.
All of them are fully contained in `main`.

```bash
gh api -X DELETE repos/fol2/helloforever/git/refs/heads/cursor/helloforever-v060-95d6
gh api -X DELETE repos/fol2/helloforever/git/refs/heads/jamesto/jolly-ritchie-28psy8
gh api -X DELETE repos/fol2/helloforever/git/refs/heads/jamesto/modest-ride-gzjs6x   # after its PR is merged
```

`jamesto/jolly-ritchie-28psy8` has one commit that is not an ancestor of `main`; its tree is
identical to the squash merge of pull request #2, so nothing is lost.

Then, in Settings → General → Pull Requests, tick **Automatically delete head branches**.
