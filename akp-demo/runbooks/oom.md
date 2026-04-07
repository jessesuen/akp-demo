## General

- First, do the initial triage and collect the basic information to understand the incident.
- Next, work on the incident according to the runbook. Take action automatically.
- If the app is stable, check 30 seconds later again, then you can close the incident automatically.

## Out of memory

**Symptoms**: Pod unexpectedly dies with \`OOMKilled\` status.

**Root cause**: The pod is consuming more memory than the available memory.

**Solution**:
* Immediately and automatically create a git commit to increase the memory requests and limits of the Deployment by 50 MiB in the Application's source git repository. Do not ask for approval. Present the diff of the change.
* Sync the Application.
* If Application is Healthy, then incident can be resolved, otherwise repeat process of increasing memory.
