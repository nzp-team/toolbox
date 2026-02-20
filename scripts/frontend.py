from __future__ import annotations

import asyncio
import os
import re
import shlex
import signal
from dataclasses import dataclass

from pathlib import Path
from typing import Dict, List, Optional

from textual import work
from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.reactive import reactive
from textual.widgets import (
    Button,
    Footer,
    Header,
    Input,
    Label,
    ListItem,
    ListView,
    RichLog,
    Static,
)

MAPS_ROOT_DEFAULT = "/workspace/repos/assets/source/maps"
SCRIPTS_ROOT_DEFAULT = "/opt/scripts"

SCRIPT_EXTS = {".sh", ""}

META_NAME_RE = re.compile(r"^\s*#\s*@name\s+(?P<val>.+?)\s*$", re.IGNORECASE)
META_DESC_RE = re.compile(r"^\s*#\s*@desc\s+(?P<val>.+?)\s*$", re.IGNORECASE)
META_USAGE_RE = re.compile(r"^\s*#\s*@usage\s+(?P<val>.+?)\s*$", re.IGNORECASE)
META_TITLE_RE = re.compile(r"^\s*#\s*@button\s+(?P<val>.+?)\s*$", re.IGNORECASE)


@dataclass(frozen=True)
class Action:
    name: str
    title: str = ""
    desc: str = ""
    usage: str = ""
    path: Optional[Path] = None

    @property
    def tooltip(self) -> str:
        parts: List[str] = []
        if self.desc:
            parts.append(self.desc)
        if self.usage:
            parts.append(self.usage)
        if self.path:
            parts.append(f"Script: {self.path}")
        return "\n".join(parts) if parts else self.name

def escape_rich_markup(text: str) -> str:
    text = text.replace("\\", "\\\\")
    text = text.replace("[", "\\[")
    return text


def find_map_files(maps_root: Path) -> List[Path]:
    results: List[Path] = []
    if not maps_root.exists():
        return results

    for p in maps_root.rglob("*.map"):
        try:
            rel = p.relative_to(maps_root)
        except ValueError:
            continue

        if len(rel.parts) >= 2:
            results.append(p)

    results.sort(key=lambda x: str(x).lower())
    return results


def parse_action_metadata(path: Path) -> Optional[Action]:
    try:
        lines = path.read_text(errors="replace").splitlines()
    except Exception:
        return None

    title = ""
    name = ""
    desc = ""
    usage = ""

    for line in lines[:80]:
        m = META_NAME_RE.match(line)
        if m:
            name = m.group("val").strip()
            continue

        m = META_DESC_RE.match(line)
        if m and not desc:
            desc = m.group("val").strip()
            continue

        m = META_USAGE_RE.match(line)
        if m and not usage:
            usage = m.group("val").strip()
            continue

        m = META_TITLE_RE.match(line)
        if m and not title:
            title = m.group("val").strip()
            continue

    if not name:
        name = path.stem

    return Action(name=name, desc=desc, usage=usage, title=title, path=path)


def load_actions(scripts_root: Path) -> List[Action]:
    actions: List[Action] = []
    if not scripts_root.exists():
        return actions

    for p in sorted(scripts_root.iterdir(), key=lambda x: str(x).lower()):
        if p.is_dir():
            continue

        if p.suffix not in SCRIPT_EXTS:
            continue

        is_exec = os.access(str(p), os.X_OK)
        is_script = p.suffix in {".sh", ".py"}
        if not (is_exec or is_script):
            continue

        action = parse_action_metadata(p)
        if action:
            actions.append(action)

    uniq: Dict[str, Action] = {}
    for a in actions:
        uniq[a.name] = a

    return sorted(uniq.values(), key=lambda a: a.name.lower())


def map_base_name(map_path: Path) -> str:
    return map_path.stem



class MapItem(ListItem):
    def __init__(self, path: Path):
        super().__init__(Label(str(path)))
        self.path = path



class ActionItem(ListItem):
    DEFAULT_CSS = """
    ActionItem {
        padding: 0 1; 
        margin-bottom: 1;
        background: $surface;
        border: tall $surface-lighten-2; 
        color: $text-muted;
        height: auto;
        min-height: 1;
        align: center middle; 
    }

    ActionItem > Label {
        width: 100%; /* Force full width */
        text-align: center;
    }

    ActionItem:hover {
        background: $surface-lighten-1;
        color: $text;
    }

    ActionItem.-highlighted {
        background: $success !important; 
        color: white !important; 
        text-style: bold;
        border: heavy $background !important;
    }

    ActionItem.-highlighted > Label {
        color: white !important;
        text-style: bold;
    }
    """

    def __init__(self, title: str):
        super().__init__(Label(title))
        self.action_name: Optional[str] = None


class ToolboxTUI(App):
    TITLE = "NZ:P Toolbox TUI"
    CSS = """
    Screen {
        layout: vertical;
        background: $surface-darken-1;
    }

    .top {
        height: 60%; 
        min-height: 10;
        margin: 1;
    }

    .bottom {
        height: 40%;
        min-height: 5;
        margin: 0 1 1 1;
    }

    #maps_panel, #actions_panel {
        background: $surface;
        border: heavy $primary;
        padding: 1;
        width: 1fr;
        margin-right: 1;
    }
    #actions_panel {
        margin-right: 0;
        margin-left: 1;
    }

    #output_panel {
        background: $surface;
        border: heavy $secondary;
        padding: 1;
    }

    #output_status {
        height: 1;
        overflow: hidden;
        background: $surface-lighten-1;
        color: $text;
    }

    #maps_title, #actions_title, #output_title {
        text-style: bold;
        background: $primary-darken-2;
        color: $text;
        padding: 0 1;
        margin-bottom: 1;
        text-align: center;
    }

    #maps_list {
        height: 1fr;
        border: solid $primary-darken-3;
    }

    #actions_list {
        height: 1fr;
        border: solid $primary-darken-3;
        overflow-y: auto;
        padding: 1 2 1 1; 
    }

    #args_row {
        height: auto;
        margin-top: 1;
        align: center middle;
    }

    #args_input {
        width: 1fr;
        border: heavy $accent;
    }

    #run_row {
        height: auto;
        margin-top: 1;
        align: center middle;
    }

    #run_button, #stop_button {
        width: 1fr;
        margin: 0 1;
    }
    """

    BINDINGS = [
        ("q", "quit", "Quit"),
        ("r", "run_selected", "Run"),
        ("f5", "refresh", "Refresh"),
    ]

    selected_map: reactive[Optional[Path]] = reactive(None)
    selected_action: reactive[Optional[str]] = reactive(None)

    def __init__(self):
        super().__init__()
        self.maps_root = Path(os.environ.get("MAPS_ROOT", MAPS_ROOT_DEFAULT))
        self.scripts_root = Path(os.environ.get("SCRIPTS_ROOT", SCRIPTS_ROOT_DEFAULT))
        self._actions: List[Action] = []
        self._action_by_name: Dict[str, Action] = {}
        self._proc: Optional[asyncio.subprocess.Process] = None

    def compose(self) -> ComposeResult:
        yield Header()

        with Horizontal(classes="top"):
            with Vertical(id="maps_panel"):
                yield Static("Map Sources", id="maps_title")
                yield ListView(id="maps_list")

            with Vertical(id="actions_panel"):
                yield Static("Actions", id="actions_title")
                yield ListView(id="actions_list")

                with Horizontal(id="args_row"):
                    yield Label("Arguments:", id="args_label")
                    yield Input(
                        placeholder="Extra args, e.g. --full --verbose",
                        id="args_input",
                    )

                with Horizontal(id="run_row"):
                    yield Button("Run", id="run_button", variant="success")
                    yield Button("Stop", id="stop_button", variant="error")

        with Vertical(id="output_panel", classes="bottom"):
            yield Static("Output", id="output_title")
            yield Static("", id="output_status")
            yield RichLog(id="output_log", wrap=True, highlight=True, markup=True)

        yield Footer()

    async def on_mount(self) -> None:
        await self.refresh_all()
        self.query_one("#stop_button", Button).disabled = True

    async def action_refresh(self) -> None:
        await self.refresh_all()

    async def refresh_all(self) -> None:
        await self.refresh_maps()
        await self.refresh_actions()

    async def refresh_maps(self) -> None:
        maps_list = self.query_one("#maps_list", ListView)
        maps_list.clear()

        maps = find_map_files(self.maps_root)
        if not maps:
            maps_list.append(ListItem(Label(f"[missing] No .map files found under {self.maps_root}")))
            self.selected_map = None
            return

        for p in maps:
            maps_list.append(MapItem(map_base_name(p)))

        maps_list.focus()
        if maps_list.children:
            maps_list.index = 0
            first_item = maps_list.children[0]
            if isinstance(first_item, MapItem):
                self.selected_map = first_item.path

    async def refresh_actions(self) -> None:
        actions_list = self.query_one("#actions_list", ListView)
        actions_list.clear()

        self._actions = load_actions(self.scripts_root)
        self._action_by_name = {a.name: a for a in self._actions}

        if not self._actions:
            actions_list.append(ListItem(Label(f"[missing] No actions found under {self.scripts_root}")))
            self.selected_action = None
            return

        for a in self._actions:
            item = ActionItem(a.title)
            item.tooltip = a.tooltip
            item.action_name = a.name
            actions_list.append(item)

        actions_list.focus()
        actions_list.index = 0
        self.selected_action = self._actions[0].name

    async def on_list_view_selected(self, event: ListView.Selected) -> None:
        if event.list_view.id == "maps_list":
            item = event.item
            if isinstance(item, MapItem):
                self.selected_map = item.path

        elif event.list_view.id == "actions_list":
            item = event.item
            if isinstance(item, ActionItem):
                self.selected_action = getattr(item, "action_name", None)

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "run_button":
            self.run_selected()
        elif event.button.id == "stop_button":
            await self.stop_running()

    async def action_run_selected(self) -> None:
        self.run_selected()

    @work(exclusive=True)
    async def run_selected(self) -> None:
        log = self.query_one("#output_log", RichLog)
        args_input = self.query_one("#args_input", Input)

        if self._proc is not None:
            log.write("[yellow]A process is already running. Stop it first.[/yellow]")
            return

        if not self.selected_map:
            log.write("[red]No map selected.[/red]")
            return

        if not self.selected_action:
            log.write("[red]No action selected.[/red]")
            return

        action = self._action_by_name.get(self.selected_action)
        if not action:
            log.write(f"[red]Unknown action: {self.selected_action}[/red]")
            return

        map_name = self.selected_map
        extra_args = args_input.value.strip()

        cmd = ["bash", f"/opt/scripts/{action.name}.sh"]
        if "build-map" in action.name:
            cmd.extend(["--map", map_name])
        if extra_args:
            cmd.extend(shlex.split(extra_args))

        log.write(f"[bold]$ {shlex.join(cmd)}[/bold]")
        log.write(f"[dim]maps_root={self.maps_root} scripts_root={self.scripts_root}[/dim]")
        log.scroll_end(animate=False)

        self._proc = await asyncio.create_subprocess_exec(
            *cmd,
            cwd=str(self.maps_root),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            env=os.environ.copy(),
            start_new_session=True,
        )

        self.query_one("#run_button", Button).disabled = True
        self.query_one("#stop_button", Button).disabled = False

        try:
            assert self._proc.stdout is not None
            status = self.query_one("#output_status", Static)

            buf = ""
            MAX_BUF = 20000

            while True:
                chunk = await self._proc.stdout.read(4096)
                if not chunk:
                    break

                s = chunk.decode(errors="replace")
                for ch in s:
                    if ch == "\r":
                        status.update(buf[-500:])
                        buf = ""
                    elif ch == "\n":
                        line = buf.rstrip()
                        if line:
                            log.write(escape_rich_markup(line))
                            log.scroll_end(animate=False)
                        buf = ""
                        status.update("")
                    else:
                        buf += ch
                        if len(buf) > MAX_BUF:
                            status.update(buf[-500:])
                            buf = buf[-1000:]

            tail = buf.strip()
            if tail:
                log.write(escape_rich_markup(tail))
                log.scroll_end(animate=False)
            status.update("")
            rc = await self._proc.wait()
            if rc == 0:
                log.write("[green]✔ Done[/green]")
            else:
                log.write(f"[red]✘ Exit code: {rc}[/red]")
            log.scroll_end(animate=False)

        except Exception as e:
            log.write(f"[red]Error: {escape_rich_markup(str(e))}[/red]")
            log.scroll_end(animate=False)

        finally:
            self._proc = None
            self.query_one("#run_button", Button).disabled = False
            self.query_one("#stop_button", Button).disabled = True
            await self.refresh_maps()

    async def stop_running(self) -> None:
        log = self.query_one("#output_log", RichLog)
        if self._proc is None:
            return

        self._stop_requested = True

        pid = self._proc.pid
        if pid is None:
            return

        log.write("[yellow]Stopping...[/yellow]")
        log.scroll_end(animate=False)

        try:
            os.killpg(pid, signal.SIGINT)
        except ProcessLookupError:
            return

        try:
            await asyncio.wait_for(self._proc.wait(), timeout=2.0)
            return
        except asyncio.TimeoutError:
            pass

        try:
            os.killpg(pid, signal.SIGTERM)
        except ProcessLookupError:
            return

        try:
            await asyncio.wait_for(self._proc.wait(), timeout=2.0)
            return
        except asyncio.TimeoutError:
            pass

        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            return



if __name__ == "__main__":
    ToolboxTUI().run()
