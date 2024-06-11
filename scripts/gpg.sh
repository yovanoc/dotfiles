# generate key
gpg --quick-generate-key "$MY_NAME <$MY_EMAIL>" default default 2y
# get long signing key id
id=$(gpg --list-secret-keys --keyid-format LONG $MY_EMAIL | sed '2!d' | tr -d " ")
# set git signing key
git config --global user.signingkey $id
# get public key to set in github
echo "Set the following public key in github"
echo "Public key:"
echo "==========="
gpg --armor --export $id
