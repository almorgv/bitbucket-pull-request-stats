# bitbucket-pull-request-stats
Get all pull requests approved by user in each repositiory of specified project

```bash
Usage: main.sh [OPTIONS]

Configuration Options:
  --base-url URL        Stash base URL
  --project-key KEY     Project key
  --username USER       Reviewer username
  --auth-username USER  Your username
  --auth-user-id ID     Your user ID
  --session-id ID       Your Bitbucket session ID (from cookie)

Filtering Options:
  --since DATETIME      Filter merge requests created since the specified datetime
                        Format: 'YYYY-MM-DD HH:MM:SS' (e.g., '2024-01-01 00:00:00')

Other Options:
  -h, --help           Show this help message

Examples:
  # Use with custom configuration
  main.sh --base-url 'https://git.company.com' --project-key 'DEV' --username 'john.doe' --auth-username 'john.doe' --auth-user-id '1234' --session-id 'abc123'

  # Filter by date with custom config
  main.sh --username 'john.doe' --user-id '1234' --since '2024-06-01 00:00:00'
```
