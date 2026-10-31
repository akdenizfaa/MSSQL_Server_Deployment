#!/usr/bin/python
from ansible.module_utils.basic import AnsibleModule
import os
m = AnsibleModule(argument_spec=dict(data=dict(default='pong')))
m.exit_json(ping='pong')
