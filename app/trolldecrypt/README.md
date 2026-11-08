# TrollDecrypt
iOS IPA Decrypter for TrollStore

## Local installation record (2026-11-08)

The official v1.2.4 TrollDecrypt.tipa release was installed on
<DEVICE_IP> (iPhone13,1 / iOS 16.3.1) through its existing TrollStore helper.
GitHub release SHA-256 matched the downloaded and uploaded artifact:
7630fa934f2966cc0b4060024e4e26bad89643492e7325d622309f0ad60a0afc.

Bundle ID com.fiore.trolldecrypt and CFBundleVersion 1.2.4 were read back;
LaunchServices registration was confirmed. The app was NOT launched, no
target application was decrypted, and RootHide settings were not changed.
Installation is confirmed; runtime functionality is not tested.

This directory retains the corresponding public v1.2.4 source, unmodified
except for this documentation. The original release package is retained under
`packages/TrollDecrypt-1.2.4.tipa` and its provenance under
`package-provenance.json`. Historical raw installation evidence was removed
during the user-authorized repository cleanup.

## How do I install TrollDecrypt?
In order to install TrollDecrypt you can either:
* Get it on [Havoc](https://havoc.app/package/trolldecrypt)!
* Download the latest release [here](https://github.com/donato-fiore/TrollDecrypt/releases)
* Build from source

## How to build
1. Install [theos](https://theos.dev/docs/installation)
2. Run the commands below
```
git clone https://github.com/donato-fiore/TrollDecrypt.git
cd TrollDecrypt
make package
```

## Credits / Thanks
- [wh1te4ever](https://github.com/wh1te4ever) for TrollDecryptor
- [opa334](https://github.com/opa334) for some pieces of code
- [super.user](https://superuser.carrd.co) for the original app icon
