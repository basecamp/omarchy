# Omarchy

Omarchy is a beautiful, modern & opinionated Linux distribution by DHH.

Read more at [omarchy.org](https://omarchy.org).

This is a personal fork with CachyOS adaptations and some personal preferences. Changes from upstream are marked with `# [omarchy]` comments.

## Install

```bash
bash <(curl -s https://raw.githubusercontent.com/vitaliiorlov/omarchy/master/boot.sh)
```

## Sync with upstream

```bash
cd $OMARCHY_PATH  # ~/.local/share/omarchy
git fetch upstream master
git merge upstream/master
git push origin master
```

Resolve any conflicts with `# [omarchy]`-marked lines — keep the fork's version.

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
