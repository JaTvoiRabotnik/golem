# golem
Automated code completer

This is just a few prompts that make so-called "vibe coding" on Claude safer. It relies on small and very well defined issues, in GitHub, which the agent can work through in a single context window (without needing to auto-compact).

The `automate.sh` script should only be used once you feel that the agent has gained enough trust to work unsupervised, in multiple issues in parallel. The instructions explicitly tell the agent to commit the changes to a branch, and so far I haven't seen it deviate from that, but still proceed with caution. If working in a production environment, it's probably best to have the auto-deployment happening from a non-standard branch name (i.e., not "main" or "master"), so that the AI can't guess it, and you then manually merge the changes if and when you feel they are ready.

It's advisable to work from the Claude Code UI first, so that it can learn what commands you feel safe for it to perform automatically. Once you have a good whitelist built (in settings.local.json), then you can remove the `--dangerously-skip-permissions` parameter from the automate.sh script (grep for that to find where it is).

This repo is public, so feel free to create issues, or submit PRs with your suggestions for improvement.


