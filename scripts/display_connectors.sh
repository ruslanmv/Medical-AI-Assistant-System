#!/bin/bash
# display_connectors.sh - Display all available connections in watsonx Orchestrate

set -e

# --- CONFIGURATION & COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(pwd)"
VENV_DIR="${PROJECT_ROOT}/venv"

# --- HELPER FUNCTIONS ---
check_command() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1 successful${NC}"
    else
        echo -e "${RED}✗ $1 failed${NC}"
        exit 1
    fi
}

check_orchestrate() {
    if ! command -v orchestrate &> /dev/null; then
        echo -e "${RED}Error: 'orchestrate' command not found.${NC}"
        echo "Please make sure the watsonx Orchestrate ADK is installed and the venv is active."
        exit 1
    fi
}

# --- VIRTUAL ENVIRONMENT ACTIVATION ---
activate_venv() {
    if [[ -d "$VENV_DIR" ]]; then
        echo -e "${YELLOW}📦 Activating virtual environment from: ${VENV_DIR}${NC}"
        source "${VENV_DIR}/bin/activate"
        echo -n "🔧 Python " && python --version
        ADK_VERSION=$(pip show ibm-watsonx-orchestrate 2>/dev/null | awk '/^Version:/{print $2}')
        if [[ -z "$ADK_VERSION" ]]; then
            echo -e "${YELLOW}⚠️  Could not detect installed ADK version.${NC}"
        else
            echo -e "${GREEN}✅ Detected ADK version ${ADK_VERSION}${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Virtual environment not found at '${VENV_DIR}'. Trying to continue...${NC}"
    fi
}

# --- MAIN FUNCTIONS ---
display_environment_info() {
    echo -e "${CYAN}Current Environment Information:${NC}"
    echo "=================================="
    
    # Get current environment
    current_env=$(orchestrate env list 2>/dev/null | grep "(active)" | awk '{print $1}' || echo "Unknown")
    echo -e "${BLUE}Active Environment:${NC} ${current_env}"
    
    # List all environments
    echo -e "\n${BLUE}All Available Environments:${NC}"
    orchestrate env list 2>/dev/null || echo "Could not retrieve environment list"
    echo ""
}

display_connections() {
    echo -e "${CYAN}Available Connections (Connectors):${NC}"
    echo "===================================="
    
    # List all connections
    echo -e "${YELLOW}Listing all connections in the active environment...${NC}"
    orchestrate connections list
    check_command "Connection listing"
}

display_connection_details() {
    echo -e "\n${CYAN}Connection Details:${NC}"
    echo "==================="
    
    # Get connection list in verbose mode if available
    echo -e "${YELLOW}Attempting to get detailed connection information...${NC}"
    
    # Note: The orchestrate connections list command doesn't have a verbose flag
    # but we can show what information is typically available
    echo -e "${BLUE}Connection Information Includes:${NC}"
    echo "• Connection Name (App ID)"
    echo "• Environment (Draft/Live)"
    echo "• Authentication Type (Basic Auth, Bearer Token, API Key, OAuth, etc.)"
    echo "• Credential Scope (Team/Member)"
    echo "• Connection Status (Green tick indicates properly configured)"
    echo ""
    echo -e "${YELLOW}💡 For detailed connection configuration, check the UI at:${NC}"
    echo "   Manage -> Connections in watsonx Orchestrate"
}

show_connection_types() {
    echo -e "\n${CYAN}Supported Connection Types:${NC}"
    echo "============================"
    echo -e "${BLUE}Authentication Methods:${NC}"
    echo "• Basic Auth - Username and password authentication"
    echo "• Bearer Token - Token-based authentication"
    echo "• API Key - API key authentication"
    echo "• OAuth (Multiple flows) - OAuth authentication"
    echo "• Key-Value - Custom key-value pairs for flexible configuration"
    echo ""
    echo -e "${BLUE}Credential Scopes:${NC}"
    echo "• Team - Shared credentials across team members"
    echo "• Member - Individual user credentials"
    echo ""
    echo -e "${BLUE}Environments:${NC}"
    echo "• Draft - Development/testing environment"
    echo "• Live - Production environment"
}

show_helpful_commands() {
    echo -e "\n${CYAN}Helpful Connection Commands:${NC}"
    echo "============================="
    echo -e "${YELLOW}Basic Connection Management:${NC}"
    echo "• orchestrate connections list                    - List all connections"
    echo "• orchestrate connections add -a <name>          - Add new connection"
    echo "• orchestrate connections remove --app-id <name> - Remove connection"
    echo ""
    echo -e "${YELLOW}Connection Configuration:${NC}"
    echo "• orchestrate connections configure --app-id <name> --kind basic --url <url> --env draft --type team"
    echo "• orchestrate connections set-credentials --app-id <name> --env draft --username <user> --password <pass>"
    echo ""
    echo -e "${YELLOW}Environment Management:${NC}"
    echo "• orchestrate env list                           - List all environments"
    echo "• orchestrate env activate <env-name>            - Switch environment"
}

# --- MAIN EXECUTION ---
main() {
    echo ""
    echo -e "${GREEN}=== watsonx Orchestrate Connection Display ===${NC}"
    echo ""
    
    # Activate virtual environment if available
    activate_venv
    
    # Check if orchestrate command is available
    check_orchestrate
    
    # Display environment information
    display_environment_info
    
    # Display connections
    display_connections
    
    # Show connection details and types
    display_connection_details
    show_connection_types
    
    # Show helpful commands
    show_helpful_commands
    
    echo ""
    echo -e "${GREEN}=== Connection Display Complete! ===${NC}"
    echo ""
    echo -e "${YELLOW}💡 Tip: Use 'orchestrate connections list' anytime to see current connections${NC}"
    echo ""
}

# Run the main function
main