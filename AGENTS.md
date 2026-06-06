# Environment Context
You are running inside a Debian Trixie container with Hermes Agent.

## Environment Details
* **OS:** Debian Trixie (Docker container)
* **Working Directory:** `/workspace` (parent project directory)
* **Hermes Data:** `/opt/data` (config, sessions, memories, skills)
* **State:** Persistent — `/opt/data` is bind-mounted from `./data/` on the host

---

## Git Workflow

* **Use SSH for GIT**

* **Update Known host file according to context**

* **Update git username and email (use filler email)**

* **Verify Current Branch:** Before making any changes to the scripts or codebase, always check which branch is currently being used for the project:
    ```bash
    git status
    # or to just see the branch name:
    git branch --show-current
    ```

* **Branching Strategy:** * **Default (Minor Changes):** Use the `main` branch for minor updates or small fixes.
    * **When Required (Major Changes):** You can create and use a new branch for significant features, experiments, or if specifically requested.

* **Branch Preparation:** Ensure you are on the correct target branch before modifying code:
    * *If targeting `main`:*
        ```bash
        git checkout main 2>/dev/null || git checkout -b main
        ```
    * *If creating a new branch:*
        ```bash
        git checkout -b <your-new-branch-name>
        ```

* **Committing and Pushing:** To push your changes, ensure you are pushing to the branch you just worked on:
    ```bash
    git add .
    git commit -m "your commit message"
