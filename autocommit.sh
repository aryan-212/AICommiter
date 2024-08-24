#!/bin/bash

# Set your variables
GOOGLE_API_KEY="AIzaSyAxV6iLZuwJMeJqkw1jDIPQm6BS0DTTG1g"
REPO_DIR=$(pwd)
BRANCH_NAME="master"
LOG_FILE="git_auto_commit.log"
DRY_RUN=0
UNDO_LAST=0

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to display help message
function display_help() {
  echo -e "${CYAN}Usage: $0 [OPTIONS]${RESET}"
  echo -e "${CYAN}Commit and push changes to a Git repository.${RESET}"
  echo -e "${CYAN}Options:${RESET}"
  echo -e "${CYAN}  -h, --help          Display this help message${RESET}"
  echo -e "${CYAN}  -d, --directory     Set the directory of the Git repository${RESET}"
  echo -e "${CYAN}  -b, --branch        Set the branch to push changes to${RESET}"
  echo -e "${CYAN}  -n, --dry-run       Perform a trial run with no changes made${RESET}"
  echo -e "${CYAN}  -u, --undo          Undo the last commit${RESET}"
}

# Parse command-line arguments
while (("$#")); do
  case "$1" in
  -h | --help)
    display_help
    exit 0
    ;;
  -d | --directory)
    if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
      REPO_DIR=$2
      shift 2
    else
      echo -e "${RED}Error: Argument for $1 is missing${RESET}" >&2
      exit 1
    fi
    ;;
  -b | --branch)
    if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
      BRANCH_NAME=$2
      shift 2
    else
      echo -e "${RED}Error: Argument for $1 is missing${RESET}" >&2
      exit 1
    fi
    ;;
  -n | --dry-run)
    DRY_RUN=1
    shift
    ;;
  -u | --undo)
    UNDO_LAST=1
    shift
    ;;
  --) # end argument parsing
    shift
    break
    ;;
  -* | --*=) # unsupported flags
    echo -e "${RED}Error: Unsupported flag $1${RESET}" >&2
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
  echo -e "${RED}Directory $REPO_DIR not found.${RESET}"
  exit 1
}

# If undo flag is set, undo the last commit
if [ $UNDO_LAST -eq 1 ]; then
  git reset --soft HEAD~1
  echo -e "${GREEN}Last commit has been undone.${RESET}"
  exit 0
fi

git add .

# Check if there are staged changes
if git diff --cached --quiet; then
  echo -e "${YELLOW}No staged changes to commit.${RESET}"
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

# Function to generate commit message using Gemini API
function generate_commit_message() {
  RESPONSE=$(curl -s -X POST \
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$GOOGLE_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "$REQUEST_BODY" 2>/dev/null)

  echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text'
}

# Generate initial commit message
COMMIT_MESSAGE=$(generate_commit_message)

# Check if the commit message was successfully extracted
if [ -z "$COMMIT_MESSAGE" ]; then
  echo -e "${RED}Failed to generate commit message.${RESET}"
  exit 1
fi

# If dry run flag is set, print the commit message and exit
if [ $DRY_RUN -eq 1 ]; then
  echo -e "${CYAN}Dry run: Commit message would be: ${GREEN}$COMMIT_MESSAGE${RESET}"
  exit 0
fi

# Loop for user confirmation
while true; do
  echo -e "${CYAN}Proposed commit message:${RESET}"
  echo -e "${GREEN}$COMMIT_MESSAGE${RESET}"
  echo -e "${CYAN}Do you want to use this commit message? (Y/N): ${RESET}"
  read -r USER_INPUT

  case $USER_INPUT in
  [Yy]*)
    # Commit the changes
    git commit -m "$COMMIT_MESSAGE"
    git push origin "$BRANCH_NAME"
    echo -e "${GREEN}Changes committed and pushed with message: $COMMIT_MESSAGE${RESET}"
    exit 0
    ;;
  [Nn]*)
    echo -e "${CYAN}Generating a new commit message...${RESET}"
    COMMIT_MESSAGE=$(generate_commit_message)
    if [ -z "$COMMIT_MESSAGE" ]; then
      echo -e "${RED}Failed to generate commit message.${RESET}"
      exit 1
    fi
    ;;
  *)
    echo -e "${YELLOW}Please answer Y (yes) or N (no).${RESET}"
    ;;
  esac
done

