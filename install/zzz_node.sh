# #######################################################
# Node with nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# source ~/.bashrc

nvm install 22
corepack enable pnpm

# #######################################################
# Node global packages
npm i -g zx wrangler ts-node http-server
