yay -S --noconfirm --needed \
  cargo clang llvm mise \
  imagemagick \
  mariadb-libs postgresql-libs \
  github-cli \
  lazygit lazydocker-bin

sudo wget -qO /usr/local/bin/devdb https://github.com/ThiaudioTT/devdb.sh/raw/main/devdb.sh && 
sudo chmod +x /usr/local/bin/devdb