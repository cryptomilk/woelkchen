#!py
#
# woelkchen
#
# Copyright (C) 2025   darix
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

import os
import yaml


def run():
    config = {}

    opencloud_pillar = __salt__['pillar.get']('opencloud', {})

    is_enabled = opencloud_pillar.get('enabled', True)
    env_vars = opencloud_pillar.get('env', {})
    csp_config = opencloud_pillar.get('csp', None)

    env_file_path = '/etc/default/opencloud-server'
    csp_path = csp_config.get('path', '/etc/opencloud-server/csp.yaml') if csp_config else None

    if is_enabled:
        config['opencloud_packages'] = {
            'pkg.installed': [
                {'pkgs': ['opencloud-server']},
            ]
        }

        run_init = opencloud_pillar.get('run_init', True)
        if run_init:
            init_insecure = opencloud_pillar.get('init_insecure', False)
            admin_password = opencloud_pillar.get('admin_password', '')
            init_cmd = "opencloud init --config-path /etc/opencloud --insecure {}".format(
                'true' if init_insecure else 'false'
            )
            if admin_password:
                init_cmd += " --admin-password '{}'".format(admin_password)

            config['opencloud_init'] = {
                'cmd.run': [
                    {'name': init_cmd},
                    {'creates': '/etc/opencloud/opencloud.yaml'},
                    {'require': ['opencloud_packages']},
                    {'require_in': ['opencloud_env_file']},
                ]
            }

        env_contents = '\n'.join('{}={}'.format(k, v) for k, v in sorted(env_vars.items()))
        if env_contents:
            env_contents += '\n'

        config['opencloud_env_file'] = {
            'file.managed': [
                {'name': env_file_path},
                {'user': 'root'},
                {'group': 'root'},
                {'mode': '0640'},
                {'contents': env_contents},
                {'require': ['opencloud_packages']},
            ]
        }

        service_require = ['opencloud_env_file']
        service_watch = ['opencloud_env_file']

        if csp_config:
            csp_dir = os.path.dirname(csp_path)

            config['opencloud_csp_dir'] = {
                'file.directory': [
                    {'name': csp_dir},
                    {'user': 'root'},
                    {'group': 'opencloud-server'},
                    {'mode': '0770'},
                    {'require': ['opencloud_packages']},
                ]
            }

            config['opencloud_csp_config'] = {
                'file.managed': [
                    {'name': csp_path},
                    {'user': 'root'},
                    {'group': 'opencloud-server'},
                    {'mode': '0640'},
                    {'contents': yaml.dump(csp_config.get('config', {}))},
                    {'require': ['opencloud_csp_dir']},
                ]
            }

            service_require.append('opencloud_csp_config')
            service_watch.append('opencloud_csp_config')

        config['opencloud_service'] = {
            'service.running': [
                {'name': 'opencloud-server.service'},
                {'enable': True},
                {'require': service_require},
                {'watch': service_watch},
            ]
        }

    else:
        config['opencloud_service'] = {
            'service.dead': [
                {'name': 'opencloud-server.service'},
                {'enable': False},
                {'require_in': ['opencloud_env_file']},
            ]
        }

        config['opencloud_env_file'] = {
            'file.absent': [
                {'name': env_file_path},
                {'require_in': ['opencloud_packages']},
            ]
        }

        if csp_config:
            config['opencloud_csp_config'] = {
                'file.absent': [
                    {'name': csp_path},
                    {'require': ['opencloud_service']},
                    {'require_in': ['opencloud_packages']},
                ]
            }

        config['opencloud_packages'] = {
            'pkg.purged': [
                {'pkgs': ['opencloud-server']},
            ]
        }

    return config
