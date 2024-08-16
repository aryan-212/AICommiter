#!/bin/bash

# Set your variables
GOOGLE_API_KEY="AIzaSyAxV6iLZuwJMeJqkw1jDIPQm6BS0DTTG1g"
REPO_DIR="/home/aryan/DSAGrind"
BRANCH_NAME="master"

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
STAGED_CHANGES=$(git diff --cached --pretty=format:"%b")
ESCAPED_CHANGES=$(echo "$STAGED_CHANGES" | jq -Rsa . | jq -r @json)  # Escape special characters

REQUEST_BODY=$(
  cat <<EOF
{
  "contents": [{
    "parts": [{
      "text": "Generate a commit message for the following changes: $ESCAPED_CHANGES"
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

# Print the raw API response for debugging
echo "Raw API response: $RESPONSE"

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
