#!py
#
# woelkchen
#
# Copyright (C) 2025   darix
# Copyright (C) 2026   Andreas Schneider
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

KNOWN_TYPES = {
    'pdf': {
        'mime_type': 'application/pdf',
        'name': 'PDF',
        'description': 'PDF document',
        'allow_creation': False,
        'collaboration': False,
    },
    'odt': {
        'mime_type': 'application/vnd.oasis.opendocument.text',
        'name': 'OpenDocument',
        'description': 'OpenDocument Text Document',
        'allow_creation': True,
        'collaboration': True,
    },
    'ods': {
        'mime_type': 'application/vnd.oasis.opendocument.spreadsheet',
        'name': 'OpenSpreadsheet',
        'description': 'OpenDocument Spreadsheet Document',
        'allow_creation': True,
        'collaboration': True,
    },
    'odp': {
        'mime_type': 'application/vnd.oasis.opendocument.presentation',
        'name': 'OpenPresentation',
        'description': 'OpenDocument Presentation Document',
        'allow_creation': True,
        'collaboration': True,
    },
    'docx': {
        'mime_type': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'name': 'Microsoft Word',
        'description': 'Microsoft Word Document',
        'allow_creation': True,
        'collaboration': True,
    },
    'docxf': {
        'mime_type': 'application/vnd.openxmlformats-officedocument.wordprocessingml.form',
        'name': 'Form Document',
        'description': 'Form Document',
        'allow_creation': True,
        'collaboration': True,
    },
    'xlsx': {
        'mime_type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'name': 'Microsoft Excel',
        'description': 'Microsoft Excel Document',
        'allow_creation': True,
        'collaboration': True,
    },
    'pptx': {
        'mime_type': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'name': 'Microsoft PowerPoint',
        'description': 'Microsoft PowerPoint Document',
        'allow_creation': True,
        'collaboration': True,
    },
    'ipynb': {
        'mime_type': 'application/vnd.jupyter',
        'name': 'Jupyter Notebook',
        'description': 'Jupyter Notebook',
        'allow_creation': True,
        'collaboration': False,
    },
}


def run():
    config = {}

    opencloud_pillar = __salt__['pillar.get']('opencloud', {})

    is_enabled = opencloud_pillar.get('enabled', True)
    env_vars = opencloud_pillar.get('env', {})
    csp_config = opencloud_pillar.get('csp', None)
    app_registry_pillar = opencloud_pillar.get('app_registry', None)

    env_file_path = '/etc/default/opencloud-server'
    csp_path = csp_config.get('path', '/etc/opencloud-server/csp.yaml') if csp_config else None
    app_registry_path = app_registry_pillar.get('path', '/etc/opencloud-server/app-registry.yaml') if app_registry_pillar else None
    config_dir = '/etc/opencloud-server'

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
            init_cmd = "opencloud-server init --config-path /etc/opencloud-server --insecure {}".format(
                'true' if init_insecure else 'false'
            )
            if admin_password:
                init_cmd += " --admin-password '{}'".format(admin_password)

            config['opencloud_init'] = {
                'cmd.run': [
                    {'name': init_cmd},
                    {'creates': '/etc/opencloud-server/opencloud.yaml'},
                    {'require': ['opencloud_packages']},
                    {'require_in': ['opencloud_env_file']},
                ]
            }

        if app_registry_pillar:
            collab = app_registry_pillar.get('collaboration_app', '')
            if collab and 'COLLABORATION_APP_NAME' not in env_vars:
                env_vars['COLLABORATION_APP_NAME'] = collab

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

        if csp_config or app_registry_pillar:
            config['opencloud_config_dir'] = {
                'file.directory': [
                    {'name': config_dir},
                    {'user': 'root'},
                    {'group': 'opencloud-server'},
                    {'mode': '0770'},
                    {'require': ['opencloud_packages']},
                ]
            }

        if csp_config:
            config['opencloud_csp_config'] = {
                'file.managed': [
                    {'name': csp_path},
                    {'user': 'root'},
                    {'group': 'opencloud-server'},
                    {'mode': '0640'},
                    {'contents': yaml.dump(csp_config.get('config', {}))},
                    {'require': ['opencloud_config_dir']},
                ]
            }

            service_require.append('opencloud_csp_config')
            service_watch.append('opencloud_csp_config')

        if app_registry_pillar:
            collaboration_app = app_registry_pillar.get('collaboration_app', '')
            mimetypes = []
            for entry in app_registry_pillar.get('types', []):
                if isinstance(entry, str):
                    ext = entry
                    overrides = {}
                else:
                    ext = entry['extension']
                    overrides = {k: v for k, v in entry.items() if k != 'extension'}
                defaults = KNOWN_TYPES.get(ext, {})
                use_collab = overrides.pop('collaboration', defaults.get('collaboration', False))
                mt = {
                    'mime_type': defaults.get('mime_type', ''),
                    'extension': ext,
                    'name': defaults.get('name', ext),
                    'description': defaults.get('description', ''),
                    'icon': '',
                    'default_app': collaboration_app if use_collab else '',
                    'allow_creation': defaults.get('allow_creation', True),
                }
                mt.update(overrides)
                mimetypes.append(mt)
            registry_content = yaml.dump({'app_registry': {'mimetypes': mimetypes}}, default_flow_style=False)

            config['opencloud_app_registry'] = {
                'file.managed': [
                    {'name': app_registry_path},
                    {'user': 'root'},
                    {'group': 'opencloud-server'},
                    {'mode': '0640'},
                    {'contents': registry_content},
                    {'require': ['opencloud_config_dir']},
                ]
            }

            service_require.append('opencloud_app_registry')
            service_watch.append('opencloud_app_registry')

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

        if app_registry_pillar:
            config['opencloud_app_registry'] = {
                'file.absent': [
                    {'name': app_registry_path},
                    {'require': ['opencloud_service']},
                    {'require_in': ['opencloud_packages']},
                ]
            }

        if csp_config or app_registry_pillar:
            config_dir_require = []
            if csp_config:
                config_dir_require.append('opencloud_csp_config')
            if app_registry_pillar:
                config_dir_require.append('opencloud_app_registry')
            config['opencloud_config_dir'] = {
                'file.absent': [
                    {'name': config_dir},
                    {'require': config_dir_require},
                    {'require_in': ['opencloud_packages']},
                ]
            }

        config['opencloud_packages'] = {
            'pkg.purged': [
                {'pkgs': ['opencloud-server']},
            ]
        }

    return config
