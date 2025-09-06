#!/usr/bin/env python3
"""
Unit tests for the ZFS configuration parser.

This demonstrates how Python enables comprehensive testing
of configuration logic that would be difficult to test in bash.
"""

import unittest
import tempfile
import os
from pathlib import Path

from config_parser import ZFSConfig


class TestZFSConfig(unittest.TestCase):
    """Test cases for ZFS configuration parser."""
    
    def setUp(self):
        """Set up test environment."""
        self.temp_dir = tempfile.mkdtemp()
        self.env_file = Path(self.temp_dir) / ".env"
    
    def tearDown(self):
        """Clean up test environment."""
        if self.env_file.exists():
            self.env_file.unlink()
        os.rmdir(self.temp_dir)
    
    def test_default_config(self):
        """Test default configuration values."""
        config = ZFSConfig()
        
        self.assertEqual(config.disk, "/dev/sda")
        self.assertEqual(config.hostname, "mail1")
        self.assertEqual(config.timezone, "UTC")
        self.assertEqual(config.pool_root, "rpool")
        self.assertEqual(config.pool_boot, "bpool")
        self.assertEqual(config.arc_max_mb, 2048)
        self.assertFalse(config.encrypt)
        self.assertFalse(config.force)
        self.assertIsNone(config.new_user)
        self.assertTrue(config.new_user_sudo)
        self.assertEqual(config.permit_root_login, "prohibit-password")
        self.assertFalse(config.password_auth)
    
    def test_env_file_parsing(self):
        """Test parsing configuration from .env file."""
        env_content = """
# Test configuration
DISK=/dev/nvme0n1
HOSTNAME=testhost
TZ=America/New_York
POOL_R=mypool
ARC_MAX_MB=4096
ENCRYPT=yes
FORCE=1
NEW_USER=testuser
SSH_IMPORT_IDS="gh:user1 gh:user2"
PERMIT_ROOT_LOGIN=yes
PASSWORD_AUTH=no
        """.strip()
        
        self.env_file.write_text(env_content)
        config = ZFSConfig.from_env_file(str(self.env_file))
        
        self.assertEqual(config.disk, "/dev/nvme0n1")
        self.assertEqual(config.hostname, "testhost")
        self.assertEqual(config.timezone, "America/New_York")
        self.assertEqual(config.pool_root, "mypool")
        self.assertEqual(config.arc_max_mb, 4096)
        self.assertTrue(config.encrypt)
        self.assertTrue(config.force)
        self.assertEqual(config.new_user, "testuser")
        self.assertEqual(config.ssh_import_ids, ["gh:user1", "gh:user2"])
        self.assertEqual(config.permit_root_login, "yes")
        self.assertFalse(config.password_auth)
    
    def test_environment_variable_override(self):
        """Test that environment variables override .env file."""
        env_content = "HOSTNAME=fromfile"
        self.env_file.write_text(env_content)
        
        # Set environment variable
        os.environ["HOSTNAME"] = "fromenv"
        
        try:
            config = ZFSConfig.from_env_file(str(self.env_file))
            self.assertEqual(config.hostname, "fromenv")
        finally:
            # Clean up environment
            del os.environ["HOSTNAME"]
    
    def test_disk_validation(self):
        """Test disk path validation."""
        # Valid disk paths
        valid_disks = ["/dev/sda", "/dev/nvme0n1", "/dev/vda"]
        for disk in valid_disks:
            config = ZFSConfig(disk=disk)
            self.assertEqual(config.disk, disk)
        
        # Invalid disk paths (partitions)
        invalid_disks = ["/dev/sda1", "/dev/nvme0n1p1", "/dev/vda2"]
        for disk in invalid_disks:
            with self.assertRaises(ValueError):
                ZFSConfig(disk=disk)
        
        # Invalid format
        with self.assertRaises(ValueError):
            ZFSConfig(disk="not_a_device")
    
    def test_hostname_validation(self):
        """Test hostname validation."""
        # Valid hostnames
        valid_hostnames = ["test", "test-host", "host123", "a"]
        for hostname in valid_hostnames:
            config = ZFSConfig(hostname=hostname)
            self.assertEqual(config.hostname, hostname)
        
        # Invalid hostnames
        invalid_hostnames = ["test host", "test.host", "test_host", ""]
        for hostname in invalid_hostnames:
            with self.assertRaises(ValueError):
                ZFSConfig(hostname=hostname)
        
        # Too long hostname
        with self.assertRaises(ValueError):
            ZFSConfig(hostname="a" * 64)
    
    def test_pool_name_validation(self):
        """Test ZFS pool name validation."""
        # Valid pool names
        valid_names = ["rpool", "tank", "pool-1", "pool_backup"]
        for name in valid_names:
            config = ZFSConfig(pool_root=name, pool_boot=name + "_boot")
            self.assertEqual(config.pool_root, name)
        
        # Invalid pool names
        invalid_names = ["pool with spaces", "pool@special", ""]
        for name in invalid_names:
            with self.assertRaises(ValueError):
                ZFSConfig(pool_root=name)
    
    def test_arc_validation(self):
        """Test ARC size validation."""
        # Valid ARC sizes
        config = ZFSConfig(arc_max_mb=128)
        self.assertEqual(config.arc_max_mb, 128)
        
        # Too small ARC size
        with self.assertRaises(ValueError):
            ZFSConfig(arc_max_mb=32)
    
    def test_ssh_config_validation(self):
        """Test SSH configuration validation."""
        # Valid permit_root_login values
        valid_values = ["yes", "no", "prohibit-password"]
        for value in valid_values:
            config = ZFSConfig(permit_root_login=value)
            self.assertEqual(config.permit_root_login, value)
        
        # Invalid permit_root_login value
        with self.assertRaises(ValueError):
            ZFSConfig(permit_root_login="invalid")
    
    def test_list_parsing(self):
        """Test parsing of list values from environment."""
        env_content = """
SSH_IMPORT_IDS=gh:user1 gh:user2
SSH_AUTHORIZED_KEYS_URLS="https://example.com/keys1.txt https://example.com/keys2.txt"
CI_DATASOURCES=[ConfigDrive,NoCloud,Ec2]
        """.strip()
        
        self.env_file.write_text(env_content)
        config = ZFSConfig.from_env_file(str(self.env_file))
        
        self.assertEqual(config.ssh_import_ids, ["gh:user1", "gh:user2"])
        self.assertEqual(config.ssh_authorized_keys_urls, 
                        ["https://example.com/keys1.txt", "https://example.com/keys2.txt"])
        self.assertEqual(config.ci_datasources, ["ConfigDrive", "NoCloud", "Ec2"])
    
    def test_boolean_parsing(self):
        """Test parsing of boolean values."""
        test_cases = [
            ("1", True), ("0", False),
            ("true", True), ("false", False),
            ("yes", True), ("no", False),
            ("on", True), ("off", False),
            ("True", True), ("False", False),
        ]
        
        for env_value, expected in test_cases:
            env_content = f"ENCRYPT={env_value}"
            self.env_file.write_text(env_content)
            config = ZFSConfig.from_env_file(str(self.env_file))
            self.assertEqual(config.encrypt, expected, f"Failed for value: {env_value}")
    
    def test_to_env_dict(self):
        """Test conversion back to environment dictionary."""
        config = ZFSConfig(
            disk="/dev/nvme0n1",
            hostname="testhost",
            encrypt=True,
            ssh_import_ids=["gh:user1", "gh:user2"]
        )
        
        env_dict = config.to_env_dict()
        
        self.assertEqual(env_dict["DISK"], "/dev/nvme0n1")
        self.assertEqual(env_dict["HOSTNAME"], "testhost")
        self.assertEqual(env_dict["ENCRYPT"], "1")
        self.assertEqual(env_dict["SSH_IMPORT_IDS"], "gh:user1 gh:user2")
    
    def test_comments_in_env_file(self):
        """Test handling of comments in .env file."""
        env_content = """
# This is a comment
DISK=/dev/sda  # This is an inline comment
HOSTNAME=test
# Another comment
ENCRYPT=yes   # Enable encryption
        """.strip()
        
        self.env_file.write_text(env_content)
        config = ZFSConfig.from_env_file(str(self.env_file))
        
        self.assertEqual(config.disk, "/dev/sda")
        self.assertEqual(config.hostname, "test")
        self.assertTrue(config.encrypt)
    
    def test_display_summary(self):
        """Test configuration summary display."""
        config = ZFSConfig(
            disk="/dev/nvme0n1",
            hostname="testhost",
            new_user="testuser",
            ssh_import_ids=["gh:user1"]
        )
        
        summary = config.display_summary()
        
        self.assertIn("/dev/nvme0n1", summary)
        self.assertIn("testhost", summary)
        self.assertIn("testuser", summary)
        self.assertIn("gh:user1", summary)


if __name__ == "__main__":
    # Run the tests
    unittest.main(verbosity=2)