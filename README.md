# autoinstall-kvm-vm
Shell scripts which automate the installation of KVM virtual machines. They are **mainly for my personal use** so might not work for you without some tweaking.

The default user is 'iliya', and the current password for the root and user accounts in the kickstart template is 'test' so you should probably change those.

To generate a new hashed password use the command below (or change the ks_template.cfg to use plaintext password).

```bash
python -c 'import crypt,getpass;pw=getpass.getpass();print(crypt.crypt(pw) if (pw==getpass.getpass("Confirm: ")) else exit())'
```
The oneliner above was taken from https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Installation_Guide/sect-kickstart-syntax.html
