#!/usr/bin/env python3
"""
Agent YAML Validator for watsonx Orchestrate ADK
Validates agent configuration files before import
"""

import yaml
import sys
import argparse
from typing import Dict, List, Any, Optional
from pathlib import Path

class AgentValidator:
    """Validates watsonx Orchestrate agent YAML configurations"""
    
    # Valid agent kinds
    VALID_KINDS = ['native', 'external']
    
    # Valid agent styles for native agents
    VALID_STYLES = ['default', 'react', 'planner']
    
    # Valid external agent providers
    VALID_PROVIDERS = ['external_chat', 'external_chat/A2A/0.2.1', 'wx.ai']
    
    # Valid auth schemes for external agents
    VALID_AUTH_SCHEMES = ['BEARER_TOKEN', 'API_KEY', 'NONE']
    
    # Valid LLM formats (basic validation)
    VALID_LLM_PROVIDERS = ['watsonx', 'openai', 'anthropic']
    
    # Required fields for different agent types
    REQUIRED_NATIVE_FIELDS = ['spec_version', 'kind', 'name', 'description', 'llm']
    REQUIRED_EXTERNAL_FIELDS = ['spec_version', 'kind', 'name', 'description', 'api_url']
    
    def __init__(self):
        self.errors = []
        self.warnings = []
    
    def validate_file(self, file_path: str) -> bool:
        """
        Validate an agent YAML file
        
        Args:
            file_path: Path to the YAML file
            
        Returns:
            bool: True if valid, False if errors found
        """
        self.errors = []
        self.warnings = []
        
        try:
            # Check if file exists
            if not Path(file_path).exists():
                self.errors.append(f"File not found: {file_path}")
                return False
            
            # Load YAML content
            with open(file_path, 'r', encoding='utf-8') as file:
                try:
                    agent_config = yaml.safe_load(file)
                except yaml.YAMLError as e:
                    self.errors.append(f"Invalid YAML syntax: {e}")
                    return False
            
            if not agent_config:
                self.errors.append("Empty YAML file")
                return False
            
            # Validate based on agent kind
            kind = agent_config.get('kind', '').lower()
            
            if kind == 'native':
                self._validate_native_agent(agent_config)
            elif kind == 'external':
                self._validate_external_agent(agent_config)
            else:
                self.errors.append(f"Invalid or missing 'kind'. Must be one of: {self.VALID_KINDS}")
            
            return len(self.errors) == 0
            
        except Exception as e:
            self.errors.append(f"Unexpected error: {e}")
            return False
    
    def _validate_native_agent(self, config: Dict[str, Any]) -> None:
        """Validate native agent configuration"""
        
        # Check required fields
        for field in self.REQUIRED_NATIVE_FIELDS:
            if field not in config:
                self.errors.append(f"Missing required field: '{field}'")
        
        # Validate spec_version
        if 'spec_version' in config and config['spec_version'] != 'v1':
            self.errors.append("spec_version must be 'v1'")
        
        # Validate name (alphanumeric and underscores only)
        name = config.get('name', '')
        if name and not name.replace('_', '').replace('-', '').isalnum():
            self.errors.append("Agent name should contain only alphanumeric characters, underscores, and hyphens")
        
        # Validate style
        style = config.get('style', 'default')
        if style not in self.VALID_STYLES:
            self.errors.append(f"Invalid style '{style}'. Must be one of: {self.VALID_STYLES}")
        
        # Validate LLM format
        llm = config.get('llm', '')
        if llm:
            self._validate_llm_format(llm)
        
        # Validate tools (if present)
        tools = config.get('tools', [])
        if tools is not None and not isinstance(tools, list):
            self.errors.append("'tools' must be a list")
        
        # Validate collaborators (if present)
        collaborators = config.get('collaborators', [])
        if collaborators is not None and not isinstance(collaborators, list):
            self.errors.append("'collaborators' must be a list")
        
        # Validate knowledge_base (if present)
        knowledge_base = config.get('knowledge_base', [])
        if knowledge_base is not None and not isinstance(knowledge_base, list):
            self.errors.append("'knowledge_base' must be a list")
        
        # Validate boolean fields
        self._validate_boolean_field(config, 'hidden')
        self._validate_boolean_field(config, 'context_access_enabled')
        
        # Validate guidelines (if present)
        self._validate_guidelines(config.get('guidelines', []))
        
        # Validate chat_with_docs (if present)
        self._validate_chat_with_docs(config.get('chat_with_docs'))
        
        # Validate context_variables (if present)
        context_vars = config.get('context_variables', [])
        if context_vars is not None and not isinstance(context_vars, list):
            self.errors.append("'context_variables' must be a list")
    
    def _validate_external_agent(self, config: Dict[str, Any]) -> None:
        """Validate external agent configuration"""
        
        # Check required fields
        for field in self.REQUIRED_EXTERNAL_FIELDS:
            if field not in config:
                self.errors.append(f"Missing required field: '{field}'")
        
        # Validate spec_version
        if 'spec_version' in config and config['spec_version'] != 'v1':
            self.errors.append("spec_version must be 'v1'")
        
        # Validate name
        name = config.get('name', '')
        if name and not name.replace('_', '').replace('-', '').isalnum():
            self.errors.append("Agent name should contain only alphanumeric characters, underscores, and hyphens")
        
        # Validate API URL
        api_url = config.get('api_url', '')
        if api_url and not (api_url.startswith('http://') or api_url.startswith('https://')):
            self.errors.append("api_url must be a valid HTTP/HTTPS URL")
        
        # Validate provider (if present)
        provider = config.get('provider', '')
        if provider and provider not in self.VALID_PROVIDERS:
            self.warnings.append(f"Provider '{provider}' is not in common providers: {self.VALID_PROVIDERS}")
        
        # Validate auth_scheme (if present)
        auth_scheme = config.get('auth_scheme', '')
        if auth_scheme and auth_scheme not in self.VALID_AUTH_SCHEMES:
            self.errors.append(f"Invalid auth_scheme '{auth_scheme}'. Must be one of: {self.VALID_AUTH_SCHEMES}")
        
        # Validate auth_config (if present)
        auth_config = config.get('auth_config')
        if auth_config is not None and not isinstance(auth_config, dict):
            self.errors.append("'auth_config' must be a dictionary")
        
        # Validate chat_params (if present)
        chat_params = config.get('chat_params')
        if chat_params is not None and not isinstance(chat_params, dict):
            self.errors.append("'chat_params' must be a dictionary")
        
        # Validate config (if present)
        agent_config = config.get('config')
        if agent_config is not None and not isinstance(agent_config, dict):
            self.errors.append("'config' must be a dictionary")
        
        # Validate tags (if present)
        tags = config.get('tags', [])
        if tags is not None and not isinstance(tags, list):
            self.errors.append("'tags' must be a list")
    
    def _validate_llm_format(self, llm: str) -> None:
        """Validate LLM format (provider/developer/model_id)"""
        if not llm:
            return
        
        parts = llm.split('/')
        if len(parts) < 2:
            self.errors.append(f"LLM format should be 'provider/developer/model_id', got: '{llm}'")
            return
        
        provider = parts[0]
        if provider not in self.VALID_LLM_PROVIDERS:
            self.warnings.append(f"LLM provider '{provider}' is not in common providers: {self.VALID_LLM_PROVIDERS}")
    
    def _validate_boolean_field(self, config: Dict[str, Any], field_name: str) -> None:
        """Validate that a field is boolean if present"""
        if field_name in config and not isinstance(config[field_name], bool):
            self.errors.append(f"'{field_name}' must be a boolean (true/false)")
    
    def _validate_guidelines(self, guidelines: List[Dict[str, Any]]) -> None:
        """Validate guidelines structure"""
        if not isinstance(guidelines, list):
            self.errors.append("'guidelines' must be a list")
            return
        
        for i, guideline in enumerate(guidelines):
            if not isinstance(guideline, dict):
                self.errors.append(f"Guideline {i} must be a dictionary")
                continue
            
            required_guideline_fields = ['display_name', 'condition', 'action']
            for field in required_guideline_fields:
                if field not in guideline:
                    self.errors.append(f"Guideline {i} missing required field: '{field}'")
    
    def _validate_chat_with_docs(self, chat_with_docs: Optional[Dict[str, Any]]) -> None:
        """Validate chat_with_docs configuration"""
        if chat_with_docs is None:
            return
        
        if not isinstance(chat_with_docs, dict):
            self.errors.append("'chat_with_docs' must be a dictionary")
            return
        
        # Validate enabled field
        if 'enabled' in chat_with_docs and not isinstance(chat_with_docs['enabled'], bool):
            self.errors.append("'chat_with_docs.enabled' must be a boolean")
        
        # Validate vector_index if present
        vector_index = chat_with_docs.get('vector_index')
        if vector_index is not None and not isinstance(vector_index, dict):
            self.errors.append("'chat_with_docs.vector_index' must be a dictionary")
    
    def print_results(self) -> None:
        """Print validation results"""
        if self.errors:
            print("❌ VALIDATION ERRORS:")
            for error in self.errors:
                print(f"  • {error}")
        
        if self.warnings:
            print("⚠️  WARNINGS:")
            for warning in self.warnings:
                print(f"  • {warning}")
        
        if not self.errors and not self.warnings:
            print("✅ Validation passed! No errors or warnings found.")
        elif not self.errors:
            print("✅ Validation passed! Only warnings found.")


def main():
    """Main function to run the validator"""
    parser = argparse.ArgumentParser(
        description="Validate watsonx Orchestrate agent YAML files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python validate_agent.py agent.yaml
  python validate_agent.py my_agents/greeting_agent.yaml
  python validate_agent.py -v agent.yaml  # verbose output
        """
    )
    
    parser.add_argument(
        'file_path',
        help='Path to the agent YAML file to validate'
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    
    args = parser.parse_args()
    
    # Create validator and run validation
    validator = AgentValidator()
    
    if args.verbose:
        print(f"🔍 Validating agent file: {args.file_path}")
        print("-" * 50)
    
    is_valid = validator.validate_file(args.file_path)
    
    # Print results
    validator.print_results()
    
    if args.verbose:
        print("-" * 50)
        print(f"📊 Summary: {'VALID' if is_valid else 'INVALID'}")
        print(f"   Errors: {len(validator.errors)}")
        print(f"   Warnings: {len(validator.warnings)}")
    
    # Exit with appropriate code
    sys.exit(0 if is_valid else 1)


if __name__ == "__main__":
    main()