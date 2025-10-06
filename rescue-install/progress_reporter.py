#!/usr/bin/env python3
"""
Enhanced progress reporter for ZFS installer.

This demonstrates how Python could provide better progress tracking
and user feedback compared to basic bash echo statements.
"""

import sys
import time
from enum import Enum
from dataclasses import dataclass
from typing import List, Optional
import json


class LogLevel(Enum):
    """Log levels for different message types."""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARN = "WARN"
    ERROR = "ERROR"
    SUCCESS = "SUCCESS"


@dataclass
class ProgressStep:
    """Represents a single step in the installation process."""
    name: str
    description: str
    started: Optional[float] = None
    completed: Optional[float] = None
    error: Optional[str] = None
    
    @property
    def is_started(self) -> bool:
        return self.started is not None
    
    @property
    def is_completed(self) -> bool:
        return self.completed is not None
    
    @property
    def is_error(self) -> bool:
        return self.error is not None
    
    @property
    def duration(self) -> Optional[float]:
        if self.started and self.completed:
            return self.completed - self.started
        return None


class ProgressReporter:
    """Enhanced progress reporting with structured logging."""
    
    def __init__(self, total_steps: int = 0, use_color: bool = True):
        self.total_steps = total_steps
        self.current_step = 0
        self.steps: List[ProgressStep] = []
        self.use_color = use_color and sys.stdout.isatty()
        self.start_time = time.time()
    
    def _colorize(self, text: str, color_code: str) -> str:
        """Apply color codes if color is enabled."""
        if not self.use_color:
            return text
        return f"\033[{color_code}m{text}\033[0m"
    
    def _get_level_prefix(self, level: LogLevel) -> str:
        """Get formatted prefix for log level."""
        prefixes = {
            LogLevel.DEBUG: self._colorize("[DEBUG]", "90"),  # Gray
            LogLevel.INFO: self._colorize("[INFO]", "96"),    # Cyan
            LogLevel.WARN: self._colorize("[WARN]", "93"),    # Yellow
            LogLevel.ERROR: self._colorize("[ERROR]", "91"),  # Red
            LogLevel.SUCCESS: self._colorize("[OK]", "92"),   # Green
        }
        return prefixes.get(level, "[LOG]")
    
    def log(self, level: LogLevel, message: str):
        """Log a message with the specified level."""
        prefix = self._get_level_prefix(level)
        print(f"{prefix} {message}")
    
    def debug(self, message: str):
        """Log a debug message."""
        self.log(LogLevel.DEBUG, message)
    
    def info(self, message: str):
        """Log an info message."""
        self.log(LogLevel.INFO, message)
    
    def warn(self, message: str):
        """Log a warning message."""
        self.log(LogLevel.WARN, message)
    
    def error(self, message: str):
        """Log an error message."""
        self.log(LogLevel.ERROR, message)
    
    def success(self, message: str):
        """Log a success message."""
        self.log(LogLevel.SUCCESS, message)
    
    def start_step(self, name: str, description: str) -> int:
        """Start a new step and return its index."""
        step = ProgressStep(name=name, description=description, started=time.time())
        self.steps.append(step)
        step_index = len(self.steps) - 1
        self.current_step = step_index + 1
        
        # Display progress
        progress = f"({self.current_step}/{self.total_steps})" if self.total_steps > 0 else f"({self.current_step})"
        self.info(f"{progress} {description}")
        
        return step_index
    
    def complete_step(self, step_index: int, success_message: Optional[str] = None):
        """Mark a step as completed."""
        if 0 <= step_index < len(self.steps):
            step = self.steps[step_index]
            step.completed = time.time()
            
            if success_message:
                self.success(success_message)
            elif step.duration:
                self.success(f"{step.name} completed in {step.duration:.1f}s")
            else:
                self.success(f"{step.name} completed")
    
    def fail_step(self, step_index: int, error_message: str):
        """Mark a step as failed."""
        if 0 <= step_index < len(self.steps):
            step = self.steps[step_index]
            step.error = error_message
            self.error(f"{step.name} failed: {error_message}")
    
    def show_summary(self):
        """Show a summary of all steps."""
        total_time = time.time() - self.start_time
        completed_steps = sum(1 for step in self.steps if step.is_completed)
        failed_steps = sum(1 for step in self.steps if step.is_error)
        
        print("\n" + "="*50)
        print("INSTALLATION SUMMARY")
        print("="*50)
        print(f"Total time: {total_time:.1f}s")
        print(f"Steps completed: {completed_steps}/{len(self.steps)}")
        
        if failed_steps > 0:
            print(f"Steps failed: {failed_steps}")
            print("\nFailed steps:")
            for i, step in enumerate(self.steps):
                if step.is_error:
                    print(f"  {i+1}. {step.name}: {step.error}")
        else:
            print("All steps completed successfully!")
        
        print("="*50)
    
    def get_status_json(self) -> str:
        """Get current status as JSON for integration with other tools."""
        status = {
            "total_steps": len(self.steps),
            "completed_steps": sum(1 for step in self.steps if step.is_completed),
            "failed_steps": sum(1 for step in self.steps if step.is_error),
            "current_step": self.current_step,
            "total_time": time.time() - self.start_time,
            "steps": [
                {
                    "name": step.name,
                    "description": step.description,
                    "started": step.started,
                    "completed": step.completed,
                    "error": step.error,
                    "duration": step.duration,
                }
                for step in self.steps
            ]
        }
        return json.dumps(status, indent=2)


def demo_progress_reporter():
    """Demonstrate the enhanced progress reporter."""
    print("🚀 ZFS Installation Starting...")
    
    # Simulate the steps from the bash script
    steps = [
        ("prereqs", "Installing rescue prerequisites"),
        ("partition", "Partitioning disk"),
        ("pools", "Creating ZFS pools"),
        ("datasets", "Creating ZFS datasets"),
        ("debootstrap", "Running debootstrap"),
        ("chroot", "Configuring system in chroot"),
        ("teardown", "Cleaning up and setting runtime mountpoints"),
    ]
    
    reporter = ProgressReporter(total_steps=len(steps))
    
    try:
        for i, (name, description) in enumerate(steps):
            step_idx = reporter.start_step(name, description)
            
            # Simulate work with random delays
            import random
            work_time = random.uniform(0.5, 2.0)
            time.sleep(work_time)
            
            # Simulate occasional warnings
            if random.random() < 0.3:
                reporter.warn(f"Minor issue during {name} (continuing)")
            
            # Simulate very rare failures (uncomment to test error handling)
            # if random.random() < 0.1:
            #     reporter.fail_step(step_idx, f"Simulated failure in {name}")
            #     raise Exception(f"Failed at step: {name}")
            
            reporter.complete_step(step_idx)
        
        reporter.success("🎉 ZFS installation completed successfully!")
        
    except Exception as e:
        reporter.error(f"Installation failed: {e}")
    finally:
        reporter.show_summary()


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="ZFS installer progress reporter")
    parser.add_argument("--demo", action="store_true", help="Run demonstration")
    parser.add_argument("--test-colors", action="store_true", help="Test color output")
    args = parser.parse_args()
    
    if args.demo:
        demo_progress_reporter()
    elif args.test_colors:
        reporter = ProgressReporter()
        reporter.debug("This is a debug message")
        reporter.info("This is an info message")
        reporter.warn("This is a warning message")
        reporter.error("This is an error message")
        reporter.success("This is a success message")
    else:
        print("Use --demo to see progress reporter in action")
        print("Use --test-colors to test color output")