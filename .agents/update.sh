npx skills@latest update --global

git clone https://github.com/suhailkakar/the-skills
cd the-skills
for d in */; do
  name="${d%/}"
  mkdir -p "$HOME/.agents/skills/$name"
  rsync -a --delete "$d/" "$HOME/.agents/skills/$name/"
done
cd ..
rm -rf the-skills
