"""Pydantic schema for ~/.openclaw/sandbox-profile.toml."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from pydantic import BaseModel, field_validator


class Meta(BaseModel):
    bootstrap_dir: str = ""

    @field_validator("bootstrap_dir", mode="before")
    @classmethod
    def expand_path(cls, v: str) -> str:
        if v:
            return str(Path(v).expanduser())
        return v


class Mounts(BaseModel):
    openclaw: str = ""
    config: str = ""
    agent_data: str = ""
    buildlog_data: str = ""
    secrets: str = ""
    vault: str = ""

    @field_validator("*", mode="before")
    @classmethod
    def expand_paths(cls, v: str) -> str:
        if v:
            return str(Path(v).expanduser())
        return v


class Mode(BaseModel):
    yolo: bool = False
    yolo_unsafe: bool = False
    no_docker: bool = False
    memgraph: bool = False
    memgraph_ports: list[int] = []


class Resources(BaseModel):
    cpus: int = 4
    memory: str = "8GiB"
    disk: str = "50GiB"


class SandboxProfile(BaseModel):
    meta: Meta = Meta()
    mounts: Mounts = Mounts()
    mode: Mode = Mode()
    resources: Resources = Resources()
    extra_vars: dict[str, Any] = {}
