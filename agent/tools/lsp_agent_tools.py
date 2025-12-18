"""
LSP agent tool wrappers for registration with the agent.

These tools provide a user-friendly interface to LSP functionality.
"""

from .lsp import (
    find_references as lsp_find_references_impl,
    go_to_definition as lsp_go_to_definition_impl,
    workspace_symbol as lsp_workspace_symbol_impl,
)


async def search_symbols_tool(query: str, file_path: str = "") -> str:
    """Search for symbols across the workspace.

    Find functions, classes, variables, and other symbols by name across the entire project.

    Args:
        query: Symbol name or pattern to search for
        file_path: Optional file path to determine workspace context
    """
    result = await lsp_workspace_symbol_impl(query, file_path if file_path else None)
    if result.get("success"):
        symbols = result.get("symbols", [])
        count = result.get("count", 0)
        if count == 0:
            return f"No symbols found matching '{query}'"

        lines = [f"Found {count} symbol(s) matching '{query}':\n"]
        for sym in symbols[:20]:  # Limit to 20 results
            name = sym.get("name", "")
            kind = sym.get("kind", 0)
            location = sym.get("location", {})
            uri = location.get("uri", "").replace("file://", "")
            range_info = location.get("range", {})
            start = range_info.get("start", {})
            line = start.get("line", 0) + 1  # Convert to 1-based
            container = sym.get("containerName", "")

            kind_names = {
                1: "File", 2: "Module", 3: "Namespace", 4: "Package",
                5: "Class", 6: "Method", 7: "Property", 8: "Field",
                9: "Constructor", 10: "Enum", 11: "Interface", 12: "Function",
                13: "Variable", 14: "Constant", 15: "String", 16: "Number",
                17: "Boolean", 18: "Array", 19: "Object", 20: "Key",
                21: "Null", 22: "EnumMember", 23: "Struct", 24: "Event",
                25: "Operator", 26: "TypeParameter"
            }
            kind_str = kind_names.get(kind, f"Kind{kind}")

            loc_str = f"{uri}:{line}" if uri else ""
            container_str = f" in {container}" if container else ""
            lines.append(f"  {kind_str}: {name}{container_str} @ {loc_str}")

        if len(symbols) > 20:
            lines.append(f"\n  ... and {len(symbols) - 20} more")

        return "\n".join(lines)
    return f"Error: {result.get('error', 'Unknown error')}"


async def goto_definition_tool(file_path: str, line: int, character: int) -> str:
    """Navigate to the definition of a symbol.

    Find where a function, class, or variable is defined.

    Args:
        file_path: Absolute path to the source file
        line: Line number (0-based)
        character: Character offset within the line (0-based)
    """
    result = await lsp_go_to_definition_impl(file_path, line, character)
    if result.get("success"):
        definitions = result.get("definitions", [])
        count = result.get("count", 0)

        if count == 0:
            return "No definition found at this position"

        lines = [f"Found {count} definition(s):\n"]
        for defn in definitions:
            uri = defn.get("uri", "").replace("file://", "")
            range_info = defn.get("range", {})
            start = range_info.get("start", {})
            def_line = start.get("line", 0) + 1  # Convert to 1-based
            def_char = start.get("character", 0) + 1

            lines.append(f"  {uri}:{def_line}:{def_char}")

        return "\n".join(lines)
    return f"Error: {result.get('error', 'Unknown error')}"


async def find_symbol_references_tool(file_path: str, line: int, character: int, include_declaration: bool = True) -> str:
    """Find all references to a symbol across the project.

    Locate everywhere a function, class, or variable is used.

    Args:
        file_path: Absolute path to the source file
        line: Line number (0-based)
        character: Character offset within the line (0-based)
        include_declaration: Whether to include the symbol's declaration
    """
    result = await lsp_find_references_impl(file_path, line, character, include_declaration)
    if result.get("success"):
        references = result.get("references", [])
        count = result.get("count", 0)
        files = result.get("files", [])

        if count == 0:
            return "No references found for this symbol"

        lines = [f"Found {count} reference(s) across {len(files)} file(s):\n"]

        # Group by file
        by_file: dict[str, list] = {}
        for ref in references:
            uri = ref.get("uri", "")
            if uri not in by_file:
                by_file[uri] = []
            by_file[uri].append(ref)

        # Show up to 5 files
        for file_uri in sorted(by_file.keys())[:5]:
            refs = by_file[file_uri]
            lines.append(f"\n  {file_uri} ({len(refs)} reference(s)):")

            # Show up to 10 references per file
            for ref in refs[:10]:
                range_info = ref.get("range", {})
                start = range_info.get("start", {})
                ref_line = start.get("line", 0) + 1  # Convert to 1-based
                ref_char = start.get("character", 0) + 1
                lines.append(f"    Line {ref_line}, Column {ref_char}")

            if len(refs) > 10:
                lines.append(f"    ... and {len(refs) - 10} more in this file")

        if len(by_file) > 5:
            remaining_files = len(by_file) - 5
            remaining_refs = sum(len(refs) for uri, refs in by_file.items() if uri not in list(by_file.keys())[:5])
            lines.append(f"\n  ... and {remaining_refs} more references in {remaining_files} other files")

        return "\n".join(lines)
    return f"Error: {result.get('error', 'Unknown error')}"
