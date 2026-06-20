from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape


@dataclass(frozen=True)
class Box:
    title: str
    lines: list[str]
    x: int
    y: int
    width: int = 280
    header_fill: str = "#2f5d50"
    body_fill: str = "#f8f5ef"

    @property
    def height(self) -> int:
        return 56 + 22 * len(self.lines)


def draw_box(box: Box, text_color: str = "#1c1816", stroke: str = "#2d2a26") -> list[str]:
    parts = [
        f'<rect x="{box.x}" y="{box.y}" width="{box.width}" height="{box.height}" rx="18" fill="{box.body_fill}" stroke="{stroke}" stroke-width="2" />',
        f'<rect x="{box.x}" y="{box.y}" width="{box.width}" height="44" rx="18" fill="{box.header_fill}" stroke="{stroke}" stroke-width="2" />',
        f'<rect x="{box.x}" y="{box.y + 24}" width="{box.width}" height="20" fill="{box.header_fill}" stroke="none" />',
        f'<text x="{box.x + 16}" y="{box.y + 28}" font-size="22" font-weight="700" fill="#fffdf9">{escape(box.title)}</text>',
        f'<line x1="{box.x}" y1="{box.y + 44}" x2="{box.x + box.width}" y2="{box.y + 44}" stroke="{stroke}" stroke-width="2" />',
    ]
    for index, line in enumerate(box.lines):
        parts.append(
            f'<text x="{box.x + 16}" y="{box.y + 70 + index * 22}" font-size="15" fill="{text_color}">{escape(line)}</text>'
        )
    return parts


def anchor(box: Box, side: str) -> tuple[int, int]:
    if side == "left":
        return (box.x, box.y + box.height // 2)
    if side == "right":
        return (box.x + box.width, box.y + box.height // 2)
    if side == "top":
        return (box.x + box.width // 2, box.y)
    return (box.x + box.width // 2, box.y + box.height)


def path(start: tuple[int, int], end: tuple[int, int]) -> str:
    sx, sy = start
    ex, ey = end
    if sx == ex or sy == ey:
        return f"M {sx} {sy} L {ex} {ey}"
    mid_x = sx + (ex - sx) // 2
    return f"M {sx} {sy} L {mid_x} {sy} L {mid_x} {ey} L {ex} {ey}"


def build_schema_svg() -> str:
    dims = [
        Box("dim_date", ["date_key (PK)", "full_date", "month_name", "quarter_number", "year_number"], 40, 60, header_fill="#355c7d"),
        Box("dim_organization", ["organization_sk (PK)", "organization_name"], 40, 270, header_fill="#355c7d"),
        Box("dim_user_account_scd2", ["user_sk (PK)", "user_nk", "user_name", "role_code", "organization_sk (FK)", "effective_from", "effective_to", "is_current"], 360, 60, 320, "#355c7d"),
        Box("dim_solver_family", ["solver_family_sk (PK)", "solver_family_code", "solver_family_name"], 720, 60, header_fill="#355c7d"),
        Box("dim_solver", ["solver_sk (PK)", "solver_type", "solver_family_sk (FK)"], 720, 230, header_fill="#355c7d"),
        Box("dim_workload_profile", ["workload_sk (PK)", "workload_nk", "solver_sk (FK)", "docker_image", "parameter_signature", "estimated_cost_band"], 1050, 60, 330, "#355c7d"),
        Box("dim_parameter_tag", ["parameter_tag_sk (PK)", "tag_key", "tag_value", "tag_label"], 1050, 300, 330, "#355c7d"),
        Box("bridge_workload_parameter_tag", ["workload_sk (FK)", "parameter_tag_sk (FK)", "allocation_weight"], 1410, 160, 330, "#6c5b7b"),
        Box("dim_gpu_family", ["gpu_family_sk (PK)", "gpu_family_name"], 40, 500, header_fill="#355c7d"),
        Box("dim_node", ["node_sk (PK)", "node_nk", "gpu_family_sk (FK)", "cpu_cores", "ram_gb", "performance_tier", "price_band"], 360, 460, 320, "#355c7d"),
        Box("dim_task_status", ["task_status_sk (PK)", "status_code", "status_group"], 720, 430, header_fill="#355c7d"),
        Box("dim_job_outcome", ["job_outcome_sk (PK)", "job_status_code", "validation_status_code", "outcome_label"], 720, 620, header_fill="#355c7d"),
        Box("dim_finance_event", ["finance_event_sk (PK)", "finance_event_code", "finance_event_group", "flow_direction"], 1050, 540, 330, "#355c7d"),
    ]

    facts = [
        Box("fact_task_daily", ["date_key (FK)", "buyer_user_sk (FK)", "workload_sk (FK)", "task_status_sk (FK)", "tasks_created_count", "jobs_requested_count", "total_estimated_cost", "total_actual_cost"], 40, 780, 320, "#c06c4e", "#fff6ee"),
        Box("fact_job_execution_daily", ["date_key (FK)", "buyer_user_sk (FK)", "provider_user_sk (FK)", "node_sk (FK)", "workload_sk (FK)", "job_outcome_sk (FK)", "jobs_count", "total_job_cost", "avg_cpu_usage"], 420, 760, 360, "#c06c4e", "#fff6ee"),
        Box("fact_finance_daily", ["date_key (FK)", "user_sk (FK)", "finance_event_sk (FK)", "event_count", "total_amount"], 840, 790, 320, "#c06c4e", "#fff6ee"),
    ]

    all_boxes = {box.title: box for box in dims + facts}
    relations = [
        ("dim_user_account_scd2", "dim_organization", "left", "right", "SCD2"),
        ("dim_solver", "dim_solver_family", "top", "bottom", "snowflake"),
        ("dim_workload_profile", "dim_solver", "left", "right", "snowflake"),
        ("bridge_workload_parameter_tag", "dim_workload_profile", "left", "right", "bridge"),
        ("bridge_workload_parameter_tag", "dim_parameter_tag", "bottom", "top", "bridge"),
        ("dim_node", "dim_gpu_family", "left", "right", "snowflake"),
        ("fact_task_daily", "dim_date", "top", "bottom", "FK"),
        ("fact_task_daily", "dim_user_account_scd2", "top", "bottom", "FK"),
        ("fact_task_daily", "dim_workload_profile", "top", "bottom", "FK"),
        ("fact_task_daily", "dim_task_status", "top", "bottom", "FK"),
        ("fact_job_execution_daily", "dim_date", "top", "bottom", "FK"),
        ("fact_job_execution_daily", "dim_user_account_scd2", "top", "bottom", "FK"),
        ("fact_job_execution_daily", "dim_node", "top", "bottom", "FK"),
        ("fact_job_execution_daily", "dim_workload_profile", "top", "bottom", "FK"),
        ("fact_job_execution_daily", "dim_job_outcome", "top", "bottom", "FK"),
        ("fact_finance_daily", "dim_date", "top", "bottom", "FK"),
        ("fact_finance_daily", "dim_user_account_scd2", "top", "bottom", "FK"),
        ("fact_finance_daily", "dim_finance_event", "top", "bottom", "FK"),
    ]

    width = 1780
    height = 1080
    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M 0 0 L 10 5 L 0 10 z" fill="#6b4f45" /></marker></defs>',
        f'<rect width="{width}" height="{height}" fill="#f4efe8" />',
        '<text x="40" y="38" font-size="30" font-weight="700" fill="#1e1a18">Compute Marketplace OLAP Snowflake Schema</text>',
        '<text x="40" y="64" font-size="16" fill="#4d423d">Separate OLAP database, aggregated facts, SCD Type 2 user dimension, and workload parameter bridge.</text>',
    ]

    for source, target, source_side, target_side, label in relations:
        start = anchor(all_boxes[source], source_side)
        end = anchor(all_boxes[target], target_side)
        parts.append(
            f'<path d="{path(start, end)}" fill="none" stroke="#6b4f45" stroke-width="3" marker-end="url(#arrow)" opacity="0.9" />'
        )
        label_x = (start[0] + end[0]) // 2
        label_y = (start[1] + end[1]) // 2 - 6
        parts.append(f'<rect x="{label_x - 26}" y="{label_y - 14}" width="60" height="22" rx="11" fill="#fffaf4" stroke="#6b4f45" stroke-width="1.5" />')
        parts.append(f'<text x="{label_x - 11}" y="{label_y + 1}" font-size="12" font-weight="700" fill="#6b4f45">{escape(label)}</text>')

    for box in dims + facts:
        parts.extend(draw_box(box))

    parts.append('<rect x="1260" y="760" width="470" height="250" rx="18" fill="#ece5d8" stroke="#2d2a26" stroke-width="2" />')
    parts.append('<text x="1280" y="796" font-size="24" font-weight="700" fill="#1c1816">Design Notes</text>')
    notes = [
        'Fact tables are daily aggregates, not OLTP copies.',
        'dim_user_account_scd2 tracks role and organization history.',
        'bridge_workload_parameter_tag supports multi-valued JSON attributes.',
        'Solver and GPU dimensions normalize reusable hierarchies.',
        'Power BI can consume the reporting views directly.'
    ]
    for index, line in enumerate(notes):
        parts.append(f'<text x="1280" y="836" font-size="16" fill="#1c1816">{escape(line)}</text>')
        if index < len(notes) - 1:
            parts[-1] = parts[-1].replace('836', str(836 + index * 28))

    parts.append('</svg>')
    return '\n'.join(parts)


def build_report_svg() -> str:
    width = 1600
    height = 900
    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        f'<rect width="{width}" height="{height}" fill="#f3efe7" />',
        '<text x="48" y="54" font-size="30" font-weight="700" fill="#1d1917">Compute Marketplace Performance Overview</text>',
        '<text x="48" y="82" font-size="16" fill="#5b4f49">Power BI wireframe based on the OLAP reporting views.</text>',
        '<rect x="48" y="118" width="260" height="92" rx="18" fill="#fffaf4" stroke="#3a312d" stroke-width="2" />',
        '<text x="66" y="150" font-size="22" font-weight="700" fill="#1d1917">Slicer: Month</text>',
        '<text x="66" y="180" font-size="15" fill="#514741">2026-06, 2026-07, ...</text>',
        '<rect x="332" y="118" width="260" height="92" rx="18" fill="#fffaf4" stroke="#3a312d" stroke-width="2" />',
        '<text x="350" y="150" font-size="22" font-weight="700" fill="#1d1917">Slicer: Solver Family</text>',
        '<text x="350" y="180" font-size="15" fill="#514741">CFD Solvers, Other Solvers</text>',
        '<rect x="616" y="118" width="260" height="92" rx="18" fill="#fffaf4" stroke="#3a312d" stroke-width="2" />',
        '<text x="634" y="150" font-size="22" font-weight="700" fill="#1d1917">Slicer: Provider Org</text>',
        '<text x="634" y="180" font-size="15" fill="#514741">North GPU Cloud, Omega Compute</text>',
    ]

    cards = [
        (920, 'Total Job Cost', '$182.7K', '#2f5d50'),
        (1130, 'Completed Jobs', '4,812', '#355c7d'),
        (1340, 'Avg Runtime', '97 min', '#c06c4e'),
    ]
    for x, title, value, color in cards:
        parts.extend([
            f'<rect x="{x}" y="118" width="190" height="92" rx="18" fill="#fffaf4" stroke="#3a312d" stroke-width="2" />',
            f'<text x="{x + 18}" y="150" font-size="18" font-weight="700" fill="#1d1917">{escape(title)}</text>',
            f'<text x="{x + 18}" y="186" font-size="28" font-weight="700" fill="{color}">{escape(value)}</text>',
        ])

    parts.extend([
        '<rect x="48" y="250" width="760" height="280" rx="22" fill="#fffaf4" stroke="#3a312d" stroke-width="2" />',
        '<text x="72" y="286" font-size="24" font-weight="700" fill="#1d1917">Daily Job Cost by Solver Family</text>',
        '<line x1="96" y1="476" x2="760" y2="476" stroke="#6e625b" stroke-width="2" />',
        '<line x1="96" y1="320" x2="96" y2="476" stroke="#6e625b" stroke-width="2" />',
        '<rect x="150" y="390" width="60" height="86" fill="#2f5d50" />',
        '<rect x="222" y="360" width="60" height="116" fill="#355c7d" />',
        '<rect x="294" y="332" width="60" height="144" fill="#c06c4e" />',
        '<rect x="418" y="408" width="60" height="68" fill="#2f5d50" />',
        '<rect x="490" y="356" width="60" height="120" fill="#355c7d" />',
        '<rect x="562" y="318" width="60" height="158" fill="#c06c4e" />',
        '<text x="140" y="504" font-size="14" fill="#514741">Week 1</text>',
        '<text x="406" y="504" font-size="14" fill="#514741">Week 2</text>',
        '<text x="640" y="340" font-size="14" fill="#2f5d50">OpenFOAM</text>',
        '<text x="640" y="364" font-size="14" fill="#355c7d">SU2</text>',
        '<text x="640" y="388" font-size="14" fill="#c06c4e">Other</text>',
    ])

    parts.extend([
        '<rect x="840" y="250" width="340" height="280" rx="22" fill="#fffaf4" stroke="#3a312d" stroke-width="2" />',
        '<text x="864" y="286" font-size="24" font-weight="700" fill="#1d1917">Validation Outcome Mix</text>',
        '<circle cx="1010" cy="390" r="92" fill="#e8e0d2" />',
        '<path d="M 1010 390 L 1010 298 A 92 92 0 1 1 935 438 z" fill="#2f5d50" />',
        '<path d="M 1010 390 L 935 438 A 92 92 0 0 1 1010 482 z" fill="#c06c4e" />',
        '<circle cx="1010" cy="390" r="44" fill="#fffaf4" />',
        '<text x="1090" y="352" font-size="15" fill="#514741">Completed and valid</text>',
        '<text x="1090" y="378" font-size="15" fill="#514741">Completed but invalid</text>',
        '<text x="1090" y="404" font-size="15" fill="#514741">Running / queued</text>',
    ])

    parts.extend([
        '<rect x="1208" y="250" width="344" height="280" rx="22" fill="#fffaf4" stroke="#3a312d" stroke-width="2" />',
        '<text x="1232" y="286" font-size="24" font-weight="700" fill="#1d1917">Provider Payouts</text>',
        '<line x1="1260" y1="470" x2="1508" y2="470" stroke="#6e625b" stroke-width="2" />',
        '<rect x="1280" y="388" width="190" height="28" fill="#355c7d" />',
        '<rect x="1280" y="430" width="142" height="28" fill="#2f5d50" />',
        '<text x="1280" y="380" font-size="14" fill="#514741">North GPU Cloud</text>',
        '<text x="1280" y="422" font-size="14" fill="#514741">Omega Compute</text>',
    ])

    parts.extend([
        '<rect x="48" y="560" width="1504" height="280" rx="22" fill="#fffaf4" stroke="#3a312d" stroke-width="2" />',
        '<text x="72" y="596" font-size="24" font-weight="700" fill="#1d1917">Task Throughput and Cost Trend</text>',
        '<polyline points="100,760 220,720 340,736 460,680 580,650 700,620 820,630 940,590 1060,570 1180,534 1300,520 1420,500" fill="none" stroke="#2f5d50" stroke-width="4" />',
        '<polyline points="100,774 220,752 340,742 460,708 580,694 700,682 820,664 940,640 1060,622 1180,604 1300,590 1420,570" fill="none" stroke="#c06c4e" stroke-width="4" />',
        '<line x1="96" y1="780" x2="1460" y2="780" stroke="#6e625b" stroke-width="2" />',
        '<text x="100" y="810" font-size="14" fill="#514741">01 Jun</text>',
        '<text x="1340" y="810" font-size="14" fill="#514741">30 Jun</text>',
        '<text x="1240" y="620" font-size="14" fill="#2f5d50">Task count</text>',
        '<text x="1240" y="646" font-size="14" fill="#c06c4e">Actual cost</text>',
    ])

    parts.append('</svg>')
    return '\n'.join(parts)


def write_asset(filename: str, content: str) -> None:
    Path(__file__).with_name(filename).write_text(content, encoding='utf-8')


def main() -> None:
    write_asset('compute_marketplace_olap_schema.svg', build_schema_svg())
    write_asset('power_bi_report_wireframe.svg', build_report_svg())
    print('Generated compute_marketplace_olap_schema.svg and power_bi_report_wireframe.svg')


if __name__ == '__main__':
    main()