#!/bin/bash

# Script Name: setup_git_hooks.sh
# Description: Sets up Git hooks, environment variables, and git function for the QS shared hooks system.

# -----------------------------
# Configuration
# -----------------------------

# URL of the Git hooks repository
HOOKS_REPO_URL="git@bitbucket.org:quantspark/qs-shared-git-hooks.git"
HOOKS_SUBDIR="hooks"
TEMP_DIR_PREFIX="temp_git_hooks_"
DEST_DIR="$HOME/.qs-internal/hooks"

# Function to detect shell configuration file
detect_shell_config() {
    if [[ "$SHELL" == *"zsh"* ]]; then
        SHELL_CONFIG="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
    else
        echo "Error: Unable to detect shell configuration file"
        exit 1
    fi
}

# Function to prompt for environment variables
setup_environment_variables() {
    setup_variable() {
        local var_name=$1
        local description=$2
        local allow_empty=${3:-false}
        
        if ! grep -q "export $var_name=" "$SHELL_CONFIG"; then
            echo -n "Enter $var_name ($description): "
            read -r var_value
            
            if [ -z "$var_value" ] && [ "$allow_empty" = "false" ]; then
                echo "Error: $var_name cannot be empty"
                exit 1
            fi
            
            if [ ! -z "$var_value" ]; then
                echo "export $var_name=\"$var_value\"" >> "$SHELL_CONFIG"
            fi
        fi
    }

    # Prompt for LLM provider first
    setup_variable "QSGH_LLM_PROVIDER" "LLM provider to use (openai or anthropic)" false
    
    # Based on provider, prompt for the appropriate API key
    if [ "$var_value" = "openai" ]; then
        setup_variable "QSGH_API_KEY" "OpenAI API key for generating PR descriptions" false
    elif [ "$var_value" = "anthropic" ]; then
        setup_variable "QSGH_ANTHROPIC_API_KEY" "Anthropic API key for generating PR descriptions" false
    else
        echo "Error: Invalid LLM provider. Must be either 'openai' or 'anthropic'"
        exit 1
    fi
    
    setup_variable "QSGH_BITBUCKET_USERNAME" "Your Bitbucket username" false
    setup_variable "QSGH_BITBUCKET_APP_PASSWORD" "Your Bitbucket app password" false
    setup_variable "QSGH_DEFAULT_DESTINATION_BRANCH" "Default branch for pull requests (e.g., development)" false
}

# Function to setup git function
setup_git_function() {
    if ! grep -q "git()" "$SHELL_CONFIG"; then
        cat git-function.sh >> "$SHELL_CONFIG"
    fi
}

# Function to clone the hooks repository
clone_hooks_repo() {
    CLONE_DIR=$(mktemp -d -t ${TEMP_DIR_PREFIX}XXXX)
    
    if ! git clone "$HOOKS_REPO_URL" "$CLONE_DIR" >/dev/null 2>&1; then
        echo "Error: Failed to clone the hooks repository"
        rm -rf "$CLONE_DIR"
        exit 1
    fi
}

# Function to copy hooks to the destination directory
copy_hooks() {
    SOURCE_HOOKS_DIR="$CLONE_DIR/$HOOKS_SUBDIR"
    
    if [ ! -d "$SOURCE_HOOKS_DIR" ]; then
        echo "Error: Hooks directory '$HOOKS_SUBDIR' does not exist"
        rm -rf "$CLONE_DIR"
        exit 1
    fi
    
    if ! cp -r "$SOURCE_HOOKS_DIR/." "$DEST_DIR/"; then
        echo "Error: Failed to copy hooks"
        rm -rf "$CLONE_DIR"
        exit 1
    fi
}

# Function to set executable permissions for all hook scripts
set_permissions() {
    if ! chmod +x "$DEST_DIR/"*; then
        echo "Error: Failed to set executable permissions"
        rm -rf "$CLONE_DIR"
        exit 1
    fi
}

# -----------------------------
# Main Script
# -----------------------------

# Detect shell configuration file
detect_shell_config

# Ensure the destination directory exists
if [ ! -d "$DEST_DIR" ]; then
    if ! mkdir -p "$DEST_DIR"; then
        echo "Error: Failed to create directory: $DEST_DIR"
        exit 1
    fi
fi

# Clone the hooks repository
clone_hooks_repo

# Copy hooks to the destination directory
copy_hooks

# Set executable permissions for all hook scripts
set_permissions

# Setup environment variables
setup_environment_variables

# Setup git function
setup_git_function

# Clean up
rm -rf "$CLONE_DIR"

echo "Git hooks setup completed successfully"
echo "Please restart your terminal or run 'source $SHELL_CONFIG' to apply the changes"
