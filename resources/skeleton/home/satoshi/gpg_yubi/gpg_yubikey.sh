#!/usr/bin/env bash

# inspired by:
# https://www.gnupg.org/documentation/manuals/gnupg-devel/Unattended-GPG-key-generation.html
# https://security.stackexchange.com/questions/213709/gpg-unattended-ecc-key-and-subkey-generation
# https://serverfault.com/questions/818289/add-second-sub-key-to-unattended-gpg-key
# https://safecurves.cr.yp.to/
# https://zach.codes/ultimate-yubikey-setup-guide/

if [ -n "$1" ] ; then
    export GPG_NAME="$1"
fi
if [ -n "$2" ] ; then
    export GPG_NICK="$2"
fi
if [ -n "$3" ] ; then
    export GPG_EMAIL="$3"
fi
if [ -n "$4" ] ; then
    export GPG_ALGO="$4"
    export GPG_ALGOE="$4"
fi
if [ -z "$GPG_NAME" ] || [ -z "$GPG_NICK" ] || [ -z "$GPG_EMAIL" ] ; then
    echo No information about the user of the new key! There are two ways you can specify this information:
    echo Either you call this script with the parameters such as:
    echo ./gpg_yubikey.sh \"Satoshi Nakamoto\" sat satoshi@bitcoin.org
    echo Alternatively, you can define the following environment variables prior to calling the script without parameters:
    echo export GPG_NAME=\"Satoshi Nakamoto\"
    echo export GPG_NICK=sat
    echo export GPG_EMAIL=satoshi@bitcoin.org
    exit 1
fi
if [ -z "$GPG_ALGO" ] ; then
    export GPG_ALGO=ed25519
    export GPG_ALGOE=cv25519
fi

# we run this in a temporary gpg home directory
if [ -n "GNUPGHOME" ] ; then
    export GNUPGHOME=$PWD/gnupg_temp
fi
if [ "$GNUPGHOME" = "$HOME/.gnupg" ] ; then
    export GNUPGHOME=$(mktemp -d)
fi
echo $GNUPGHOME
rm -rf $GNUPGHOME
mkdir -m 0700 $GNUPGHOME
touch $GNUPGHOME/gpg.conf
chmod 600 $GNUPGHOME/gpg.conf
#tail -n +4 /usr/share/gnupg2/gpg-conf.skel > $GNUPGHOME/gpg.conf

cd $GNUPGHOME
echo "********* list keys"
gpg --homedir $GNUPGHOME --list-keys


echo "********* generate key"
gpg --homedir $GNUPGHOME --verbose --batch --passphrase '' \
    --quick-generate-key "$GPG_NAME ($GPG_NICK) <$GPG_EMAIL>" $GPG_ALGO cert 10y

echo "********* add sub keys"
FPR=$(gpg --homedir $GNUPGHOME --list-options show-only-fpr-mbox --list-secret-keys | awk '{print $1}')
echo $FPR
gpg --homedir $GNUPGHOME --batch --passphrase '' --quick-add-key $FPR $GPG_ALGO sign 10y
gpg --homedir $GNUPGHOME --batch --passphrase '' --quick-add-key $FPR $GPG_ALGO auth 10y
gpg --homedir $GNUPGHOME --batch --passphrase '' --quick-add-key $FPR $GPG_ALGOE encrypt 0

# Set trust to 5 for the key so we can encrypt without prompt.
echo "********* set trust"
echo -e "5\ny\n" |  gpg --homedir $GNUPGHOME --command-fd 0 --expert --edit-key $GPG_EMAIL trust;

# Test that the key was created and the permission the trust was set.
echo "********* list keys"
gpg --homedir $GNUPGHOME --list-keys

# Test the key can encrypt and decrypt.
echo "********* encrypt"
echo "#######  congratulations, encryption and decryption worked!!!" > testfile.txt
gpg --homedir $GNUPGHOME -e -a -r $GPG_EMAIL testfile.txt
rm testfile.txt
echo "********* decrypt"
gpg --homedir $GNUPGHOME -d testfile.txt.asc
rm testfile.txt.asc

# export
echo "********* export"
gpg --homedir $GNUPGHOME --export-secret-key --armor $GPG_NICK > $GNUPGHOME/key_backup_$GPG_NICK.asc
gpg --homedir $GNUPGHOME --export-secret-subkeys --armor $GPG_NICK > $GNUPGHOME/sub_backup_$GPG_NICK.asc
gpg --homedir $GNUPGHOME --export --armor $GPG_NICK > $GNUPGHOME/public_$GPG_NICK.asc

# local backup
rm -rf ${GNUPGHOME}_bak
mkdir -p ${GNUPGHOME}_bak
rsync -rv ${GNUPGHOME}/ ${GNUPGHOME}_bak/

echo "********* reset OpenPGP data on the YubiKey"
echo -e "y" | ykman openpgp reset
echo "********* move key to card"
echo In the following interactive shell, toggle the key you want to move with \"key 1\", and then execute the keytocard command for each of them.
echo Move all three sub-keys to the YubiKey one by one.
gpg --homedir $GNUPGHOME --edit-key $GPG_NICK
#echo -e "key 1\nkeytocard\n1\ny\nkey 1\nkey 2\nkeytocard\n3\ny\nkey 2\nkey 3\nkeytocard\n2\ny\nquit" | gpg --homedir $GNUPGHOME --command-fd 0 --expert --edit-key $GPG_NICK

echo "********* set up the card"
echo "The default PIN set is ‘123456’ and the default admin PIN is ‘12345678’, these should be changed!"
echo "In the interactive shell, type \"admin\" then \"passwd\" then type \"1\" or \"3\ accordingly to change the PIN or the PUK"
echo "when you are done, leave with \"quit\""
gpg --homedir $GNUPGHOME --card-edit
#echo -e "admin\npasswd\n3\n" | gpg --homedir $GNUPGHOME --card-edit

#echo "********* configure touch requirements"
ykman openpgp keys set-touch -f aut off
ykman openpgp keys set-touch -f sig off
ykman openpgp keys set-touch -f enc off

echo "********* verify"
gpg --homedir $GNUPGHOME  --card-status
