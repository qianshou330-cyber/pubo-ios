"""Read-only process samples. Reports simulator RSS/CPU, not physical-device FPS."""
import json, subprocess, threading, time


class SimulatorResources:
    def __init__(self, output):
        self.output = output
        self.samples = []
        self.stop = threading.Event()
        self.worker = threading.Thread(target=self._sample, daemon=True)

    def __enter__(self):
        self.worker.start()
        return self

    def _sample(self):
        started = time.monotonic()
        while not self.stop.is_set():
            try:
                lines = subprocess.check_output(['ps', '-axo', 'pid=,rss=,%cpu=,command='], text=True, timeout=5)
                for line in lines.splitlines():
                    values = line.strip().split(None, 3)
                    if len(values) == 4 and values[3].split()[0].endswith('/PUBO.app/PUBO'):
                        self.samples.append({'seconds': round(time.monotonic()-started,2), 'rssMiB': round(int(values[1])/1024,2), 'cpuPercent': float(values[2])})
            except (subprocess.SubprocessError, ValueError):
                pass
            self.stop.wait(1)

    def __exit__(self, *args):
        self.stop.set()
        self.worker.join(timeout=6)
        self.output.write_text(json.dumps({'scope': 'iOS Simulator process, all interactions in this group; not device FPS', 'peakRSSMiB': max((s['rssMiB'] for s in self.samples),default=None), 'samples': self.samples},indent=2))
