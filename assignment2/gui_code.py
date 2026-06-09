import re
import queue
import threading
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from dataclasses import dataclass
from typing import List, Optional, Dict

from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure


LOG_PATTERN = re.compile(
    r"time\s+(?P<time>[^,]+),\s*node\s+(?P<node>\d+),\s*seq\s+(?P<seq>\d+),\s*"
    r"temperature_raw\s+(?P<temp_raw>\d+),\s*temperature\s+(?P<temp_c>-?\d+(?:\.\d+)?)C,\s*"
    r"humidity_raw\s+(?P<hum_raw>\d+),\s*humidity\s+(?P<hum_pct>-?\d+(?:\.\d+)?)%,\s*"
    r"battery_raw\s+(?P<batt_raw>\d+),\s*battery\s+(?P<batt_v>-?\d+(?:\.\d+)?)V"
)


@dataclass
class LogEntry:
    time_text: str
    node: int
    seq: int
    temp_raw: int
    temp_c: float
    hum_raw: int
    hum_pct: float
    batt_raw: int
    batt_v: float
    original_line: str

    @property
    def raw_summary(self) -> str:
        return (
            f"time {self.time_text}, node {self.node}, seq {self.seq}, "
            f"temperature_raw {self.temp_raw}, humidity_raw {self.hum_raw}, "
            f"battery_raw {self.batt_raw}"
        )

    @property
    def converted_summary(self) -> str:
        return (
            f"time {self.time_text}, node {self.node}, seq {self.seq}, "
            f"temperature {self.temp_c:.1f}C, humidity {self.hum_pct:.1f}%, "
            f"battery {self.batt_v:.2f}V"
        )

    @property
    def full_summary(self) -> str:
        return (
            f"time {self.time_text}, node {self.node}, seq {self.seq}, "
            f"temperature_raw {self.temp_raw}, temperature {self.temp_c:.1f}C, "
            f"humidity_raw {self.hum_raw}, humidity {self.hum_pct:.1f}%, "
            f"battery_raw {self.batt_raw}, battery {self.batt_v:.2f}V"
        )


def parse_line(line: str) -> Optional[LogEntry]:
    match = LOG_PATTERN.search(line.strip())
    if not match:
        return None
    return LogEntry(
        time_text=match.group("time"),
        node=int(match.group("node")),
        seq=int(match.group("seq")),
        temp_raw=int(match.group("temp_raw")),
        temp_c=float(match.group("temp_c")),
        hum_raw=int(match.group("hum_raw")),
        hum_pct=float(match.group("hum_pct")),
        batt_raw=int(match.group("batt_raw")),
        batt_v=float(match.group("batt_v")),
        original_line=line.rstrip(),
    )


class SimpleWSNMonitor:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Simple WSN Monitor")
        self.root.geometry("1400x900")

        self.entries: List[LogEntry] = []
        self.proc: Optional[subprocess.Popen] = None
        self.proc_thread: Optional[threading.Thread] = None
        self.output_queue: queue.Queue[str] = queue.Queue()

        self.mode_var = tk.StringVar(value="raw")
        self.graph_metric_var = tk.StringVar(value="temperature")
        self.graph_node_var = tk.StringVar(value="all")
        self.command_var = tk.StringVar(
            value=(
                "java -classpath "
                "/home/nsl/tinyos-main/apps/assignment2:"
                "/home/nsl/tinyos-main/tools/tinyos/java/tinyos.jar "
                "SimpleWSNListener -comm serial@/dev/ttyUSB0:telosb"
            )
        )
        self._build_ui()
        self._schedule_queue_poll()

    def _build_ui(self):
        top = ttk.Frame(self.root, padding=10)
        top.pack(fill=tk.X)

        ttk.Label(top, text="Mode:").pack(side=tk.LEFT, padx=(0, 6))
        ttk.Radiobutton(top, text="Raw data mode", value="raw", variable=self.mode_var,
                        command=self.refresh_views).pack(side=tk.LEFT)
        ttk.Radiobutton(top, text="Converted data mode", value="converted", variable=self.mode_var,
                        command=self.refresh_views).pack(side=tk.LEFT, padx=(8, 0))

        ttk.Separator(top, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=12)
        ttk.Label(top, text="Java command:").pack(side=tk.LEFT, padx=(0, 6))
        self.command_entry = ttk.Entry(top, textvariable=self.command_var, width=80)
        self.command_entry.pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(top, text="Start", command=self.start_java_listener).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="Stop", command=self.stop_java_listener).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="Load Log File", command=self.load_log_file).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="Clear", command=self.clear_all).pack(side=tk.LEFT, padx=4)

        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 10))

        self.dashboard_tab = ttk.Frame(self.notebook, padding=10)
        self.printf_tab = ttk.Frame(self.notebook, padding=10)
        self.graph_tab = ttk.Frame(self.notebook, padding=10)

        self.notebook.add(self.dashboard_tab, text="Dashboard")
        self.notebook.add(self.printf_tab, text="Printf View")
        self.notebook.add(self.graph_tab, text="Graphs")

        self._build_dashboard_tab()
        self._build_printf_tab()
        self._build_graph_tab()

    def _build_dashboard_tab(self):
        upper = ttk.Frame(self.dashboard_tab)
        upper.pack(fill=tk.X)

        self.node_cards: Dict[int, Dict[str, ttk.Label]] = {}
        for node in (2, 3, 4):
            card = ttk.LabelFrame(upper, text=f"Node {node}", padding=10)
            card.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5)

            labels = {}
            for key in ["time", "seq", "temp", "hum", "batt"]:
                row = ttk.Frame(card)
                row.pack(fill=tk.X, pady=2)
                ttk.Label(row, text=f"{key.upper()}:", width=8).pack(side=tk.LEFT)
                labels[key] = ttk.Label(row, text="-")
                labels[key].pack(side=tk.LEFT)
            self.node_cards[node] = labels

        lower = ttk.Frame(self.dashboard_tab)
        lower.pack(fill=tk.BOTH, expand=True, pady=(10, 0))

        columns = (
            "time", "node", "seq", "temp_raw", "temp_c", "hum_raw", "hum_pct", "batt_raw", "batt_v"
        )
        self.table = ttk.Treeview(lower, columns=columns, show="headings", height=22)
        headings = {
            "time": "Time",
            "node": "Node",
            "seq": "Seq",
            "temp_raw": "Temp Raw",
            "temp_c": "Temp C",
            "hum_raw": "Hum Raw",
            "hum_pct": "Hum %",
            "batt_raw": "Batt Raw",
            "batt_v": "Batt V",
        }
        widths = {
            "time": 100,
            "node": 60,
            "seq": 80,
            "temp_raw": 100,
            "temp_c": 100,
            "hum_raw": 100,
            "hum_pct": 100,
            "batt_raw": 100,
            "batt_v": 100,
        }
        for col in columns:
            self.table.heading(col, text=headings[col])
            self.table.column(col, width=widths[col], anchor=tk.CENTER)

        yscroll = ttk.Scrollbar(lower, orient=tk.VERTICAL, command=self.table.yview)
        self.table.configure(yscrollcommand=yscroll.set)
        self.table.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        yscroll.pack(side=tk.RIGHT, fill=tk.Y)

    def _build_printf_tab(self):
        top = ttk.Frame(self.printf_tab)
        top.pack(fill=tk.X, pady=(0, 8))
        ttk.Label(top, text="출력 페이지: 모드에 따라 raw / converted 형식으로 표시됩니다.").pack(side=tk.LEFT)

        frame = ttk.Frame(self.printf_tab)
        frame.pack(fill=tk.BOTH, expand=True)

        self.printf_text = tk.Text(frame, wrap=tk.NONE, font=("Courier New", 11))
        yscroll = ttk.Scrollbar(frame, orient=tk.VERTICAL, command=self.printf_text.yview)
        xscroll = ttk.Scrollbar(frame, orient=tk.HORIZONTAL, command=self.printf_text.xview)
        self.printf_text.configure(yscrollcommand=yscroll.set, xscrollcommand=xscroll.set)

        self.printf_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        yscroll.pack(side=tk.RIGHT, fill=tk.Y)
        xscroll.pack(side=tk.BOTTOM, fill=tk.X)

    def _build_graph_tab(self):
        controls = ttk.Frame(self.graph_tab)
        controls.pack(fill=tk.X, pady=(0, 8))

        ttk.Label(controls, text="Node:").pack(side=tk.LEFT)
        node_combo = ttk.Combobox(
            controls,
            textvariable=self.graph_node_var,
            values=["all", "2", "3", "4"],
            width=8,
            state="readonly",
        )
        node_combo.pack(side=tk.LEFT, padx=(6, 12))
        node_combo.bind("<<ComboboxSelected>>", lambda e: self.refresh_graph())

        ttk.Label(controls, text="Metric:").pack(side=tk.LEFT)
        metric_combo = ttk.Combobox(
            controls,
            textvariable=self.graph_metric_var,
            values=["temperature", "humidity", "battery"],
            width=14,
            state="readonly",
        )
        metric_combo.pack(side=tk.LEFT, padx=(6, 12))
        metric_combo.bind("<<ComboboxSelected>>", lambda e: self.refresh_graph())

        ttk.Button(controls, text="Refresh Graph", command=self.refresh_graph).pack(side=tk.LEFT)

        self.figure = Figure(figsize=(9, 5), dpi=100)
        self.ax = self.figure.add_subplot(111)
        self.canvas = FigureCanvasTkAgg(self.figure, master=self.graph_tab)
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)

    def load_log_file(self):
        path = filedialog.askopenfilename(
            title="Open log file",
            filetypes=[("Text files", "*.txt *.log"), ("All files", "*.*")],
        )
        if not path:
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    self._consume_line(line)
            self.refresh_views()
        except Exception as e:
            messagebox.showerror("Load error", str(e))

    def start_java_listener(self):
        if self.proc is not None:
            messagebox.showinfo("Info", "Listener is already running.")
            return
        try:
            self.proc = subprocess.Popen(
                self.command_var.get(),
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True,
            )
        except Exception as e:
            messagebox.showerror("Start error", str(e))
            self.proc = None
            return

        self.proc_thread = threading.Thread(target=self._reader_thread, daemon=True)
        self.proc_thread.start()

    def stop_java_listener(self):
        if self.proc is not None:
            self.proc.terminate()
            self.proc = None

    def clear_all(self):
        self.entries.clear()
        self.printf_text.delete("1.0", tk.END)
        for item in self.table.get_children():
            self.table.delete(item)
        self.refresh_views()
        self.ax.clear()
        self.canvas.draw_idle()

    def _reader_thread(self):
        assert self.proc is not None
        for line in self.proc.stdout:
            self.output_queue.put(line)
        self.output_queue.put("__PROCESS_ENDED__")

    def _schedule_queue_poll(self):
        self._poll_queue()
        self.root.after(200, self._schedule_queue_poll)

    def _poll_queue(self):
        updated = False
        while True:
            try:
                line = self.output_queue.get_nowait()
            except queue.Empty:
                break
            if line == "__PROCESS_ENDED__":
                self.proc = None
                continue
            self._consume_line(line)
            updated = True
        if updated:
            self.refresh_views()

    def _consume_line(self, line: str):
        entry = parse_line(line)
        if entry is None:
            return
        self.entries.append(entry)

    def refresh_views(self):
        self.refresh_cards()
        self.refresh_table()
        self.refresh_printf_page()
        self.refresh_graph()

    def refresh_cards(self):
        for node in (2, 3, 4):
            latest = self._latest_for_node(node)
            labels = self.node_cards[node]
            if latest is None:
                for key in labels:
                    labels[key].config(text="-")
                continue
            labels["time"].config(text=latest.time_text)
            labels["seq"].config(text=str(latest.seq))
            if self.mode_var.get() == "raw":
                labels["temp"].config(text=str(latest.temp_raw))
                labels["hum"].config(text=str(latest.hum_raw))
                labels["batt"].config(text=str(latest.batt_raw))
            else:
                labels["temp"].config(text=f"{latest.temp_c:.1f} C")
                labels["hum"].config(text=f"{latest.hum_pct:.1f} %")
                labels["batt"].config(text=f"{latest.batt_v:.2f} V")

    def refresh_table(self):
        for item in self.table.get_children():
            self.table.delete(item)
        for entry in self.entries[-300:]:
            self.table.insert(
                "",
                tk.END,
                values=(
                    entry.time_text,
                    entry.node,
                    entry.seq,
                    entry.temp_raw,
                    f"{entry.temp_c:.1f}",
                    entry.hum_raw,
                    f"{entry.hum_pct:.1f}",
                    entry.batt_raw,
                    f"{entry.batt_v:.2f}",
                ),
            )

    def refresh_printf_page(self):
        self.printf_text.delete("1.0", tk.END)
        for entry in self.entries:
            if self.mode_var.get() == "raw":
                text = entry.raw_summary
            else:
                text = entry.converted_summary
            self.printf_text.insert(tk.END, text + "\n")

    def refresh_graph(self):
        self.ax.clear()
        if not self.entries:
            self.ax.set_title("No data")
            self.canvas.draw_idle()
            return

        selected_node = self.graph_node_var.get()
        metric = self.graph_metric_var.get()
        mode = self.mode_var.get()

        nodes = [2, 3, 4] if selected_node == "all" else [int(selected_node)]
        labels = {2: "Node 2", 3: "Node 3", 4: "Node 4"}

        for node in nodes:
            node_entries = [e for e in self.entries if e.node == node]
            if not node_entries:
                continue
            x = [e.seq for e in node_entries]
            if metric == "temperature":
                y = [e.temp_raw for e in node_entries] if mode == "raw" else [e.temp_c for e in node_entries]
                ylabel = "Temperature Raw" if mode == "raw" else "Temperature (C)"
            elif metric == "humidity":
                y = [e.hum_raw for e in node_entries] if mode == "raw" else [e.hum_pct for e in node_entries]
                ylabel = "Humidity Raw" if mode == "raw" else "Humidity (%)"
            else:
                y = [e.batt_raw for e in node_entries] if mode == "raw" else [e.batt_v for e in node_entries]
                ylabel = "Battery Raw" if mode == "raw" else "Battery (V)"
            self.ax.plot(x, y, marker="o", label=labels[node])

        self.ax.set_title(f"{metric.capitalize()} Graph")
        self.ax.set_xlabel("Sequence Number")
        self.ax.set_ylabel(ylabel)
        self.ax.grid(True)
        if len(nodes) > 1:
            self.ax.legend()
        self.canvas.draw_idle()

    def _latest_for_node(self, node: int) -> Optional[LogEntry]:
        for entry in reversed(self.entries):
            if entry.node == node:
                return entry
        return None


if __name__ == "__main__":
    root = tk.Tk()
    app = SimpleWSNMonitor(root)
    root.mainloop()
