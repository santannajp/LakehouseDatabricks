#!/usr/bin/env python3
"""Create or update the versioned Grid Intelligence Genie space."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from databricks.sdk import WorkspaceClient

DEFAULT_DEFINITION = Path(__file__).resolve().parents[1] / "src" / "genie" / "grid_intelligence_operacoes.json"
DEFAULT_PARENT_PATH = "/Workspace/Users/santannajp@gmail.com/genie_spaces"
SPACE_TITLE = "Grid Intelligence — Copiloto de Operações"
SPACE_DESCRIPTION = (
    "Agente conversacional em português para diretoria e operação da Luz do Vale. "
    "Responde perguntas sobre continuidade, prioridade de inspeção, saúde do cliente e operação diária "
    "usando exclusivamente entidades Gold e a metric view governada de continuidade."
)


def canonical_parent_path(path: str) -> str:
    """Use the path representation returned by the Genie API."""
    return path.removeprefix("/Workspace") or "/"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, help="Databricks CLI/SDK profile")
    parser.add_argument("--catalogo", required=True, help="Unity Catalog to substitute for ${catalogo}")
    parser.add_argument("--warehouse-id", required=True, help="SQL warehouse used by the Genie space")
    parser.add_argument("--definition", type=Path, default=DEFAULT_DEFINITION)
    parser.add_argument("--parent-path", default=DEFAULT_PARENT_PATH)
    parser.add_argument("--title", default=SPACE_TITLE)
    parser.add_argument("--dry-run", action="store_true", help="Validate and print the rendered definition only")
    return parser.parse_args()


def render_definition(path: Path, catalogo: str) -> str:
    source = path.read_text(encoding="utf-8")
    if "${catalogo}" not in source:
        raise ValueError(f"Definition must contain the ${catalogo} marker: {path}")
    rendered = source.replace("${catalogo}", catalogo)
    payload = json.loads(rendered)
    if payload.get("version") != 2:
        raise ValueError("Genie serialized space must use version 2")
    if "${catalogo}" in rendered:
        raise ValueError("Catalog marker was not fully substituted")
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def list_spaces(workspace: WorkspaceClient):
    response = workspace.genie.list_spaces(page_size=100)
    spaces = list(response.spaces)
    while response.next_page_token:
        response = workspace.genie.list_spaces(page_size=100, page_token=response.next_page_token)
        spaces.extend(response.spaces)
    return spaces


def main() -> None:
    args = parse_args()
    serialized_space = render_definition(args.definition, args.catalogo)

    if args.dry_run:
        print(serialized_space)
        return

    workspace = WorkspaceClient(profile=args.profile)
    parent_path = canonical_parent_path(args.parent_path)
    workspace.workspace.mkdirs(parent_path)
    existing = None
    for space in list_spaces(workspace):
        if space.title != args.title:
            continue
        details = workspace.genie.get_space(space.space_id)
        if canonical_parent_path(details.parent_path or "") == parent_path:
            existing = details
            break

    if existing:
        updated = workspace.genie.update_space(
            existing.space_id,
            description=SPACE_DESCRIPTION,
            etag=existing.etag,
            parent_path=parent_path,
            serialized_space=serialized_space,
            title=args.title,
            warehouse_id=args.warehouse_id,
        )
        print(f"updated space_id={updated.space_id} title={updated.title}")
    else:
        created = workspace.genie.create_space(
            warehouse_id=args.warehouse_id,
            description=SPACE_DESCRIPTION,
            parent_path=parent_path,
            serialized_space=serialized_space,
            title=args.title,
        )
        print(f"created space_id={created.space_id} title={created.title}")


if __name__ == "__main__":
    main()
