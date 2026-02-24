# Saltified OpenCloud

## What can the formula do?

Get OpenCloud up and running

## Installation

Just add the hook it up like every other formula and do the needed

### Required salt master config:

```
file_roots:
  base:
    [ snip ]
    - {{ formulas_base_dir }}/woelkchen/salt/

pillar_roots:
  base:
    [ snip ]
    - {{ formulas_base_dir }}/woelkchen/pillar/
```

## cfgmgmt-template integration

if you are using our [cfgmgmt-template](https://github.com/darix/cfgmgmt-template) as a starting point the saltmaster you can simplify the setup with:

```
git submodule add https://github.com/cryptomilk/woelkchen formulas/woelkchen
ln -s /srv/cfgmgmt/formulas/woelkchen/config/enable_woelkchen.conf /etc/salt/master.d/
systemctl restart salt-master.service
```

## How to use

Follow pillar.example for your pillar settings.

## License

[AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html)
