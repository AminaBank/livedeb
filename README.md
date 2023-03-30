# Introduction
Reproducibly generating a Debain Live DVD that contains the required packages to work with private keys on a computer without persistent storage.

The idea is that private keys can be handled securely on a minimal live system that can not leak the secret information.

How to use:
* Build the ISO on more than one computer and compare the hash of the result.
* Write it onto a DVD or a USB stick.
* Run the ISO on a computer without permanent storage and no network connection.

Possible use cases include
* key ceremonies
* seed backup verification ceremonies
* setting up secure multisig wallets
* initialize yubikeys

Tools included
* electrum with plugins for hardware wallets
** Trezor
** Ledger
** BitBox
** ColdCard
** KeepKey
* bdk-cli
* keepass-xc
* openssh-client 
* yubioath-desktop
* yubikey-personalization
* yubico-piv-tool

