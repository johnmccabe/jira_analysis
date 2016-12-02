This repo contains a random selection of Jira analysis scripts.

## ticket_to_pr_jira_analysis.rb
This script will, for a given epic, parse all the child tickets recording which repos then had PRs raised.

The intent here was that for an epic containing tickets associated with CI blockers or failures I could see the repos which ultimately required a change to close the ticket - ie were causing the problem.

It should be noted that this approach provides only a rough idea as to the root cause.

Also this is hacky hacky ruby so don't go looking for best practice here !!

### Using the script
1. Check out this repo

2. Install the requirements
    ```
    bundle install --path .bundle
    ```

3. Create a `./config.yml` in the same directory as the script file with your Jira url, user details and epic id (I know, I know, OAUTH, I don't have that level of access to my local Jira). For example
    ```
    ---
    jira:
        rest_endpoint: 'https://tickets.yourcompany.com'
        username: joe.bloggs
        password: mysupersecretjirapassword
        epic: CI-12345
    ```

4. Run the script
    ```
    ./ticket_to_pr_jira_analysis.rb
    ```

5. The epic will first be queried to figure out what children exist and after a few seconds you should see a progress bar while the script processes each child in turn.
    ```
    $ ./ticket_to_pr_jira_analysis.rb
    Time: 00:02:58 ========                         25% Progress
    ```

6. On completion you will have some yml datafiles in an `./output` directory
    - `repos_to_ticket_count.yml` - hash of repositories to the number of tickets which resulted in a PR
    - `tickets_to_repo_count.yml` - hash of ticket ids to the number of repositories which had a PR raised
    - `tickets_to_repos.yml` - hash of tickets to an array of repositories which had a PR raised

