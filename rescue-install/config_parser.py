#!/usr/bin/env python3
"""
Configuration parser and validator for ZFS installer.

This demonstrates how Python could enhance the rescue-install system
by providing structured configuration management with validation.
"""

import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Dict, Any
import json


@dataclass
class ZFSConfig:
    """Structured configuration for ZFS installer with validation."""
    
    # Disk & Host
    disk: str = "/dev/sda"
    hostname: str = "mail1"
    timezone: str = "UTC"
    
    # ZFS Pools
    pool_root: str = "rpool"
    pool_boot: str = "bpool"
    arc_max_mb: int = 2048
    encrypt: bool = False
    
    # Cloud-init
    ci_datasources: List[str] = field(default_factory=lambda: ["ConfigDrive", "NoCloud", "Ec2"])
    
    # Safety
    force: bool = False
    
    # User Management
    new_user: Optional[str] = None
    new_user_sudo: bool = True
    
    # SSH Configuration
    ssh_import_ids: List[str] = field(default_factory=list)
    ssh_authorized_keys: List[str] = field(default_factory=list)
    ssh_authorized_keys_urls: List[str] = field(default_factory=list)
    permit_root_login: str = "prohibit-password"
    password_auth: bool = False
    
    def __post_init__(self):
        """Validate configuration after initialization."""
        self._validate_disk()
        self._validate_hostname()
        self._validate_pools()
        self._validate_ssh_config()
    
    def _validate_disk(self):
        """Validate disk specification."""
        if not self.disk.startswith('/dev/'):
            raise ValueError(f"Invalid disk path: {self.disk}")
        
        # Check if it looks like a partition rather than a whole disk
        if (re.match(r'.*p\d+$', self.disk) or  # NVMe partitions
            re.match(r'^/dev/[sv]d[a-z]\d+$', self.disk)):  # SATA/SCSI partitions
            raise ValueError(f"DISK={self.disk} appears to be a partition. "
                           f"Please specify the whole disk.")
    
    def _validate_hostname(self):
        """Validate hostname format."""
        if not re.match(r'^[a-zA-Z0-9-]+$', self.hostname):
            raise ValueError(f"Invalid hostname: {self.hostname}")
        if len(self.hostname) > 63:
            raise ValueError(f"Hostname too long: {self.hostname}")
    
    def _validate_pools(self):
        """Validate ZFS pool names."""
        for pool_name in [self.pool_root, self.pool_boot]:
            if not re.match(r'^[a-zA-Z0-9_-]+$', pool_name):
                raise ValueError(f"Invalid pool name: {pool_name}")
        
        if self.arc_max_mb < 64:
            raise ValueError(f"ARC max too small: {self.arc_max_mb}MB")
    
    def _validate_ssh_config(self):
        """Validate SSH configuration."""
        valid_permit_values = ["yes", "no", "prohibit-password"]
        if self.permit_root_login not in valid_permit_values:
            raise ValueError(f"Invalid permit_root_login: {self.permit_root_login}")
    
    @classmethod
    def from_env_file(cls, env_file: str = ".env") -> "ZFSConfig":
        """Load configuration from .env file with validation."""
        config_dict = {}
        env_path = Path(env_file)
        
        if env_path.exists():
            with open(env_path) as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    
                    if '=' not in line:
                        print(f"Warning: Invalid line {line_num} in {env_file}: {line}")
                        continue
                    
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().strip('"\'')
                    
                    # Remove inline comments
                    if '#' in value:
                        value = value.split('#')[0].strip().strip('"\'')
                    
                    # Convert environment variable names to config field names
                    field_name = cls._env_to_field_name(key)
                    if field_name:
                        config_dict[field_name] = cls._parse_value(field_name, value)
        
        # Override with environment variables
        for env_var, field_name in cls._get_env_mapping().items():
            if env_var in os.environ:
                value = os.environ[env_var]
                config_dict[field_name] = cls._parse_value(field_name, value)
        
        return cls(**config_dict)
    
    @staticmethod
    def _env_to_field_name(env_var: str) -> Optional[str]:
        """Convert environment variable name to config field name."""
        mapping = {
            'DISK': 'disk',
            'HOSTNAME': 'hostname',
            'TZ': 'timezone',
            'POOL_R': 'pool_root',
            'POOL_B': 'pool_boot',
            'ARC_MAX_MB': 'arc_max_mb',
            'ENCRYPT': 'encrypt',
            'FORCE': 'force',
            'NEW_USER': 'new_user',
            'NEW_USER_SUDO': 'new_user_sudo',
            'SSH_IMPORT_IDS': 'ssh_import_ids',
            'SSH_AUTHORIZED_KEYS': 'ssh_authorized_keys',
            'SSH_AUTHORIZED_KEYS_URLS': 'ssh_authorized_keys_urls',
            'PERMIT_ROOT_LOGIN': 'permit_root_login',
            'PASSWORD_AUTH': 'password_auth',
            'CI_DATASOURCES': 'ci_datasources',
        }
        return mapping.get(env_var)
    
    @staticmethod
    def _get_env_mapping() -> Dict[str, str]:
        """Get mapping of environment variables to field names."""
        return {k: v for k, v in [
            ('DISK', 'disk'),
            ('HOSTNAME', 'hostname'),
            ('TZ', 'timezone'),
            ('POOL_R', 'pool_root'),
            ('POOL_B', 'pool_boot'),
            ('ARC_MAX_MB', 'arc_max_mb'),
            ('ENCRYPT', 'encrypt'),
            ('FORCE', 'force'),
            ('NEW_USER', 'new_user'),
            ('NEW_USER_SUDO', 'new_user_sudo'),
            ('SSH_IMPORT_IDS', 'ssh_import_ids'),
            ('SSH_AUTHORIZED_KEYS', 'ssh_authorized_keys'),
            ('SSH_AUTHORIZED_KEYS_URLS', 'ssh_authorized_keys_urls'),
            ('PERMIT_ROOT_LOGIN', 'permit_root_login'),
            ('PASSWORD_AUTH', 'password_auth'),
            ('CI_DATASOURCES', 'ci_datasources'),
        ]}
    
    @staticmethod
    def _parse_value(field_name: str, value: str) -> Any:
        """Parse string value to appropriate type for field."""
        if field_name in ['arc_max_mb']:
            return int(value)
        elif field_name in ['encrypt', 'force', 'new_user_sudo', 'password_auth']:
            return value.lower() in ['1', 'true', 'yes', 'on']
        elif field_name in ['ssh_import_ids', 'ssh_authorized_keys', 'ssh_authorized_keys_urls', 'ci_datasources']:
            # Handle space or comma-separated lists
            if not value:
                return []
            # Handle YAML-style lists or space-separated
            if value.startswith('[') and value.endswith(']'):
                # Parse YAML-style list: [item1,item2,item3]
                items = value[1:-1].split(',')
                return [item.strip().strip('"\'') for item in items if item.strip()]
            else:
                # Space-separated
                return [item.strip().strip('"\'') for item in value.split() if item.strip()]
        elif field_name == 'new_user' and not value:
            return None
        else:
            return value
    
    def to_env_dict(self) -> Dict[str, str]:
        """Convert config to environment variable dictionary."""
        env_dict = {}
        for env_var, field_name in self._get_env_mapping().items():
            value = getattr(self, field_name)
            if value is None:
                env_dict[env_var] = ""
            elif isinstance(value, bool):
                env_dict[env_var] = "1" if value else "0"
            elif isinstance(value, list):
                if field_name == 'ci_datasources':
                    # Format as YAML-style list
                    env_dict[env_var] = f"[{','.join(value)}]"
                else:
                    # Space-separated
                    env_dict[env_var] = " ".join(value)
            else:
                env_dict[env_var] = str(value)
        return env_dict
    
    def display_summary(self) -> str:
        """Generate a human-readable configuration summary."""
        lines = [
            "=== ZFS Installation Configuration ===",
            f"Target Disk: {self.disk}",
            f"Hostname: {self.hostname}",
            f"Timezone: {self.timezone}",
            f"Root Pool: {self.pool_root}",
            f"Boot Pool: {self.pool_boot}",
            f"ARC Max: {self.arc_max_mb}MB",
            f"Encryption: {'Enabled' if self.encrypt else 'Disabled'}",
            f"Force Mode: {'Yes' if self.force else 'No'}",
        ]
        
        if self.new_user:
            lines.extend([
                f"New User: {self.new_user}",
                f"User Sudo: {'Yes' if self.new_user_sudo else 'No'}",
            ])
        
        if self.ssh_import_ids:
            lines.append(f"SSH Import IDs: {', '.join(self.ssh_import_ids)}")
        
        lines.extend([
            f"Root Login: {self.permit_root_login}",
            f"Password Auth: {'Yes' if self.password_auth else 'No'}",
        ])
        
        return "\n".join(lines)


def validate_environment() -> bool:
    """Validate that the environment is suitable for ZFS installation."""
    errors = []
    warnings = []
    
    # Check if running as root
    if os.geteuid() != 0:
        errors.append("Must run as root")
    
    # Check if rescue/live environment
    if not Path("/proc/cmdline").exists():
        warnings.append("Cannot verify rescue environment")
    
    # Check for required commands
    required_commands = ["zpool", "zfs", "debootstrap", "sgdisk"]
    for cmd in required_commands:
        if os.system(f"command -v {cmd} >/dev/null 2>&1") != 0:
            errors.append(f"Required command not found: {cmd}")
    
    if errors:
        print("❌ Environment validation failed:")
        for error in errors:
            print(f"  • {error}")
        return False
    
    if warnings:
        print("⚠️  Environment warnings:")
        for warning in warnings:
            print(f"  • {warning}")
    
    print("✅ Environment validation passed")
    return True


def main():
    """Main function for testing the configuration parser."""
    import argparse
    
    parser = argparse.ArgumentParser(description="ZFS installer configuration parser")
    parser.add_argument("--env-file", default=".env", help="Environment file to load")
    parser.add_argument("--validate-env", action="store_true", help="Validate environment")
    parser.add_argument("--export", action="store_true", help="Export as environment variables")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args()
    
    try:
        # Load and validate configuration
        config = ZFSConfig.from_env_file(args.env_file)
        
        if args.validate_env:
            if not validate_environment():
                sys.exit(1)
        
        if args.json:
            # Output as JSON (for script integration)
            import json
            print(json.dumps(config.__dict__, indent=2))
        elif args.export:
            # Output as shell exports
            for key, value in config.to_env_dict().items():
                print(f"export {key}='{value}'")
        else:
            # Human-readable summary
            print(config.display_summary())
    
    except Exception as e:
        print(f"❌ Configuration error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()