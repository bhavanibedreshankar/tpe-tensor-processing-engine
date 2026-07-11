#!/usr/bin/env python3
"""
Generates the SV register package, C++ register header, and a rendered
Markdown register map from docs/register_map/tpe_regs.yaml (the single
source of truth). Run via `make regmap` or directly:

    python3 tools/regmap_gen.py

Do not hand-edit the generated files -- edit the YAML and regenerate.
"""
import sys
from dataclasses import dataclass, field
from pathlib import Path

import yaml
from jinja2 import Environment

_ENV = Environment(keep_trailing_newline=True)


def Template(source: str):
    return _ENV.from_string(source)

REPO_ROOT = Path(__file__).resolve().parents[1]
YAML_PATH = REPO_ROOT / "docs" / "register_map" / "tpe_regs.yaml"

SV_OUT = REPO_ROOT / "rtl" / "include" / "tpe_regs_pkg.sv"
CPP_OUT = REPO_ROOT / "model" / "include" / "tpe_regs.h"
PY_OUT = REPO_ROOT / "verif" / "cocotb_tb" / "env" / "tpe_regs.py"
MD_OUT = REPO_ROOT / "docs" / "register_map" / "generated" / "register_map.md"

GENERATED_BANNER = (
    "GENERATED FILE -- DO NOT EDIT.\n"
    "Source of truth: docs/register_map/tpe_regs.yaml\n"
    "Regenerate with: make regmap  (or python3 tools/regmap_gen.py)"
)


@dataclass
class Field:
    name: str
    msb: int
    lsb: int
    description: str = ""

    @property
    def width(self) -> int:
        return self.msb - self.lsb + 1

    @property
    def mask(self) -> int:
        return ((1 << self.width) - 1) << self.lsb


@dataclass
class Register:
    name: str
    offset: int
    access: str
    reset: int
    description: str
    fields: list = field(default_factory=list)
    abs_addr: int = 0
    block_name: str = ""

    @property
    def full_name(self) -> str:
        return f"{self.block_name.upper()}_{self.name}"


@dataclass
class Block:
    name: str
    base_address: int
    description: str
    registers: list = field(default_factory=list)


def parse_bits(bits: str) -> tuple[int, int]:
    if ":" in bits:
        msb_s, lsb_s = bits.split(":")
        return int(msb_s), int(lsb_s)
    b = int(bits)
    return b, b


def load_regmap(path: Path):
    with open(path) as f:
        doc = yaml.safe_load(f)

    blocks = []
    for b in doc["blocks"]:
        block = Block(
            name=b["name"],
            base_address=int(b["base_address"], 0) if isinstance(b["base_address"], str) else b["base_address"],
            description=b.get("description", "").strip(),
        )
        for r in b["registers"]:
            offset = int(r["offset"], 0) if isinstance(r["offset"], str) else r["offset"]
            reset = r.get("reset", 0)
            reset = int(reset, 0) if isinstance(reset, str) else reset
            reg = Register(
                name=r["name"],
                offset=offset,
                access=r["access"],
                reset=reset,
                description=r.get("description", "").strip(),
                block_name=block.name,
                abs_addr=block.base_address + offset,
            )
            for fdef in r.get("fields", []):
                msb, lsb = parse_bits(str(fdef["bits"]))
                reg.fields.append(Field(name=fdef["name"], msb=msb, lsb=lsb, description=fdef.get("description", "")))
            block.registers.append(reg)
        blocks.append(block)

    return doc, blocks


SV_TEMPLATE = Template(
    """\
// {{ banner_lines[0] }}
// {{ banner_lines[1] }}
// {{ banner_lines[2] }}
package tpe_regs_pkg;

{% for block in blocks %}
  // -------------------------------------------------------------------
  // {{ block.name | upper }} block -- base 0x{{ '%04x' % block.base_address }}
  // {{ block.description }}
  // -------------------------------------------------------------------
  localparam logic [15:0] {{ block.name | upper }}_BASE_ADDR = 16'h{{ '%04x' % block.base_address }};
{% for reg in block.registers %}
  localparam logic [15:0] {{ reg.full_name }}_ADDR    = 16'h{{ '%04x' % reg.abs_addr }};
  localparam logic [15:0] {{ reg.full_name }}_OFFSET  = 16'h{{ '%04x' % reg.offset }};
  localparam logic [31:0] {{ reg.full_name }}_RESET   = 32'h{{ '%08x' % reg.reset }};
{% for f in reg.fields %}
  localparam int {{ reg.full_name }}_{{ f.name }}_MSB = {{ f.msb }};
  localparam int {{ reg.full_name }}_{{ f.name }}_LSB = {{ f.lsb }};
{% endfor %}
{% endfor %}
{% endfor %}

endpackage : tpe_regs_pkg
"""
)

CPP_TEMPLATE = Template(
    """\
// {{ banner_lines[0] }}
// {{ banner_lines[1] }}
// {{ banner_lines[2] }}
#pragma once
#include <cstdint>

namespace tpe::regs {

{% for block in blocks %}
// ---------------------------------------------------------------------
// {{ block.name | upper }} block -- base 0x{{ '%04x' % block.base_address }}
// {{ block.description }}
// ---------------------------------------------------------------------
inline constexpr uint16_t {{ block.name | upper }}_BASE_ADDR = 0x{{ '%04x' % block.base_address }};
{% for reg in block.registers %}
inline constexpr uint16_t {{ reg.full_name }}_ADDR = 0x{{ '%04x' % reg.abs_addr }};
inline constexpr uint32_t {{ reg.full_name }}_RESET = 0x{{ '%08x' % reg.reset }}u;
{% for f in reg.fields %}
inline constexpr uint32_t {{ reg.full_name }}_{{ f.name }}_MASK = 0x{{ '%08x' % f.mask }}u;
inline constexpr int {{ reg.full_name }}_{{ f.name }}_LSB = {{ f.lsb }};
{% endfor %}
{% endfor %}
{% endfor %}

}  // namespace tpe::regs
"""
)

PY_TEMPLATE = Template(
    """\
# {{ banner_lines[0] }}
# {{ banner_lines[1] }}
# {{ banner_lines[2] }}
\"\"\"Register addresses/masks for cocotb testbenches driving AXI4-Lite MMIO
directly (see verif/cocotb_tb/env/axi4_lite_driver.py).\"\"\"

{% for block in blocks %}
# ---------------------------------------------------------------------
# {{ block.name | upper }} block -- base 0x{{ '%04x' % block.base_address }}
# {{ block.description }}
# ---------------------------------------------------------------------
{{ block.name | upper }}_BASE_ADDR = 0x{{ '%04x' % block.base_address }}
{% for reg in block.registers %}
{{ reg.full_name }}_ADDR = 0x{{ '%04x' % reg.abs_addr }}
{{ reg.full_name }}_RESET = 0x{{ '%08x' % reg.reset }}
{% for f in reg.fields %}
{{ reg.full_name }}_{{ f.name }}_MASK = 0x{{ '%08x' % f.mask }}
{{ reg.full_name }}_{{ f.name }}_LSB = {{ f.lsb }}
{% endfor %}
{% endfor %}
{% endfor %}
"""
)

MD_TEMPLATE = Template(
    """\
<!--
{{ banner_lines[0] }}
{{ banner_lines[1] }}
{{ banner_lines[2] }}
-->
# TPE Register Map

{{ doc_description }}

Address width: {{ address_width }} bits. Data width: {{ data_width }} bits.

{% for block in blocks %}
## {{ block.name }} (base `0x{{ '%04x' % block.base_address }}`)

{{ block.description }}

| Register | Offset | Address | Access | Reset | Description |
|---|---|---|---|---|---|
{% for reg in block.registers -%}
| `{{ reg.name }}` | `0x{{ '%02x' % reg.offset }}` | `0x{{ '%04x' % reg.abs_addr }}` | {{ reg.access }} | `0x{{ '%08x' % reg.reset }}` | {{ reg.description }} |
{% endfor %}
{% for reg in block.registers %}{% if reg.fields %}
**{{ reg.name }} fields:**

| Field | Bits | Description |
|---|---|---|
{% for f in reg.fields -%}
| `{{ f.name }}` | `[{{ f.msb }}:{{ f.lsb }}]` | {{ f.description }} |
{% endfor %}
{% endif %}{% endfor %}
{% endfor %}
"""
)


def main() -> int:
    if not YAML_PATH.exists():
        print(f"error: {YAML_PATH} not found", file=sys.stderr)
        return 1

    doc, blocks = load_regmap(YAML_PATH)
    banner_lines = GENERATED_BANNER.split("\n")

    SV_OUT.parent.mkdir(parents=True, exist_ok=True)
    SV_OUT.write_text(SV_TEMPLATE.render(blocks=blocks, banner_lines=banner_lines))

    CPP_OUT.parent.mkdir(parents=True, exist_ok=True)
    CPP_OUT.write_text(CPP_TEMPLATE.render(blocks=blocks, banner_lines=banner_lines))

    PY_OUT.parent.mkdir(parents=True, exist_ok=True)
    PY_OUT.write_text(PY_TEMPLATE.render(blocks=blocks, banner_lines=banner_lines))

    MD_OUT.parent.mkdir(parents=True, exist_ok=True)
    MD_OUT.write_text(
        MD_TEMPLATE.render(
            blocks=blocks,
            banner_lines=banner_lines,
            doc_description=doc.get("description", "").strip(),
            address_width=doc["address_width"],
            data_width=doc["data_width"],
        )
    )

    total_regs = sum(len(b.registers) for b in blocks)
    print(f"regmap_gen: {len(blocks)} blocks, {total_regs} registers")
    print(f"  wrote {SV_OUT.relative_to(REPO_ROOT)}")
    print(f"  wrote {CPP_OUT.relative_to(REPO_ROOT)}")
    print(f"  wrote {PY_OUT.relative_to(REPO_ROOT)}")
    print(f"  wrote {MD_OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
