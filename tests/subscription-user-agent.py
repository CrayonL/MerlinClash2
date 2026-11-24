import os
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / "merlinclash" / "scripts"
PATH = "/subscribe?token=fixture"
AGENT = "clash.meta/1.19.3"
YAML = b"mixed-port: 7890\nproxies: []\n"


class SubscriptionServer(BaseHTTPRequestHandler):
    def do_GET(self):
        agents = self.headers.get_all("User-Agent") or []
        self.server.requests.append((self.path, agents))
        body = YAML if agents == [self.server.expected] else b"bm9kZXM="
        if self.server.retry and len(self.server.requests) == 1:
            body = b""
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class DownloadTest(unittest.TestCase):
    def setUp(self):
        self.server = HTTPServer(("127.0.0.1", 0), SubscriptionServer)
        self.server.requests = []
        self.server.retry = False
        self.server.expected = AGENT
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        scripts = self.tmp / "scripts"
        scripts.mkdir()
        for name in ("clash_download", "clash_online_yaml", "clash_config_name"):
            source = (SCRIPTS / f"{name}.sh").read_text(encoding="utf-8")
            source = source.replace("/koolshare", tmp.name).replace("/tmp/upload", tmp.name)
            (scripts / f"{name}.sh").write_text(source, encoding="utf-8")
        (scripts / "clash_base.sh").write_text(
            'LOG_FILE="$TEST_DIR/log"\nclash_agent="$TEST_CORE"\nMC2_agent=fixture\n'
            'echo_date() { echo "$@"; }\nhttp_response() { :; }\n'
            'get() { echo sample; }\ndecode_url_link() { echo "$TEST_URL"; }\n'
        )
        # 在完成下载后结束导入校验，避免创建定时任务。
        (scripts / "clash_checkyaml.sh").write_text("exit 0\n")
        self.url = f"http://127.0.0.1:{self.server.server_port}{PATH}"
        self.env = dict(os.environ, TEST_DIR=tmp.name, TEST_URL=self.url, TEST_CORE="Meta/v1.19.3",
                        NO_PROXY="127.0.0.1", no_proxy="127.0.0.1")

    def subscribe(self, mode):
        args = ["request", "2"] if mode == "manual" else ["sample", "1", self.url]
        subprocess.run(["sh", self.tmp / "scripts/clash_online_yaml.sh", *args],
                       env=self.env, cwd=self.tmp, capture_output=True, check=True, timeout=10)
        self.assertEqual(self.server.requests, [(PATH, [self.server.expected])] * (2 if self.server.retry else 1))
        self.assertEqual((self.tmp / "sample.yaml").read_bytes(), YAML)

    def test_manual_and_curl_retry(self):
        self.server.retry = True
        self.subscribe("manual")

    def test_scheduled_wget_fallback(self):
        curl = self.tmp / "curl"
        curl.write_text("#!/bin/sh\nexit 1\n")
        curl.chmod(0o755)
        self.env["PATH"] = str(self.tmp) + os.pathsep + self.env["PATH"]
        self.subscribe("scheduled")

    def test_missing_core_version(self):
        self.env["TEST_CORE"] = ""
        self.server.expected = "clash.meta"
        self.subscribe("manual")

    def test_software_download_keeps_native_curl_agent(self):
        command = '. "$TEST_DIR/scripts/clash_download.sh"; echo_date() { :; }; download_by_mc2 "$TEST_URL" "$TEST_DIR/update"'
        subprocess.run(["sh", "-c", command], env=self.env, capture_output=True, check=True, timeout=10)
        self.assertEqual(len(self.server.requests), 1)
        path, agents = self.server.requests[0]
        self.assertEqual(path, PATH)
        self.assertEqual(len(agents), 1)
        self.assertTrue(agents[0].startswith("curl/"))


if __name__ == "__main__":
    unittest.main()
