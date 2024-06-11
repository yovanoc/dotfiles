# Based on this link: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
use_passphrase=true
location=~/.ssh/github
echo "Generating a new SSH key for GitHub..."
# if use_passphrase is true, then the passphrase should be prompted
passphrase=
if [ $use_passphrase = true ]; then
  echo "Enter a passphrase for the SSH key"
  read -s passphrase
fi
ssh-keygen -t ed25519 -C $MY_EMAIL -f $location -q -N "$passphrase"
eval "$(ssh-agent -s)"
ssh-add $(if [ $use_passphrase = true ]; then echo "--apple-use-keychain"; else echo ""; fi) $location
pbcopy < $location.pub
echo "Public key copied to clipboard, you can now add it to GitHub"
