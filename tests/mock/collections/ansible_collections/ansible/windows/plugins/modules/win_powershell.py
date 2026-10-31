#!/usr/bin/python
import json, os
from datetime import datetime, timezone
from ansible.module_utils.basic import AnsibleModule
m = AnsibleModule(argument_spec=dict(script=dict(), parameters=dict(type='dict')), supports_check_mode=True)
s = m.params['script'] or ''
fx = os.environ.get('MOCK_FIXTURE', 'good')
if 'Get-SessionInfo' in s or 'AuthenticationType' in s:
    r = dict(computer_name='SQLSRV01', dns_host_name='sqlsrv01', domain='corp.example.com', part_of_domain=True,
             fqdn='sqlsrv01.corp.example.com', user='CORP\\svc_ansible', authentication_type='NTLM' if fx=='ntlm' else 'Kerberos',
             is_admin=True, ps_version='5.1.20348.2849', os_caption='Microsoft Windows Server 2022 Datacenter', os_build=20348,
             winrm_listeners=['HTTPS/5986'], utc_now=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
elif 'Invoke-SqlPrecheck' in s or 'PolicyJson' in json.dumps(m.params['parameters'] or {}):
    pol = json.loads(m.params['parameters']['PolicyJson'])
    checks = [dict(id='PC-001',name='Supported operating system',status='PASS',expected='Windows Server 2019 / 2022 / 2025',actual='Windows Server 2022 Datacenter (20348.2849)',message='')]
    if fx == 'bad':
        checks += [dict(id='PC-016',name='Drive T: present (tempdb)',status='FAIL',expected='local fixed disk',actual='missing',message='Standart gereği T: zorunlu.'),
                   dict(id='PC-012',name='Drive D: allocation unit',status='WARN',expected='64 KB',actual='4 KB',message='64 KB önerilir.')]
    r = dict(facts=dict(cpu=dict(logical_processors=8), memory_mb=32768, policy_seen=pol), checks=checks)
else:
    r = dict(ok=True, error='')
m.exit_json(changed=False, result=r, output=[], error=[])
