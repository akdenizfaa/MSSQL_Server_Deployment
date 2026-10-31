#!/usr/bin/env bash
# Windows sunucusu olmadan mantık testleri.
#  1) PowerShell precheck script'i mock Windows verisiyle (pwsh gerekir)
#  2) Ansible akışı mock ansible.windows modülleriyle (sahte WinRM listener 5986)
# Kullanım: tests/run_mock_tests.sh   (repo kökünden)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

echo "== 1) PowerShell parse + mock run =="
if command -v pwsh >/dev/null; then
  pwsh -NoProfile -File tests/powershell/Invoke-SqlPrecheck.Mock.ps1 -Script "$ROOT/roles/sql_precheck/files/Invoke-SqlPrecheck.ps1" | tail -1
else
  echo "pwsh yok, atlandı"
fi

echo "== 2) Ansible akışı (mock) =="
grep -q "sqlsrv01.corp.example.com" /etc/hosts || { echo "Gerekli: /etc/hosts içine '127.0.0.1 sqlsrv01.corp.example.com'"; exit 1; }
python3 -c "import socket,sys;s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(('127.0.0.1',5986));s.listen(50)
while True: c,_=s.accept();c.close()" &
LPID=$!; trap 'kill $LPID' EXIT
export ANSIBLE_COLLECTIONS_PATH="$ROOT/tests/mock/collections:${ANSIBLE_COLLECTIONS_PATH:-$HOME/.ansible/collections}"
# fixture | extra-vars | beklenen rc
run_case() {
  local name=$1 fx=$2 extra=$3 want=$4
  set +e
  MOCK_FIXTURE=$fx ansible-playbook -i tests/mock/inventory.yml playbooks/01_precheck.yml $extra >"/tmp/mock_${name}.log" 2>&1
  local rc=$?; set -e
  if [ "$rc" = "$want" ]; then echo "PASS  $name (rc=$rc)"; else echo "FAIL  $name (rc=$rc, beklenen $want) -> /tmp/mock_${name}.log"; FAILED=1; fi
}
FAILED=0
run_case good_2019   good "-e sql_version=2019" 0
run_case good_2022   good "-e sql_version=2022" 0
run_case good_2025   good "-e sql_version=2025" 0
run_case no_version  good ""                    2
run_case bad_version good "-e sql_version=2017" 2
run_case disk_fail   bad  "-e sql_version=2025" 2
run_case ntlm        ntlm "-e sql_version=2025" 2
exit $FAILED
