#!/bin/bash

# Script Name: setup_git_hooks.sh
# Description: Sets up Git hooks, environment variables, and git function for the QS shared hooks system.

# -----------------------------
# Configuration
# -----------------------------

# Paths and URLs
CONFIG_DIR="$HOME/.qs-internal"
CONFIG_FILE="$CONFIG_DIR/config"
HOOKS_REPO_URL="git@bitbucket.org:quantspark/qs-shared-git-hooks.git"
HOOKS_SUBDIR="hooks"
TEMP_DIR_PREFIX="temp_git_hooks_"
DEST_DIR="$HOME/.qs-internal/hooks"

# Function to create config directory and file
create_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        if ! mkdir -p "$CONFIG_DIR"; then
            echo "Error: Failed to create directory: $CONFIG_DIR"
            exit 1
        fi
    fi
    
    # Create or clear config file
    > "$CONFIG_FILE"
}

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
        
        echo -n "Enter $var_name ($description): "
        read -r var_value
        
        if [ -z "$var_value" ]; then
            echo "Error: $var_name cannot be empty"
            exit 1
        fi
        
        echo "export $var_name=\"$var_value\"" >> "$CONFIG_FILE"
    }

    # First prompt for LLM provider
    echo "Select LLM provider:"
    echo "1) OpenAI"
    echo "2) Anthropic"
    read -p "Enter choice (1 or 2): " provider_choice

    case $provider_choice in
        1)
            echo "export QSGH_LLM_PROVIDER=\"openai\"" >> "$CONFIG_FILE"
            setup_variable "QSGH_API_KEY" "OpenAI API key for generating PR descriptions"
            ;;
        2)
            echo "export QSGH_LLM_PROVIDER=\"anthropic\"" >> "$CONFIG_FILE"
            setup_variable "QSGH_ANTHROPIC_API_KEY" "Anthropic API key for generating PR descriptions"
            ;;
        *)
            echo "Error: Invalid choice"
            exit 1
            ;;
    esac

    # Setup common variables
    setup_variable "QSGH_BITBUCKET_USERNAME" "Your Bitbucket username"
    setup_variable "QSGH_BITBUCKET_APP_PASSWORD" "Your Bitbucket app password"
    setup_variable "QSGH_DEFAULT_DESTINATION_BRANCH" "Default branch for pull requests (e.g., development)"
}

# Function to setup shell configuration
setup_shell_config() {
    # Add git function if not present
    if ! grep -q "git()" "$SHELL_CONFIG"; then
        cat "$CONFIG_DIR/git-function.sh" >> "$SHELL_CONFIG"
    fi

    # Add config file sourcing if not present
    if ! grep -q "source $CONFIG_FILE" "$SHELL_CONFIG"; then
        echo "" >> "$SHELL_CONFIG"
        echo "# Source QS Git Hooks config" >> "$SHELL_CONFIG"
        echo "source $CONFIG_FILE" >> "$SHELL_CONFIG"
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

# Function to copy hooks and git function to the destination directory
copy_hooks() {
    SOURCE_HOOKS_DIR="$CLONE_DIR/$HOOKS_SUBDIR"
    
    if [ ! -d "$SOURCE_HOOKS_DIR" ]; then
        echo "Error: Hooks directory '$HOOKS_SUBDIR' does not exist"
        rm -rf "$CLONE_DIR"
        exit 1
    fi
    
    # Copy hooks
    if ! cp -r "$SOURCE_HOOKS_DIR/." "$DEST_DIR/"; then
        echo "Error: Failed to copy hooks"
        rm -rf "$CLONE_DIR"
        exit 1
    fi

    # Copy git-function.sh
    if [ ! -f "$CLONE_DIR/git-function.sh" ]; then
        echo "Error: git-function.sh not found in cloned repository"
        rm -rf "$CLONE_DIR"
        exit 1
    fi
    
    if ! cp "$CLONE_DIR/git-function.sh" "$CONFIG_DIR/"; then
        echo "Error: Failed to copy git-function.sh"
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

# Create config directory and file
create_config_dir

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

# Setup shell configuration
setup_shell_config

# Clean up
rm -rf "$CLONE_DIR"

echo "Git hooks setup completed successfully"
echo "Please restart your terminal or run 'source $SHELL_CONFIG' to apply the changes"
