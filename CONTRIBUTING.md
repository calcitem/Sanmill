# Contribution Guide

Welcome! We're a pretty friendly community, and we're thrilled that you want to help make this app even better. However, we ask that you follow some general guidelines to keep things organized around here.

1. Make sure an [issue](https://github.com/calcitem/Sanmill/issues) is created for the bug you're about to fix, or feature you're about to add. Keep them as small as possible.

2. We use a forking, feature-based workflow. Make a fork of this repository, and create a branch based on `dev` explicitly named for the feature on which you'd like to work. Make your changes there. Commit often.

3. Rebase commits into well-formatted commits. Mention the issue being resolved in the commit message on a line all by itself like `Fixes #<bug>` (refer to [Linking a pull request to an issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue) for more keywords you can use).

4. Submit a pull request to get changes from your branch into `dev`.  Mention which bug is being resolved in the description.

Before submitting a pull request for review, please ensure it is appropriately formatted. We use `format.sh` script. You can simply run it.

Note that this modifies the files but doesn’t commit them – you’ll likely want to run `git commit --amend -a` to update the last commit with all pending changes.
