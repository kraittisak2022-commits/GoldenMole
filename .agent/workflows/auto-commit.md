---
description: Auto commit and push changes to GitHub after each edit
---

# Auto Commit & Push Workflow

After making code changes, automatically commit and push to GitHub.

## Steps

// turbo-all

1. Stage all changes:
```
git add -A
```

2. Commit with a descriptive message summarizing the changes:
```
git commit -m "<descriptive message about what was changed>"
```

3. Push to the main branch:
```
git push origin main
```

## Notes
- Always use a descriptive commit message in Thai or English summarizing the actual changes
- Run this workflow after every set of code modifications
- If push fails due to conflicts, pull first with `git pull --rebase origin main` then push again
