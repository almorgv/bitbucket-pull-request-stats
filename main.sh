#!/bin/bash

# Configuration
BASE_URL="https://stash.local"
PROJECT_KEY="PRJ"
AUTH_USERNAME="username"
AUTH_USER_ID="123"
REVIEWER_USERNAME="username"
SESSION_ID="123"

# Date filtering (set to empty string to disable)
# Format: YYYY-MM-DD HH:MM:SS (e.g., "2024-01-01 00:00:00")
SINCE_DATE="2025-01-01 00:00:00"

# Function to convert datetime string to Unix timestamp (milliseconds)
datetime_to_timestamp() {
    local datetime="$1"
    if [ -z "$datetime" ]; then
        echo "0"
        return
    fi
    
    # Convert to Unix timestamp in seconds, then to milliseconds
    if command -v gdate &> /dev/null; then
        # macOS with GNU coreutils
        gdate -d "$datetime" +%s000 2>/dev/null || echo "0"
    else
        # Linux date
        date -d "$datetime" +%s000 2>/dev/null || echo "0"
    fi
}

# Function to validate datetime format
validate_datetime() {
    local datetime="$1"
    if [ -z "$datetime" ]; then
        return 0  # Empty is valid (no filtering)
    fi
    
    local timestamp=$(datetime_to_timestamp "$datetime")
    if [ "$timestamp" = "0" ]; then
        echo "Error: Invalid datetime format: '$datetime'"
        echo "Expected format: YYYY-MM-DD HH:MM:SS (e.g., '2024-01-01 00:00:00')"
        return 1
    fi
    return 0
}

# Function to get all repositories
get_repositories() {
    local url="${BASE_URL}/rest/api/latest/repos?projectkey=${PROJECT_KEY}&archived=ACTIVE&avatarSize=48&start=0&limit=200"
    
    curl -s --compressed \
        -H "X-AAUTH_USERNAME: ${AUTH_USERNAME}" \
        -H "X-AUSERID: ${AUTH_USER_ID}" \
        -H "Cookie: BITBUCKETSESSIONID=${SESSION_ID}" \
        -H "Referer: ${BASE_URL}/projects/${PROJECT_KEY}" \
        "$url"
}

# Function to get merge requests for a repository
get_merge_requests() {
    local repo_slug="$1"
    local start="${2:-0}"
    local url="${BASE_URL}/rest/api/latest/projects/${PROJECT_KEY}/repos/${repo_slug}/pull-requests?avatarSize=64&order=newest&state=ALL&draft=false&role.1=REVIEWER&AUTH_username.1=${REVIEWER_USERNAME}&start=${start}"
    
    curl -s --compressed \
        -H "X-AAUTH_USERNAME: ${AUTH_USERNAME}" \
        -H "X-AUSERID: ${AUTH_USER_ID}" \
        -H "Cookie: BITBUCKETSESSIONID=${SESSION_ID}" \
        -H "Referer: ${BASE_URL}/projects/${PROJECT_KEY}/repos/${repo_slug}/pull-requests?state=OPEN&reviewer=${AUTH_USERNAME}" \
        -H "Priority: u=0" \
        "$url"
}

# Function to process merge requests and filter
process_merge_requests() {
    local repo_slug="$1"
    local json_data="$2"
    local since_timestamp="$3"
            
    # (.properties.commentCount > 1) and
    echo "$json_data" | jq -r --arg repo_slug "$repo_slug" --arg user_name "$REVIEWER_USERNAME" --arg since_ts "$since_timestamp" '
        .values[] | 
        select(
            ( .reviewers[]? | select( .user.name == $user_name and .approved == true ) ) and
            (.author.user.name != "service-generator") and
            (if $since_ts == "0" then true else .createdDate >= ($since_ts | tonumber) end)
        ) | 
        {
            repository: $repo_slug,
            title: .title,
            state: .state,
            createdDate: (.createdDate / 1000 | strftime("%Y-%m-%d %H:%M:%S")),
            updatedDate: (.updatedDate / 1000 | strftime("%Y-%m-%d %H:%M:%S")),
            author: .author.user.name,
            commentCount: .properties.commentCount,
            approved: (.reviewers[] | select(.user.name == $user_name) | .approved),
            links: .links.self[0].href
        }
    '
}

# Function to get all merge requests for a repository (handle pagination with date filtering)
get_all_merge_requests() {
    local repo_slug="$1"
    local since_timestamp="$2"
    local start=0
    local all_results="[]"
    
    while true; do
        local response=$(get_merge_requests "$repo_slug" "$start")
        local is_last_page=$(echo "$response" | jq -r '.isLastPage')
        local values=$(echo "$response" | jq -r '.values')
        
        # If we have a date filter, check if any MRs in this page are older than the filter
        if [ "$since_timestamp" != "0" ]; then
            local oldest_in_page=$(echo "$response" | jq -r '.values | min_by(.createdDate) | .createdDate')
            
            # If the oldest MR in this page is older than our filter date, we can stop
            # but we still need to include MRs from this page that are newer
            if [ "$oldest_in_page" != "null" ] && [ "$oldest_in_page" -lt "$since_timestamp" ]; then
                # Filter this page to only include MRs newer than the date filter
                local filtered_values=$(echo "$response" | jq --arg since_ts "$since_timestamp" '
                    .values | map(select(.createdDate >= ($since_ts | tonumber)))
                ')
                
                # Merge the filtered results
                all_results=$(echo "$all_results $filtered_values" | jq -s 'add')
                
                # Stop pagination since we've reached MRs older than our filter
                break
            fi
        fi
        
        # Merge all results from this page
        all_results=$(echo "$all_results $values" | jq -s 'add')
        
        if [ "$is_last_page" = "true" ]; then
            break
        fi
        
        start=$((start + $(echo "$response" | jq -r '.size')))
    done
    
    # Create final response structure
    echo "{\"values\": $all_results}"
}

# Main execution
main() {
    # Parse command line arguments

    while [[ $# -gt 0 ]]; do
        case $1 in
            --base-url)
                BASE_URL="$2"
                shift 2
                ;;
            --project-key)
                PROJECT_KEY="$2"
                shift 2
                ;;
            --auth-username)
                AUTH_USERNAME="$2"
                shift 2
                ;;
            --auth-user-id)
                AUTH_USER_ID="$2"
                shift 2
                ;;
            --user-name)
                REVIEWER_USERNAME="$2"
                shift 2
                ;;
            --session-id)
                SESSION_ID="$2"
                shift 2
                ;;
            --since)
                SINCE_DATE="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Configuration Options:"
                echo "  --base-url URL        Stash base URL (default: https://stash.local)"
                echo "  --project-key KEY     Project key (default: PRJ)"
                echo "  --username USER       Reviewer username (default: username)"
                echo "  --auth-username USER  Your username (default: username)"
                echo "  --auth-user-id ID     Your user ID (default: 9957)"
                echo "  --session-id ID       Your Bitbucket session ID (default: 123)"
                echo ""
                echo "Filtering Options:"
                echo "  --since DATETIME      Filter merge requests created since the specified datetime"
                echo "                        Format: 'YYYY-MM-DD HH:MM:SS' (e.g., '2024-01-01 00:00:00')"
                echo ""
                echo "Other Options:"
                echo "  -h, --help           Show this help message"
                echo ""
                echo "Examples:"
                echo "  # Use with custom configuration"
                echo "  $0 --base-url 'https://git.company.com' --project-key 'DEV' --username 'john.doe' --auth-username 'john.doe' --auth-user-id '1234' --session-id 'abc123'"
                echo ""
                echo "  # Filter by date with custom config"
                echo "  $0 --username 'john.doe' --user-id '1234' --since '2024-06-01 00:00:00'"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$BASE_URL" ]; then
        echo "Error: BASE_URL is required"
        exit 1
    fi
    if [ -z "$PROJECT_KEY" ]; then
        echo "Error: PROJECT_KEY is required"
        exit 1
    fi
    if [ -z "$AUTH_USERNAME" ]; then
        echo "Error: USERNAME is required"
        exit 1
    fi
    if [ -z "$AUTH_USER_ID" ]; then
        echo "Error: USER_ID is required"
        exit 1
    fi
    if [ -z "$REVIEWER_USERNAME" ]; then
        REVIEWER_USERNAME=${AUTH_USERNAME}
        exit 1
    fi
    if [ -z "$SESSION_ID" ]; then
        echo "Error: SESSION_ID is required"
        exit 1
    fi

    # Validate datetime if provided
    if ! validate_datetime "$SINCE_DATE"; then
        exit 1
    fi

    local since_timestamp=$(datetime_to_timestamp "$SINCE_DATE")

    echo "=== Getting Merge Requests You Reviewed ==="
    echo "User ID: $AUTH_USER_ID"
    echo "Auth Username: $AUTH_USERNAME"
    echo "Reviewer Username: $REVIEWER_USERNAME"
    echo "Project: $PROJECT_KEY"
    if [ -n "$SINCE_DATE" ]; then
        echo "Since: $SINCE_DATE"
    fi
    echo

    # Get repositories
    repos_response=$(get_repositories)
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fetch repositories"
        exit 1
    fi

    # Check if we got valid JSON
    if ! echo "$repos_response" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response from repositories API"
        echo "Response: $repos_response"
        exit 1
    fi

    # Extract repository slugs
    repo_slugs=$(echo "$repos_response" | jq -r '.values[].slug')
    
    if [ -z "$repo_slugs" ]; then
        echo "No repositories found"
        exit 0
    fi

    echo "Found $(echo "$repo_slugs" | wc -l) repositories"
    echo

    # Process each repository
    found_mrs=false
    for repo_slug in $repo_slugs; do
        echo "Processing repository: $repo_slug" 2>&1
        
        # Get all merge requests for this repository
        mrs_response=$(get_all_merge_requests "$repo_slug" "$since_timestamp")
        
        if [ $? -ne 0 ]; then
            echo "  Error: Failed to fetch merge requests for $repo_slug"
            continue
        fi

        # Check if we got valid JSON
        if ! echo "$mrs_response" | jq empty 2>/dev/null; then
            echo "  Error: Invalid JSON response for $repo_slug"
            continue
        fi

        process_merge_requests "$repo_slug" "$mrs_response" "$since_timestamp"
    done
    echo "DONE"
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first."
    exit 1
fi

# Run main function with all arguments
main "$@"
