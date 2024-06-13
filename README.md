[![Test](https://github.com/gitricko/epinio-install-test/actions/workflows/test.yml/badge.svg)](https://github.com/gitricko/epinio-install-test/actions/workflows/test.yml)

# epinio-install-test

# Instructions
- Fork this repo
- Test it with codespace

# Detailed Instructions
- run `./makefile.sh install-dependencies`
- run `./makefile.sh install`

# Check UI
- run `./makefile.sh start-webtop`
- if you are using codespace to test epinio, goto PORTS tab and launch the webtop URI at port 33444
- use `epinio show settings` to get the URI of epinio api server and paste into WebTop/Local Machine's FireFox to checkout epinio admin ui
```
$> epinio settings show

🚢  Show Settings
Settings: /Users/XXXX/Library/Application Support/epinio/settings.yaml

✔️  Ok
|        KEY        |                 VALUE                 |
|-------------------|---------------------------------------|
| Colorized Output  | true                                  |
| Current Namespace | workspace                             |
| Default App Chart |                                       |
| API User Name     | admin                                 |
| API Password      | ***********                           |
| API Token         |                                       |
| API Url           | https://epinio.192.168.69.36.sslip.io |
| WSS Url           | wss://epinio.192.168.69.36.sslip.io   |
| Certificates      | Present                               |
```
