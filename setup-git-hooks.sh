#!/bin/bash

# Script Name: setup_git_hooks.sh
# Description: Sets up Git hooks, environment variables, and git function for the QS shared hooks system.

# -----------------------------
# Configuration
# -----------------------------

# Command line arguments
RESET_CONFIG=false

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --reset) RESET_CONFIG=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Paths and URLs
CONFIG_DIR="$HOME/.qs-internal"
CONFIG_FILE="$CONFIG_DIR/config"
HOOKS_REPO_URL="git@bitbucket.org:quantspark/qs-shared-git-hooks.git"
HOOKS_SUBDIR="hooks"
TEMP_DIR_PREFIX="temp_git_hooks_"
DEST_DIR="$HOME/.qs-internal/hooks"
VENV_DIR="$CONFIG_DIR/venv"

# Function to check if a variable exists in config file
variable_exists() {
    local var_name=$1
    [ -f "$CONFIG_FILE" ] && grep -q "export $var_name=" "$CONFIG_FILE"
}

# Function to create config directory and file
create_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        if ! mkdir -p "$CONFIG_DIR"; then
            echo "Error: Failed to create directory: $CONFIG_DIR"
            exit 1
        fi
    fi
    
    # Only clear config file if reset flag is set
    if [ "$RESET_CONFIG" = true ]; then
        > "$CONFIG_FILE"
        echo "Resetting configuration file..."
    fi
}

# Function to detect shell configuration file
detect_shell_config() {
    if [[ "$SHELL" == *"zsh"* ]]; then
        SHELL_CONFIG="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
        BASH_PROFILE="$HOME/.bash_profile"
        # Create .bashrc if it doesn't exist
        touch "$SHELL_CONFIG"
        # Ensure .bash_profile sources .bashrc
        if [ -f "$BASH_PROFILE" ]; then
            if ! grep -q "source.*\.bashrc" "$BASH_PROFILE"; then
                echo "" >> "$BASH_PROFILE"
                echo "# Source .bashrc for non-login shells" >> "$BASH_PROFILE"
                echo '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"' >> "$BASH_PROFILE"
            fi
        else
            echo "# Source .bashrc for non-login shells" > "$BASH_PROFILE"
            echo '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"' >> "$BASH_PROFILE"
        fi
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
        
        if [ "$RESET_CONFIG" = true ] || ! variable_exists "$var_name"; then
            echo -n "Enter $var_name ($description): "
            read -r var_value
            
            if [ -z "$var_value" ]; then
                echo "Error: $var_name cannot be empty"
                exit 1
            fi
            
            echo "export $var_name=\"$var_value\"" >> "$CONFIG_FILE"
        fi
    }

    # First prompt for LLM provider
    if [ "$RESET_CONFIG" = true ] || ! variable_exists "QSGH_LLM_PROVIDER"; then
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
    fi

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

# Function to verify required dependencies
verify_required_dependencies() {
    command -v git >/dev/null 2>&1 || {
        echo >&2 "Git is required but not installed. Aborting."
        exit 1
    }
    command -v curl >/dev/null 2>&1 || {
        echo >&2 "cURL is required but not installed. Aborting."
        exit 1
    }
    command -v jq >/dev/null 2>&1 || {
        echo >&2 "jq is required but not installed. Aborting."
        exit 1
    }
    command -v python3 >/dev/null 2>&1 || {
        echo >&2 "Python 3 is required but not installed. Aborting."
        exit 1
    }
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

# Function to setup Python virtual environment
setup_python_environment() {
    echo "Setting up Python virtual environment..."
    
    # Remove existing venv if resetting
    if [ "$RESET_CONFIG" = true ] && [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
    fi

    # Create virtual environment if it doesn't exist
    if [ ! -d "$VENV_DIR" ]; then
        if ! python3 -m venv "$VENV_DIR"; then
            echo "Error: Failed to create virtual environment"
            rm -rf "$CLONE_DIR"
            exit 1
        fi
    fi

    # Install requirements
    if ! "$VENV_DIR/bin/pip" install -r "$CLONE_DIR/requirements.txt"; then
        echo "Error: Failed to install Python dependencies"
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

# Verify dependencies
verify_required_dependencies

# Clone the hooks repository
clone_hooks_repo

# Setup Python environment
setup_python_environment

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
