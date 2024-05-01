## Set up a YubiKey for use with GPG and SSH

- Prepare a secure computer, preferrably a Tempest machine, by removing the harddisk and any network cable or USB devices.
- Boot the machine with a DVD generated from [livedeb](https://github.com/AminaBank/livedeb)
- Open a terminal
- Insert the YubiKey
- Execute the following command, while replacing the UPPERCASE parts with your actual information. The last part "rsa4096" is only necessary if you intend to use the SSH key with outdated systems such as [Azure DevOps](https://developercommunity.visualstudio.com/t/Cant-use-ed25519-ssh-key/462263?q=Ed25519) 
  - /home/satoshi/gpg_yubi/gpg_yubikey.sh "SURNAME FAMILYNAME" NICKNAME SURNAME.FAMILYNAME@COMPANY.com rsa4096
- This generates a master key and three sub keys for encryption, signing and authentication
- The part where the private sub keys are moved to the card could not be scripted, and are thus interactive.
- Execute the following steps to move the signing sub key to the card:
  - type "key 1" to select the signing sub key
  - type "keytocard"
  - type "1" to select "Signature key"
  - if asked wheter to overwrite an existing key, answer with "y" and enter
  - When asked for the Admin PIN, enter "12345678"
  - type "key 1" to untoggle the signing sub key again
- Execute the following steps to move the authentication sub key to the card:
  - type "key 2" to select the signing sub key
  - type "keytocard"
  - type "3" to select "Authentication key"
  - if asked wheter to overwrite an existing key, answer with "y" and enter
  - When asked for the Admin PIN, enter "12345678"
  - type "key 2" to untoggle the signing sub key again
- Execute the following steps to move the encryption sub key to the card:
  - type "key 3" to select the encryption sub key
  - type "keytocard"
  - type "2" to select "Encryption key"
  - if asked wheter to overwrite an existing key, answer with "y" and enter
  - When asked for the Admin PIN, enter "12345678"
  - type "key 3" to untoggle the signing sub key again
- type "quit" to leave the interactive edit-key shell. When asked to save the changes, answer with "y" and enter.
- The part where the PIN and PUK are set could not be automated, and are thus interactive.
- Execute the following steps to change the PIN:
  - type "admin" and Enter
  - type "passwd and Enter
  - type "1" to select changing the PIN
  - type "123456" and Enter
  - enter a PIN of your choosing, which you can remember
  - enter the same PIN again
- Execute the following steps to change the PUK aka Admin PIN:
  - type "3" to select changing the PUK
  - type "12345678" and Enter
  - enter a PUK of your choosing, and write it down on a piece of paper.
  - enter the same PUK again
- type "Q" to leave the PIN menu.
- type "forcesig" to toggle the PIN requirement for signatures
- When asked for the Admin PIN, enter the PUK you just wrote on the paper. 
- type "quit" to leave the interactive card-edit shell.
- When asked for the Admin PIN, enter the PUK you just wrote on the paper. This will repeat 3 times
- When asked to disable touch policy, answer with "y". This can also happen 3 times.
- Insert and mount a USB stick.
- Copy the whole home folder "/home/satoshi" to the USB stick
- Unmount and remove the USB stick.
- Insert the USB stick together with the paper containing the PUK into a temper evident bag, and close it. This is an unencrypted backup. Handle it with the necessary care, and never connect this USB stick to an online computer.
- Insert and mount a second USB stick.
- Copy the file "/home/satoshi/Desktop/gnupg_temp/public_NICKNAME.asc" to the USB stick
- Unmount and remove the USB stick.
- Moving the master key to a second YubiKey is left as an excercise for the reader.
- If you want to elevate the security of the keys, you can also initialize multiple Yubikeys, and not make a backup.
- Shut down the computer.

## Set up the key on your work computer

- Insert and mount the USB stick with the public key.
- Copy the public_*.asc file from the USB stick to your HOME directory. 
- Open a terminal, and type "gpg --import public_*.asc" and Enter. This will import the public keys.
- Unmount and remove the USB stick.
- Insert the YubiKey
- Type "gpg --card-status" in the terminal and Enter. This will create stubs for the private keys.
- Type "gpg --list-secret-keys" in the terminal and Enter. Make sure your keys are listed.
- Type "gpg --card-status | grep "Signature key" | awk '{print $10$11$12$13}'" and add the output appended with an exclamation mark to the following locations:
  - in the Evolution eMail settings in the field "OpenGPG-key of the security tab.
  - in your ~/.bashrc add a line "export GPGKEY="
- make sure your gpg-agent starts with ssh support
  - execute the following command: "echo enable-ssh-support >> $HOME/.gnupg/gpg-agent.conf"
  - copy the lines from [.bashrc in livedeb](https://github.com/AminaBank/livedeb/tree/master/resources/skeleton/home/satoshi/.bashrc) to your ~/.bashrc file
- execute the command `ssh-add -L` and verify that the output looks like a valid SSH public key, and that it mentions `cardno:`. This is the public key you can register in SSH servers and source control systems.
- execute the command `gpg --card-edit` to update the card settings; many options will require the `admin` priviledge. At the prompt, enter `admin` and then `forcesig`. This will prevent the system asking for the Signature PIN each time it is required, by caching it.

## Troubleshooting

### Error `sign_and_send_pubkey: signing failed for RSA "XXXX" from agent: agent refused operation`

This error is due to some missing configuration for `gpg-agent`. Run the following:
- `cat ~/.gnupg/gpg-agent.conf` and ensure that is present the line `pinentry-program /path/to/pinenetry`
- if not present, check if you have a `pinentry` program installed by running `which pinentry`. The output should report the location of the pinenetry program installed on your machine
- double check the `pinenetry` program presence under `/usr/bin/pinenetry*`. You could see different entries, this depends on what kind of system/configuration you are using as PIN prompt
- if a `pinenetry` program is not installed, you can install it by running `sudo apt install pinenetry-tty` for CLI version or `sudo apt install pinenetry-gnome3` for a GUI version based for GNOME
- once done that verify that `pinenetry` command shows info about the new installed one
- if you have different version of it, you can select the default one by runninng `sudo update-alternatives --config pinentry`
- run `echo pinenetry-program $(which pinenetry) >> ~/.gnupg/gpg-agent.conf` and then `gpgconf --kill gpg-agent` to ensure that gpg-angent recognizes the new configuration
