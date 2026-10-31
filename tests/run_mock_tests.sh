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
  pwsh -NoProfile -File tests/powershell/Invoke-SqlPrecheck.Mock.ps1 -Script "$ROOT/roles/sql_precheck/files/Invoke-SqlPrecheck.ps1"
else
  echo "pwsh yok, atlandı"
fi

echo "== 2) Ansible akışı (mock) =="
grep -q "sqlsrv01.corp.example.com" /etc/hosts || { echo "Gerekli: /etc/hosts içine '127.0.0.1 sqlsrv01.corp.example.com'"; exit 1; }
python3 -c "import socket,sys;s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(('127.0.0.1',5986));s.listen(50)
while True: c,_=s.accept();c.close()" &
LPID=$!; trap 'kill $LPID' EXIT
export ANSIBLE_COLLECTIONS_PATH="$ROOT/tests/mock/collections:${ANSIBLE_COLLECTIONS_PATH:-$HOME/.ansible/collections}"
for fx in good bad ntlm; do
  set +e
  MOCK_FIXTURE=$fx ansible-playbook -i tests/mock/inventory.yml playbooks/01_precheck.yml >/tmp/mock_$fx.log 2>&1
  rc=$?; set -e
  echo "fixture=$fx rc=$rc  (beklenen: good=0, bad=2, ntlm=2)"
done
