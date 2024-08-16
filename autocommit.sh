#!/bin/bash

# Set your variables
GOOGLE_API_KEY="AIzaSyAxV6iLZuwJMeJqkw1jDIPQm6BS0DTTG1g"
REPO_DIR=$(pwd)
BRANCH_NAME="master"

# Function to display help message
function display_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Commit and push changes to a Git repository."
  echo "Options:"
  echo "  -h, --help          Display this help message"
  echo "  -d, --directory     Set the directory of the Git repository"
  echo "  -b, --branch        Set the branch to push changes to"
}

# Parse command-line arguments
while (( "$#" )); do
  case "$1" in
    -h|--help)
      display_help
      exit 0
      ;;
    -d|--directory)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        REPO_DIR=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -b|--branch)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        BRANCH_NAME=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

# Navigate to your Git repository
cd "$REPO_DIR" || {
  echo "Directory $REPO_DIR not found."
  exit 1
}

git add .

# Check if there are staged changes
if git diff --cached --quiet; then
  echo "No staged changes to commit."
  exit 0
fi

# Prepare the data to send to the Gemini API
STAGED_CHANGES=$(git diff --cached)
ESCAPED_CHANGES=$(echo "$STAGED_CHANGES" | jq -Rsa . | jq -r @json) # Escape special characters

REQUEST_BODY=$(
  cat <<EOF
{
  "contents": [{
    "parts": [{
      "text": "Generate a commit message for the following changes: $STAGED_CHANGES"
    }]
  }]
}
EOF
)

# Call the Gemini API to generate a commit message using the provided curl command
RESPONSE=$(curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$GOOGLE_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "$REQUEST_BODY" 2>/dev/null)

# Extract the commit message from the response
COMMIT_MESSAGE=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text')

# Check if the commit message was successfully extracted
if [ -z "$COMMIT_MESSAGE" ]; then
  echo "Failed to generate commit message."
  exit 1
fi

# Commit the changes
git commit -m "$COMMIT_MESSAGE"

# Push the changes to the correct branch
git push origin "$BRANCH_NAME"
echo "Changes committed and pushed with message: $COMMIT_MESSAGE"
