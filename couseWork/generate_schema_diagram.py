from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from xml.sax.saxutils import escape


@dataclass(frozen=True)
class Table:
    name: str
    fields: list[str]
    x: int
    y: int
    width: int = 300

    @property
    def height(self) -> int:
        return 56 + len(self.fields) * 24


@dataclass(frozen=True)
class Relation:
    source: str
    target: str
    label: str
    source_side: str = "right"
    target_side: str = "left"


BOX_FILL = "#fffaf2"
BOX_STROKE = "#3c2f2f"
HEADER_FILL = "#d66b4d"
TEXT_COLOR = "#211a1a"
PANEL_FILL = "#f4efe6"
RELATION_COLOR = "#6a4a3c"
BACKGROUND = "#f8f3ea"


TABLES = [
    Table(
        "users",
        [
            "id (PK)",
            "email (UNIQUE)",
            "password_hash",
            "role {buyer|provider|admin}",
            "created_at",
        ],
        x=40,
        y=40,
    ),
    Table(
        "profiles",
        [
            "user_id (PK, FK -> users.id)",
            "name",
            "organization",
            "balance",
        ],
        x=40,
        y=250,
    ),
    Table(
        "nodes",
        [
            "id (PK)",
            "provider_id (FK -> users.id)",
            "status {online|offline|busy}",
            "created_at",
        ],
        x=380,
        y=40,
    ),
    Table(
        "node_specs",
        [
            "node_id (PK, FK -> nodes.id)",
            "cpu_cores",
            "ram_gb",
            "gpu_model",
            "gpu_vram_gb",
            "disk_gb",
        ],
        x=380,
        y=230,
    ),
    Table(
        "node_pricing",
        [
            "node_id (PK, FK -> nodes.id)",
            "price_cpu_hour",
            "price_gpu_hour",
            "price_ram_gb_hour",
        ],
        x=380,
        y=470,
    ),
    Table(
        "tasks",
        [
            "id (PK)",
            "user_id (FK -> users.id)",
            "status {created|running|completed|failed}",
            "total_cost",
            "created_at",
        ],
        x=720,
        y=40,
    ),
    Table(
        "task_configs",
        [
            "task_id (PK, FK -> tasks.id)",
            "solver_type (OpenFOAM, etc.)",
            "parameters_json",
            "docker_image",
            "estimated_cost",
        ],
        x=720,
        y=250,
    ),
    Table(
        "jobs",
        [
            "id (PK)",
            "task_id (FK -> tasks.id)",
            "node_id (FK -> nodes.id, nullable)",
            "status {queued|running|failed|completed}",
            "retry_count",
            "created_at",
            "started_at",
            "finished_at",
        ],
        x=1060,
        y=40,
    ),
    Table(
        "job_results",
        [
            "id (PK)",
            "job_id (FK -> jobs.id)",
            "output_path",
            "checksum",
            "created_at",
        ],
        x=1400,
        y=40,
    ),
    Table(
        "validations",
        [
            "id (PK)",
            "job_id (FK -> jobs.id)",
            "status {valid|invalid}",
            "reason",
            "created_at",
        ],
        x=1400,
        y=250,
    ),
    Table(
        "job_metrics",
        [
            "id (PK)",
            "job_id (FK -> jobs.id)",
            "cpu_usage",
            "gpu_usage",
            "memory_usage",
            "timestamp",
        ],
        x=1400,
        y=470,
    ),
    Table(
        "job_logs",
        [
            "id (PK)",
            "job_id (FK -> jobs.id)",
            "log_text",
            "created_at",
        ],
        x=1400,
        y=710,
    ),
    Table(
        "transactions",
        [
            "id (PK)",
            "user_id (FK -> users.id)",
            "type {debit|credit}",
            "amount",
            "created_at",
        ],
        x=40,
        y=510,
    ),
    Table(
        "job_costs",
        [
            "id (PK)",
            "job_id (FK -> jobs.id)",
            "cpu_cost",
            "gpu_cost",
            "total_cost",
        ],
        x=1060,
        y=320,
    ),
    Table(
        "payouts",
        [
            "id (PK)",
            "provider_id (FK -> users.id)",
            "amount",
            "status {pending|paid}",
            "created_at",
        ],
        x=40,
        y=760,
    ),
]


RELATIONS = [
    Relation("profiles", "users", "1:1", "top", "bottom"),
    Relation("nodes", "users", "N:1", "left", "right"),
    Relation("transactions", "users", "N:1", "top", "bottom"),
    Relation("payouts", "users", "N:1", "top", "bottom"),
    Relation("node_specs", "nodes", "1:1", "top", "bottom"),
    Relation("node_pricing", "nodes", "1:1", "top", "bottom"),
    Relation("tasks", "users", "N:1", "left", "right"),
    Relation("task_configs", "tasks", "1:1", "top", "bottom"),
    Relation("jobs", "tasks", "N:1", "left", "right"),
    Relation("jobs", "nodes", "N:1", "left", "right"),
    Relation("job_results", "jobs", "1:1", "left", "right"),
    Relation("validations", "jobs", "1:1", "left", "right"),
    Relation("job_metrics", "jobs", "N:1", "left", "right"),
    Relation("job_logs", "jobs", "N:1", "left", "right"),
    Relation("job_costs", "jobs", "1:1", "top", "bottom"),
]


INDEXES = [
    "users(email) UNIQUE",
    "jobs(task_id, status)",
    "jobs(node_id)",
    "job_metrics(job_id, timestamp)",
    "transactions(user_id, created_at)",
    "nodes(status)",
]


SCENARIOS = [
    (
        "Task launch",
        [
            "1. INSERT tasks",
            "2. INSERT task_configs",
            "3. INSERT jobs (batch)",
        ],
    ),
    (
        "Node assignment",
        [
            "1. UPDATE jobs SET node_id, status='running'",
            "2. UPDATE nodes SET status='busy'",
        ],
    ),
    (
        "Job completion",
        [
            "1. UPDATE jobs SET status='completed', finished_at",
            "2. INSERT job_results",
            "3. INSERT validations",
            "4. INSERT job_costs",
            "5. UPDATE tasks.total_cost",
        ],
    ),
    (
        "Debit funds",
        [
            "1. INSERT transactions (debit)",
            "2. UPDATE profiles.balance",
        ],
    ),
]


DESIGN_NOTES = [
    "parameters_json keeps PDE configuration flexible.",
    "tasks and jobs are separated for horizontal scaling.",
    "validations stays explicit to preserve trust in results.",
    "node_specs is isolated so hardware can evolve independently.",
    "job_metrics is modeled as time-series and can move to a TSDB later.",
]


def anchor(table: Table, side: str) -> tuple[int, int]:
    if side == "left":
        return (table.x, table.y + table.height // 2)
    if side == "right":
        return (table.x + table.width, table.y + table.height // 2)
    if side == "top":
        return (table.x + table.width // 2, table.y)
    if side == "bottom":
        return (table.x + table.width // 2, table.y + table.height)
    raise ValueError(f"Unsupported side: {side}")


def orthogonal_path(start: tuple[int, int], end: tuple[int, int]) -> str:
    sx, sy = start
    ex, ey = end
    if sx == ex or sy == ey:
        return f"M {sx} {sy} L {ex} {ey}"

    mid_x = sx + (ex - sx) // 2
    return f"M {sx} {sy} L {mid_x} {sy} L {mid_x} {ey} L {ex} {ey}"


def render_text(lines: Iterable[str], x: int, y: int, size: int = 18, weight: str = "400") -> list[str]:
    rendered = []
    for index, line in enumerate(lines):
        rendered.append(
            f'<text x="{x}" y="{y + index * (size + 8)}" font-size="{size}" '
            f'font-weight="{weight}" fill="{TEXT_COLOR}">{escape(line)}</text>'
        )
    return rendered


def draw_table(table: Table) -> list[str]:
    parts = [
        f'<rect x="{table.x}" y="{table.y}" width="{table.width}" height="{table.height}" '
        f'rx="18" fill="{BOX_FILL}" stroke="{BOX_STROKE}" stroke-width="2" />',
        f'<rect x="{table.x}" y="{table.y}" width="{table.width}" height="46" '
        f'rx="18" fill="{HEADER_FILL}" stroke="{BOX_STROKE}" stroke-width="2" />',
        f'<rect x="{table.x}" y="{table.y + 28}" width="{table.width}" height="18" '
        f'fill="{HEADER_FILL}" stroke="none" />',
        f'<text x="{table.x + 18}" y="{table.y + 29}" font-size="24" font-weight="700" fill="#fffdf8">{escape(table.name)}</text>',
        f'<line x1="{table.x}" y1="{table.y + 46}" x2="{table.x + table.width}" y2="{table.y + 46}" '
        f'stroke="{BOX_STROKE}" stroke-width="2" />',
    ]
    for index, field in enumerate(table.fields):
        parts.append(
            f'<text x="{table.x + 18}" y="{table.y + 75 + index * 24}" font-size="16" '
            f'fill="{TEXT_COLOR}">{escape(field)}</text>'
        )
    return parts


def draw_panel(title: str, x: int, y: int, width: int, lines: list[str], line_height: int = 22) -> list[str]:
    height = 72 + len(lines) * line_height
    parts = [
        f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="22" '
        f'fill="{PANEL_FILL}" stroke="{BOX_STROKE}" stroke-width="2" />',
        f'<text x="{x + 20}" y="{y + 34}" font-size="24" font-weight="700" fill="{TEXT_COLOR}">{escape(title)}</text>',
        f'<line x1="{x + 16}" y1="{y + 48}" x2="{x + width - 16}" y2="{y + 48}" stroke="{BOX_STROKE}" stroke-width="2" />',
    ]
    parts.extend(render_text(lines, x + 20, y + 76, size=16))
    return parts


def draw_scenarios(x: int, y: int, width: int) -> list[str]:
    lines: list[str] = []
    for title, steps in SCENARIOS:
        lines.append(title)
        lines.extend(steps)
        lines.append("")
    if lines and lines[-1] == "":
        lines.pop()

    height = 76 + len(lines) * 20
    parts = [
        f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="22" fill="{PANEL_FILL}" stroke="{BOX_STROKE}" stroke-width="2" />',
        f'<text x="{x + 20}" y="{y + 34}" font-size="24" font-weight="700" fill="{TEXT_COLOR}">Transactional scenarios</text>',
        f'<line x1="{x + 16}" y1="{y + 48}" x2="{x + width - 16}" y2="{y + 48}" stroke="{BOX_STROKE}" stroke-width="2" />',
    ]

    cursor_y = y + 76
    for line in lines:
        if not line:
            cursor_y += 10
            continue
        weight = "700" if not line.startswith(("1.", "2.", "3.", "4.", "5.")) else "400"
        size = 17 if weight == "700" else 15
        parts.append(
            f'<text x="{x + 20}" y="{cursor_y}" font-size="{size}" font-weight="{weight}" '
            f'fill="{TEXT_COLOR}">{escape(line)}</text>'
        )
        cursor_y += 22
    return parts


def build_svg() -> str:
    table_map = {table.name: table for table in TABLES}
    width = 2280
    height = 1120

    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<defs>',
        '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">',
        '<feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#000000" flood-opacity="0.14" />',
        '</filter>',
        '<marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto">',
        f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{RELATION_COLOR}" />',
        '</marker>',
        '</defs>',
        f'<rect width="{width}" height="{height}" fill="{BACKGROUND}" />',
        '<text x="40" y="1010" font-size="34" font-weight="700" fill="#241c1c">Distributed Compute Marketplace Schema</text>',
        '<text x="40" y="1046" font-size="18" fill="#4c3b3b">Core entities, key relationships, OLTP indexes, transaction flows, and design notes.</text>',
    ]

    for relation in RELATIONS:
        source = table_map[relation.source]
        target = table_map[relation.target]
        start = anchor(source, relation.source_side)
        end = anchor(target, relation.target_side)
        path = orthogonal_path(start, end)
        parts.append(
            f'<path d="{path}" fill="none" stroke="{RELATION_COLOR}" stroke-width="3" marker-end="url(#arrow)" opacity="0.92" />'
        )
        label_x = (start[0] + end[0]) // 2
        label_y = (start[1] + end[1]) // 2 - 8
        parts.append(
            f'<rect x="{label_x - 18}" y="{label_y - 16}" width="44" height="24" rx="12" fill="#fff9f0" stroke="{RELATION_COLOR}" stroke-width="1.5" />'
        )
        parts.append(
            f'<text x="{label_x - 7}" y="{label_y + 1}" font-size="13" font-weight="700" fill="{RELATION_COLOR}">{escape(relation.label)}</text>'
        )

    parts.append('<g filter="url(#shadow)">')
    for table in TABLES:
        parts.extend(draw_table(table))
    parts.append('</g>')

    parts.extend(draw_panel("Critical OLTP indexes", 1760, 40, 470, INDEXES))
    parts.extend(draw_scenarios(1760, 300, 470))
    parts.extend(draw_panel("Design notes", 1760, 760, 470, DESIGN_NOTES))

    parts.append('</svg>')
    return "\n".join(parts)


def main() -> None:
    output_path = Path(__file__).with_name("compute_marketplace_schema.svg")
    output_path.write_text(build_svg(), encoding="utf-8")
    print(f"Schema image written to {output_path}")


if __name__ == "__main__":
    main()