#!/usr/bin/env python3

"""
Script name: search-commit-message.py
Purpose: Search for commits containing a specified string in commit messages
         across all branches (local and remote) and display which branches
         contain each matching commit.
"""

import subprocess
import sys
from collections import defaultdict


def run_git_command(command):
    """Execute a git command and return its output."""
    try:
        result = subprocess.run(
            command,
            shell=True,
            check=True,
            capture_output=True,
            text=True,
            encoding='utf-8'
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return ""
    except UnicodeDecodeError:
        # Try with a different encoding if UTF-8 fails
        try:
            result = subprocess.run(
                command,
                shell=True,
                check=True,
                capture_output=True,
                text=False
            )
            return result.stdout.decode('gbk', errors='ignore').strip()
        except:
            return ""


def print_usage():
    """Display usage information."""
    print("Usage: search-commit-message.py <search_string>")
    print("")
    print("Description:")
    print("  Search for commits containing the specified string in commit messages")
    print("  across all branches (local and remote).")
    print("")
    print("Arguments:")
    print("  search_string    The string to search for in commit messages")
    print("")
    print("Example:")
    print('  search-commit-message.py "Fix bug"')
    print('  search-commit-message.py "Add feature"')


def main():
    # Check if search string is provided
    if len(sys.argv) < 2:
        print("Error: No search string provided.")
        print("")
        print_usage()
        sys.exit(1)
    
    search_string = sys.argv[1]
    
    # Check if we are in a Git repository
    if not run_git_command("git rev-parse --git-dir"):
        print("Error: Not in a Git repository.")
        sys.exit(1)
    
    print("=" * 60)
    print(f'Searching for commits with message containing: "{search_string}"')
    print("=" * 60)
    print()
    
    # Fetch latest remote branches
    print("Fetching latest remote branches...")
    run_git_command("git fetch --all --quiet")
    print()
    
    print("Scanning branches for matching commits...")
    print()
    
    # Dictionary to store commit hash -> list of branches
    commit_to_branches = defaultdict(list)
    
    # Get all local branches
    local_branches = run_git_command("git for-each-ref --format=%(refname:short) refs/heads/")
    if local_branches:
        for branch in local_branches.split('\n'):
            branch = branch.strip()
            if not branch:
                continue
            
            # Get all matching commits in this branch
            cmd = f"git log {branch} --grep={search_string} --format=%H"
            commits = run_git_command(cmd)
            if commits:
                for commit_hash in commits.split('\n'):
                    commit_hash = commit_hash.strip()
                    if commit_hash:
                        commit_to_branches[commit_hash].append(f"[local] {branch}")
    
    # Get all remote branches
    remote_branches = run_git_command("git for-each-ref --format=%(refname:short) refs/remotes/ | grep -v HEAD$")
    if remote_branches:
        for branch in remote_branches.split('\n'):
            branch = branch.strip()
            if not branch:
                continue
            
            # Get all matching commits in this branch
            cmd = f"git log {branch} --grep={search_string} --format=%H"
            commits = run_git_command(cmd)
            if commits:
                for commit_hash in commits.split('\n'):
                    commit_hash = commit_hash.strip()
                    if commit_hash:
                        commit_to_branches[commit_hash].append(f"[remote] {branch}")
    
    # Check if any commits were found
    if not commit_to_branches:
        print(f'No commits found containing "{search_string}" in their messages.')
        sys.exit(0)
    
    print("Found matching commits:")
    print("=" * 60)
    print()
    
    # Process each commit
    for commit_hash in sorted(commit_to_branches.keys(), key=lambda x: -int(run_git_command(f'git log -1 --format=%at {x}') or '0')):
        # Get commit information
        commit_subject = run_git_command(f'git log -1 --format=%s {commit_hash}')
        commit_author = run_git_command(f'git log -1 --format=%an {commit_hash}')
        commit_date = run_git_command(f'git log -1 --format=%ad --date=short {commit_hash}')
        commit_body = run_git_command(f'git log -1 --format=%b {commit_hash}')
        
        print(f"Commit: {commit_hash}")
        print(f"Author: {commit_author}")
        print(f"Date:   {commit_date}")
        print(f"Subject: {commit_subject}")
        
        # Display commit body if it exists and is not empty
        if commit_body:
            print()
            print("Message:")
            for line in commit_body.split('\n'):
                print(f"    {line}")
        
        print()
        print("Branches containing this commit:")
        
        # Remove duplicates and sort branches
        branches = sorted(set(commit_to_branches[commit_hash]))
        for branch_info in branches:
            print(f"  - {branch_info}")
        
        print()
        print("-" * 60)
        print()
    
    print("Search completed.")


if __name__ == "__main__":
    main()

